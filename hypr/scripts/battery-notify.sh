#!/usr/bin/env bash

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
notify_icon="battery-level"

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

percentage_to_step() {
    local perc=$1
    local step=$(((perc + 5) / 10 * 10))
    (( step > 100 )) && step=100
    (( step < 0 )) && step=0
    echo "$step"
}

notify_battery() {
    local urgency=$1
    local icon=$2
    local title=$3
    local msg=$4
    notify-send -a "Power Notify" -t 5000 -u "$urgency" -i "$icon" "$title" "$msg"
}

# ────────────────────────────── LOGIC ──────────────────────────────
fn_status_change() {
    get_battery_info

    local step_icon=$(percentage_to_step "$battery_percentage")
    local icon_base="$notify_icon-$step_icon-symbolic"

    # Only notify once when transitioning from non-Discharging to Discharging
    if [[ "$battery_status" == "Discharging" && "$last_status" != "Discharging" && -n "$last_status" ]]; then
        notify_battery normal "$icon_base" "Charger Unplugged" "Battery at $battery_percentage%"
    elif [[ "$battery_status" != "Discharging" && "$last_status" == "Discharging" ]]; then
        notify_battery normal "$notify_icon-$step_icon-charging-symbolic" "Charger Plugged In" "Battery at $battery_percentage%"
    fi
    last_status="$battery_status"

    case "$battery_status" in
        Discharging)
            # Low battery fixed points
            for lvl in "${low_thresholds[@]}"; do
                if (( battery_percentage == lvl )) && [[ ! -f /tmp/.notified_low_$lvl ]]; then
                    touch /tmp/.notified_low_$lvl
                    case $lvl in
                        20)  msg="Battery at $battery_percentage%. Not critical yet, but maybe start looking for that charger 👀" ;;
                        15)  msg="Battery at $battery_percentage%. Okay seriously… maybe plug it in before it starts begging 🙏" ;;
                        10)  msg="Battery at $battery_percentage%! Danger zone! Your laptop is running on pure hope now 😬" ;;
                    esac
                    notify_battery critical "$icon_base" "Battery Low" "$msg"
                fi
            done

            # Critical repeated alert loop
            if (( battery_percentage <= critical_threshold )) && [[ "$battery_status" == "Discharging" ]]; then
                echo "Entering critical loop at ${battery_percentage}%..."
                while true; do
                    get_battery_info
                    if [[ "$battery_status" != "Discharging" ]] || (( battery_percentage > critical_threshold )); then
                        echo "Exiting critical loop — charging or above threshold."
                        break
                    fi
                    notify_battery critical "xfce4-battery-critical" \
                        "Battery Critically Low" "Battery at $battery_percentage% — Plug in Right NOW! ⚡"
                    sleep 1
                done &
            fi


            # Reset unplug flags (for next charge cycle)
            for lvl in "${unplug_thresholds[@]}"; do
                rm -f /tmp/.notified_unplug_$lvl 2>/dev/null
            done
            ;;
        Charging|NotCharging|Unknown)
            # Unplug charger fixed points
            for lvl in "${unplug_thresholds[@]}"; do
                if (( battery_percentage == lvl )) && [[ ! -f /tmp/.notified_unplug_$lvl ]]; then
                    touch /tmp/.notified_unplug_$lvl
                    case $lvl in
                        85)  msg="Battery at $battery_percentage%. Time to unplug and let it breathe 🌿" ;;
                        90)  msg="Battery at $battery_percentage%. That's plenty. Give the poor charger a break 😌" ;;
                        95)  msg="Battery at $battery_percentage%. Overachiever detected. Stop overfeeding it 🍔" ;;
                        100) msg="Battery fully charged ($battery_percentage%). Unplug me before I turn into a toaster 🔥" ;;
                    esac
                    notify_battery critical "$notify_icon-$step_icon-charging-symbolic" "Battery Charged" "$msg"
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
    ls /sys/class/power_supply/BAT* >/dev/null 2>&1 || {
        echo "No battery detected. Exiting." >&2
        exit 0
    }
}

_cleanup() {
    echo "Stopping battery notifier..."
    rm -f /tmp/.notified_low_* /tmp/.notified_unplug_*
    exit
}
trap _cleanup SIGINT SIGTERM

main() {
    is_laptop

    battery_dbus_path=$(upower -e | grep battery | head -n 1)
    if [[ -z "$battery_dbus_path" ]]; then
        echo "No D-Bus battery path found. Exiting."
        exit 1
    fi

    echo "Monitoring battery D-Bus events on $battery_dbus_path"
    stdbuf -oL dbus-monitor --system "type='signal',interface='org.freedesktop.DBus.Properties',path='$battery_dbus_path'" |
    grep --line-buffered -E "Percentage|State" |
    while read -r _; do
        fn_status_change
    done
}

main
