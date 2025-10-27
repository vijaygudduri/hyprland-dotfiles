#!/usr/bin/env bash
# battery-notify.sh — Hyprland battery notifier (DBus + UPower)
# Event-driven battery notifications (no startup notify, no actions)
# Low thresholds: 20, 15, 10, 5
# High thresholds: 85, 90, 95, 100

# --- CONFIGURATION (can be overridden by environment variables) ---
LOW_THRESHOLD=${BATTERY_NOTIFY_THRESHOLD_LOW:-20}
CRITICAL_THRESHOLD=${BATTERY_NOTIFY_THRESHOLD_CRITICAL:-10}
EMERGENCY_THRESHOLD=${BATTERY_NOTIFY_THRESHOLD_EMERGENCY:-5}

# --- UTILITIES ---
notify() {
    local urgency=$1 icon=$2 title=$3 msg=$4
    notify-send -a "Battery Notifier" --urgency="$urgency" --icon="$icon" --expire-time=8000 "$title" "$msg"
}

get_battery_info() {
    local battery total=0 count=0
    for battery in /sys/class/power_supply/BAT*; do
        [[ -f "$battery/capacity" ]] || continue
        capacity=$(<"$battery/capacity")
        status=$(<"$battery/status")
        total=$((total + capacity))
        ((count++))
    done

    if ((count > 0)); then
        battery_percentage=$((total / count))
    else
        battery_percentage=-1
    fi

    battery_status="$status"
    ((battery_percentage > 100)) && battery_percentage=100
    ((battery_percentage < 0)) && battery_percentage=0
}

# --- STATE TRACKING ---
last_low_notified=100
notified_charge_levels=()
last_status=""

# --- MAIN HANDLER ---
handle_status_change() {
    get_battery_info

    # --- Status Change Notifications ---
    if [[ "$battery_status" != "$last_status" ]]; then
        case "$battery_status" in
            "Charging"|"Not charging")
                notify normal battery-good "Charger Connected" "🔌 Battery at ${battery_percentage}%."
                last_low_notified=100
                ;;
            "Discharging")
                notify normal battery "On Battery" "🔋 Battery at ${battery_percentage}%."
                notified_charge_levels=()
                ;;
            "Full")
                notify normal battery-full "Battery Full" "✅ Please Unplug Charger."
                ;;
        esac
        last_status="$battery_status"
    fi

    # --- High Battery Notifications ---
    if [[ "$battery_status" == "Charging" || "$battery_status" == "Full" ]]; then
        for level in 100 95 90 85; do
            if ((battery_percentage >= level)); then
                if [[ ! " ${notified_charge_levels[*]} " =~ " ${level} " ]]; then
                    case "$level" in
                        100)
                            notify critical battery-full "Battery 100%" "💯 Fully charged — unplug now!"
                            ;;
                        95)
                            notify critical battery-full "Battery ${level}%" "🔋 Unplug to preserve battery health!"
                            ;;
                        *)
                            notify normal battery-good "Battery ${level}%" "🔋 Consider unplugging soon."
                            ;;
                    esac
                    notified_charge_levels+=("$level")
                fi
            fi
        done
    fi

    # --- Low Battery Notifications ---
    if [[ "$battery_status" == "Discharging" ]]; then
        for level in 20 15 10 5; do
            if ((battery_percentage <= level)); then
                local urgency="normal"
                [[ $level -le 10 ]] && urgency="critical"

                # Critical loop: repeat at ≤5% until charger connects
                if ((battery_percentage <= 5)); then
                    while true; do
                        get_battery_info
                        if [[ "$battery_status" == "Charging" || "$battery_status" == "Full" ]]; then
                            break
                        fi
                        if ((battery_percentage > 5)); then
                            break
                        fi
                        notify "$urgency" "battery-low" "⚠️ Critical Battery!" "Plug in immediately! Battery at ${battery_percentage}%."
                        sleep 1
                    done
                else
                    if ((battery_percentage < last_low_notified)); then
                        notify "$urgency" "battery-low" "⚠️ Low Battery" "Plug in! Battery at ${battery_percentage}%."
                        last_low_notified=$battery_percentage
                    fi
                fi
                break
            fi
        done
    fi
}

# --- MAIN LOOP (UPower Event-based) ---
main() {
    get_battery_info
    last_status="$battery_status"

    upower_path=$(upower -e | grep -m1 'battery')
    if [[ -z "$upower_path" ]]; then
        # Fallback polling (in case UPower fails)
        while true; do
            handle_status_change
            sleep 60
        done
    else
        dbus-monitor --system "type='signal',interface='org.freedesktop.DBus.Properties',path='$upower_path'" |
        while read -r line; do
            if [[ "$line" == *"PropertiesChanged"* ]]; then
                handle_status_change
            fi
        done
    fi
}

main
