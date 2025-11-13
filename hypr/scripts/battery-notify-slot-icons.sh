#!/usr/bin/env bash

# Fixed ID for replacing old notifications
NOTIFY_ID=144321

lockfile="${XDG_RUNTIME_DIR:-/tmp}/.battery-notify.lock"
exec 9>"$lockfile"
if ! flock -n 9; then
    echo "Battery notifier already running."
    exit 0
fi

# ────────────────────────────── CONFIG ──────────────────────────────
unplug_thresholds=(85 90 95 100)
low_thresholds=(20 15 10)
critical_threshold=5

# ────────────────────────────── SLOT ICON FUNCTIONS ─────────────────────────────
# Slot theme uses:
# battery-030-symbolic.svg
# battery-030-charging.svg
# battery-100.svg
# battery-100-charging.svg

icon_discharging() {
    local pct="$1"
    echo "battery-${pct}-symbolic"
}

icon_charging() {
    local pct="$1"
    echo "battery-${pct}-charging"
}

# Padded percentage steps for Slot theme
percentage_to_step() {
    local perc=$1
    if   (( perc <= 10 )); then echo 010
    elif (( perc <= 20 )); then echo 020
    elif (( perc <= 30 )); then echo 030
    elif (( perc <= 40 )); then echo 040
    elif (( perc <= 50 )); then echo 050
    elif (( perc <= 60 )); then echo 060
    elif (( perc <= 70 )); then echo 070
    elif (( perc <= 80 )); then echo 080
    elif (( perc <= 90 )); then echo 090
    else echo 100
    fi
}

notify_battery() {
    local urgency=$1
    local icon=$2
    local title=$3
    local msg=$4
    notify-send -a "Power Notify" -t 5000 -u "$urgency" -i "$icon" -r "$NOTIFY_ID" "$title" "$msg"
}

# ────────────────────────────── HELPERS ──────────────────────────────
get_battery_info() {
    local total_pct=0 count=0
    for battery in /sys/class/power_supply/BAT*; do
        local status=$(<"$battery/status")
        local capacity=$(<"$battery/capacity")
        if [[ -n "$status" && "$capacity" =~ ^[0-9]+$ ]]; then
            battery_status="$status"
            total_pct=$((total_pct + capacity))
            ((count++))
        fi
    done
    ((count > 0)) || exit 1
    battery_percentage=$((total_pct / count))
}

# ────────────────────────────── LOGIC ──────────────────────────────
fn_status_change() {
    get_battery_info

    local step_icon=$(percentage_to_step "$battery_percentage")
    local icon_base="$(icon_discharging "$step_icon")"
    local icon_chg="$(icon_charging "$step_icon")"

    # Plug/unplug notifications
    if [[ "$battery_status" == "Discharging" && "$last_status" != "Discharging" && -n "$last_status" ]]; then
        notify_battery normal "$icon_base" "Charger Unplugged" "Battery at $battery_percentage%"
    elif [[ "$battery_status" != "Discharging" && "$last_status" == "Discharging" ]]; then
        notify_battery normal "$icon_chg" "Charger Plugged In" "Battery at $battery_percentage%"
    fi
    last_status="$battery_status"

    case "$battery_status" in
        Discharging)
            # Low battery notifications
            for lvl in "${low_thresholds[@]}"; do
                if (( battery_percentage == lvl )) && [[ ! -f /tmp/.notified_low_$lvl ]]; then
                    touch /tmp/.notified_low_$lvl
                    case $lvl in
                        20) msg="Battery at $battery_percentage%. This is your early warning tweet, plugin the charger now 📣" ;;
                        15) msg="Battery at $battery_percentage%. Okay seriously… maybe plug it in before it starts begging 🙏" ;;
                        10) msg="Battery at $battery_percentage%! Red alert! We're entering the last chapter. Save your work! 🚨" ;;
                    esac
                    notify_battery critical "$icon_base" "Battery Low" "$msg"
                fi
            done

            # Critical loop at 5%
            if (( battery_percentage <= critical_threshold )); then
                while true; do
                    get_battery_info
                    (( battery_percentage > critical_threshold )) && break
                    [[ "$battery_status" != "Discharging" ]] && break

                    notify_battery critical "battery-000" \
                        "Battery Critically Low" "Battery at $battery_percentage% — PLUG IN RIGHT NOW ⚡"

                    sleep 2
                done &
            fi

            # Reset unplug notifications
            for lvl in "${unplug_thresholds[@]}"; do
                rm -f /tmp/.notified_unplug_$lvl 2>/dev/null
            done
            ;;
        Charging|NotCharging|Unknown)
            # Unplug notifications
            for lvl in "${unplug_thresholds[@]}"; do
                if (( battery_percentage == lvl )) && [[ ! -f /tmp/.notified_unplug_$lvl ]]; then
                    touch /tmp/.notified_unplug_$lvl
                    case $lvl in
                        85) msg="Battery at $battery_percentage%. The prophecy says: unplug at this point 🧙‍♂️✨" ;;
                        90) msg="Battery at $battery_percentage%. Stop now. More charging won't make it smarter 😅" ;;
                        95) msg="Battery at $battery_percentage%. That's plenty. Give the poor charger a break 😌" ;;
                        100) msg="Battery fully charged ($battery_percentage%). I'm full, bro… why are we still charging? 😵" ;;
                    esac
                    # 100%-charging exists in Slot, so this works:
                    notify_battery critical "$icon_chg" "Battery Charged" "$msg"
                fi
            done

            # Reset low flags
            for lvl in "${low_thresholds[@]}"; do
                rm -f /tmp/.notified_low_$lvl 2>/dev/null
            done
            ;;
    esac
}

# ────────────────────────────── MAIN ──────────────────────────────
is_laptop() {
    ls /sys/class/power_supply/BAT* >/dev/null 2>&1 || exit 0
}

_cleanup() {
    rm -f /tmp/.notified_low_* /tmp/.notified_unplug_*
    exit
}
trap _cleanup SIGINT SIGTERM

main() {
    is_laptop

    battery_dbus_path=$(upower -e | grep battery | head -n 1)
    [[ -z "$battery_dbus_path" ]] && exit 1

    stdbuf -oL dbus-monitor --system \
        "type='signal',interface='org.freedesktop.DBus.Properties',path='$battery_dbus_path'" |
        grep --line-buffered -E "Percentage|State" |
        while read -r _; do fn_status_change; done
}

main
