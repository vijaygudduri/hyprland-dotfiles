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

# Round % to nearest 10% step (GNOME/Tela standard)
battery_step_icon() {
    local perc=$1
    local step=$(( (perc + 5) / 10 * 10 ))
    (( step > 100 )) && step=100
    (( step < 0 )) && step=0
    echo "$step"
}

notify_battery() {
    notify-send -t 5000 -u "$1" -i "$2" "$3" "$4"
}

# ────────────────────────────── MAIN LOGIC ──────────────────────────────

fn_status_change() {
    get_battery_info
    icon_step=$(battery_step_icon "$battery_percentage")

    # Plug/unplug notifications (with direct inline icon)
    if [[ "$battery_status" == "Discharging" && "$last_status" != "Discharging" && -n "$last_status" ]]; then
        notify_battery normal "battery-level-$icon_step-symbolic" \
            "Charger Unplugged" "Battery at $battery_percentage%"
    elif [[ "$battery_status" != "Discharging" && "$last_status" == "Discharging" ]]; then
        notify_battery normal "battery-level-$icon_step-plugged-in-symbolic" \
            "Charger Plugged In" "Battery at $battery_percentage%"
    fi

    last_status="$battery_status"

    case "$battery_status" in

        # ──────────────────────────── DISCHARGING ────────────────────────────
        Discharging)

            # Low battery fixed notifications
            for lvl in "${low_thresholds[@]}"; do
                if (( battery_percentage == lvl )) && [[ ! -f /tmp/.notified_low_$lvl ]]; then
                    touch /tmp/.notified_low_$lvl

                    case $lvl in
                        20)
                            msg="Battery at $battery_percentage%. This is your early warning, plugin the charger now 📣"
                            notify_icon="battery-level-20-symbolic"
                            ;;
                        15)
                            msg="Battery at $battery_percentage%. Please plugin the charger bro, I'm begging 🙏"
                            notify_icon="battery-level-10-symbolic"
                            ;;
                        10)
                            msg="Battery at $battery_percentage%! Red alert! We're entering the last chapter. Save your work! 🚨"
                            notify_icon="battery-level-0-symbolic"
                            ;;
                    esac

                    notify_battery critical "$notify_icon" "Battery Low" "$msg"
                fi
            done

            # Critical loop (every second)
            if (( battery_percentage <= critical_threshold )); then
                while true; do
                    get_battery_info
                    if [[ "$battery_status" != "Discharging" ]] || (( battery_percentage > critical_threshold )); then
                        break
                    fi

                    notify_battery critical "battery-level-0-symbolic" \
                        "Battery Critically Low" \
                        "Battery at $battery_percentage% — Just few more mins left, PLUG IN RIGHT NOW! ⚡"

                    sleep 2
                done &
            fi

            # Reset unplug flags when discharging
            for lvl in "${unplug_thresholds[@]}"; do
                rm -f /tmp/.notified_unplug_$lvl
            done
            ;;

        # ─────────────────────────── CHARGING ─────────────────────────────
        Charging|NotCharging|Unknown)

            # Unplug charger fixed notifications
            for lvl in "${unplug_thresholds[@]}"; do
                if (( battery_percentage == lvl )) && [[ ! -f /tmp/.notified_unplug_$lvl ]]; then
                    touch /tmp/.notified_unplug_$lvl

                    case $lvl in
                        85)
                            msg="Battery at $battery_percentage%. The prophecy says: unplug at this point 🧙‍♂️✨"
                            icon="battery-level-80-charging-symbolic"
                            ;;
                        90)
                            msg="Battery at $battery_percentage%. Stop now. More charging won't make it smarter 😅"
                            icon="battery-level-90-charging-symbolic"
                            ;;
                        95)
                            msg="Battery at $battery_percentage%. That's plenty. Give the poor charger a break 😌"
                            icon="battery-level-90-charging-symbolic"
                            ;;
                        100)
                            msg="Battery fully charged ($battery_percentage%). I'm full, bro… why are we still charging? 😵"
                            icon="battery-level-100-charged-symbolic"
                            ;;
                    esac

                    notify_battery critical "$icon" "Battery Charged" "$msg"
                fi
            done

            # Reset low battery flags when charging
            for lvl in "${low_thresholds[@]}"; do
                rm -f /tmp/.notified_low_$lvl
            done
            ;;

    esac
}

# ────────────────────────────── INIT ──────────────────────────────

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

    # Remove stale flags left by kill -9 or previous crash
    rm -f /tmp/.notified_low_* /tmp/.notified_unplug_* /tmp/.notified_critical_* /tmp/.notified_charged_* 2>/dev/null

    battery_dbus_path=$(upower -e | grep battery | head -n 1)
    [[ -z "$battery_dbus_path" ]] && exit 1

    stdbuf -oL dbus-monitor --system \
        "type='signal',interface='org.freedesktop.DBus.Properties',path='$battery_dbus_path'" \
    | grep --line-buffered -E "Percentage|State" \
    | while read -r _; do
        fn_status_change
    done
}

main
