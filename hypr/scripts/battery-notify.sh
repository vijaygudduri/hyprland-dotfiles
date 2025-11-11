#!/usr/bin/env bash

lockfile="${XDG_RUNTIME_DIR:-/tmp}/.battery-notify.lock"
exec 9>"$lockfile"
if ! flock -n 9; then
    echo "Battery notifier already running."
    exit 0
fi

# Default configuration (can override via environment variables)
battery_full_threshold=${BATTERY_NOTIFY_THRESHOLD_FULL:-100}
battery_critical_threshold=${BATTERY_NOTIFY_THRESHOLD_CRITICAL:-5}
unplug_charger_threshold=${BATTERY_NOTIFY_THRESHOLD_UNPLUG:-85}
battery_low_threshold=${BATTERY_NOTIFY_THRESHOLD_LOW:-20}
timer=${BATTERY_NOTIFY_TIMER:-200}          # Seconds before executing critical action
notify_interval_minutes=${BATTERY_NOTIFY_NOTIFY:-30} # Minutes between 'Battery Full' notifications
interval=${BATTERY_NOTIFY_INTERVAL:-5}      # Percentage steps for low/unplug notifications
execute_critical=${BATTERY_NOTIFY_EXECUTE_CRITICAL:-"systemctl suspend"}
execute_low=${BATTERY_NOTIFY_EXECUTE_LOW:-}
execute_unplug=${BATTERY_NOTIFY_EXECUTE_UNPLUG:-}
execute_charging=${BATTERY_NOTIFY_EXECUTE_CHARGING:-}
execute_discharging=${BATTERY_NOTIFY_EXECUTE_DISCHARGING:-}
dock_mode=${BATTERY_NOTIFY_DOCK:-false}     # Disable notifications on status change if true
verbose=false

# Separate tracker for low battery notifications
last_low_notified_percentage=-1

# Show configuration info
config_info() {
    cat <<EOF
Current Battery Notification Configuration:

      STATUS        THRESHOLD      INTERVAL
      Full          $battery_full_threshold      $notify_interval_minutes Minutes
      Critical      $battery_critical_threshold  $timer Seconds then '$execute_critical'
      Low           $battery_low_threshold       $interval Percent then '$execute_low'
      Unplug        $unplug_charger_threshold    $interval Percent then '$execute_unplug'

      Command on Charging: $execute_charging
      Command on Discharging: $execute_discharging
      Dock Mode: $dock_mode (no notifications on status change)

EOF
}

# Check for battery presence (laptop)
is_laptop() {
    if ls /sys/class/power_supply/BAT* >/dev/null 2>&1; then
        return 0
    else
        echo "No battery detected. Exiting." >&2
        exit 0
    fi
}

# Verbose output
fn_verbose() {
    if $verbose; then
        cat <<VERBOSE
=============================================
        Battery Status: $battery_status
        Battery Percentage: $battery_percentage
=============================================
VERBOSE
    fi
}

# Convert percentage to icon step
percentage_to_step() {
    local perc=$1
    local step=$(((perc + 5) / 10 * 10))
    (( step > 100 )) && step=100
    (( step < 0 )) && step=0
    echo "$step"
}

# Gather battery data
get_battery_info() {
    local total_pct=0
    local count=0
    for battery in /sys/class/power_supply/BAT*; do
        local status=$(cat "$battery/status" 2>/dev/null)
        local capacity=$(cat "$battery/capacity" 2>/dev/null)
        if [[ -n "$status" && "$capacity" =~ ^[0-9]+$ ]]; then
            battery_status="$status"
            total_pct=$(( total_pct + capacity ))
            count=$(( count + 1 ))
        fi
    done
    if (( count > 0 )); then
        battery_percentage=$(( total_pct / count ))
    else
        echo "ERROR: No battery info found." >&2
        exit 1
    fi
}

# Execute critical action (e.g., suspend)
fn_action() {
    if [[ $battery_status == Discharging* ]]; then
        if $verbose; then echo "Executing critical command: $execute_critical"; fi
        nohup $execute_critical &>/dev/null &
    fi
}

# Notification logic on percentage changes
fn_percentage() {
    local delta=$(( battery_percentage - last_notified_percentage ))

    # Unplug notification
    if (( battery_percentage >= unplug_charger_threshold )) && [[ "$battery_status" != "Discharging" ]] && [[ "$battery_status" != "Full" ]] && (( delta >= interval )); then
        local icon=$(percentage_to_step "$battery_percentage")
        if $verbose; then echo "Notify: Unplug threshold reached"; fi
        notify-send -a "Power Notify" -t 5000 -r 5 -u critical -i "battery-level-$icon-charging-symbolic" \
            "Battery Charged" "Battery at $battery_percentage%. Please Unplug the Charger, it's enough"
        last_notified_percentage=$battery_percentage
    fi

    # Critical low battery countdown
    if (( battery_percentage <= battery_critical_threshold )); then
        local count=$timer
        while (( count > 0 )) && [[ $battery_status == Discharging* ]]; do
            get_battery_info
            if [[ $battery_status != Discharging* ]]; then break; fi
            notify-send -a "Power Notify" -t 5000 -r 5 -u critical -i "xfce4-battery-critical" \
                "Battery Critically Low" "$battery_percentage% is critically low, it will be dead soon. Suspending in $(( count / 60 )):$(( count % 60 )) ..."
            (( count-- ))
            sleep 1
        done
        (( count == 0 )) && fn_action
    fi

    # Low battery warning notification with separate tracking
    if (( battery_percentage <= battery_low_threshold )) && [[ "$battery_status" == Discharging* ]]; then
        local low_delta=$(( last_low_notified_percentage < 0 ? interval + 1 : last_low_notified_percentage - battery_percentage ))
        if (( low_delta >= interval )); then
            local icon=$(percentage_to_step "$battery_percentage")
            if $verbose; then echo "Notify: Low battery threshold"; fi
            notify-send -a "Power Notify" -t 5000 -r 5 -u critical -i "battery-level-$icon-symbolic" \
                "Battery Low" "Battery at $battery_percentage%. Please Connect the Charger, I beg you🙏"
            last_low_notified_percentage=$battery_percentage
        fi
    fi
}

# Handle overall battery status changes and notifications
fn_status() {
    if (( battery_percentage >= battery_full_threshold )) && [[ "$battery_status" != Discharging* ]]; then
        battery_status="Full"
    fi

    case "$battery_status" in
        Discharging)
            if $verbose; then echo "Discharging at $battery_percentage%"; fi
            if [[ "$prev_status" != "Discharging" || "$prev_status" == "Full" ]]; then
                prev_status="Discharging"
                local urgency="normal"
                if (( battery_percentage <= battery_low_threshold )); then urgency="critical"; fi
                local icon=$(percentage_to_step "$battery_percentage")
                notify-send -a "Power Notify" -t 5000 -r 5 -u "$urgency" -i "battery-level-$icon-symbolic" \
                    "Charger Unplugged" "Battery at $battery_percentage%"
                $execute_discharging
            fi
            fn_percentage
            ;;
        Charging|NotCharging|Unknown)
            if $verbose; then echo "Charging or other status at $battery_percentage%"; fi
            if [[ "$prev_status" != "$battery_status" || "$prev_status" == "Discharging" ]]; then
                prev_status="$battery_status"
                local urgency="normal"
                if (( battery_percentage >= unplug_charger_threshold )); then urgency="critical"; fi
                local icon=$(percentage_to_step "$battery_percentage")
                notify-send -a "Power Notify" -t 5000 -r 5 -u "$urgency" -i "battery-level-$icon-charging-symbolic" \
                    "Charger Plugged In" "Battery at $battery_percentage%"
                $execute_charging
            fi
            fn_percentage
            ;;
        Full)
            if $verbose; then echo "Battery Full at $battery_percentage%"; fi
            if [[ "$prev_status" != "Full" ]]; then
                local now=$(date +%s)
                if [[ "$prev_status" =~ ^(Charging|NotCharging|Discharging)$ ]] && (( now - lt >= notify_interval_minutes * 60 )); then
                    notify-send -a "Power Notify" -t 5000 -r 5 -u critical -i "battery-full-charging-symbolic" \
                        "Battery Full" "Please unplug the charger"
                    prev_status="Full"
                    lt=$now
                    $execute_charging
                fi
            fi
            ;;
        *)
            if [[ -z "$battery_status" ]]; then
                echo "Battery status empty" >&2
            elif [[ ! -f "/tmp/battery.notify.status.fallback.$battery_status-$$" ]]; then
                echo "Unknown battery status '$battery_status'" >&2
                touch "/tmp/battery.notify.status.fallback.$battery_status-$$"
            fi
            fn_percentage
            ;;
    esac
}

# On battery status or percentage change
fn_status_change() {
    get_battery_info

    local executed_low=false
    local executed_unplug=false

    if [[ "$battery_status" != "$last_battery_status" ]] || [[ "$battery_percentage" != "$last_battery_percentage" ]]; then
        last_battery_status=$battery_status
        last_battery_percentage=$battery_percentage
        fn_verbose
        fn_percentage

        if (( battery_percentage <= battery_low_threshold )) && ! $executed_low; then
            $execute_low
            executed_low=true
        fi

        if (( battery_percentage >= unplug_charger_threshold )) && ! $executed_unplug; then
            $execute_unplug
            executed_unplug=true
        fi

        if ! $dock_mode; then
            fn_status
        fi
    fi
}

# Graceful exit
_cleanup() {
    echo "Stopping battery monitor..."
    exit
}
trap _cleanup SIGINT SIGTERM

main() {
    config_info

    if $verbose; then echo "Verbose mode enabled"; fi

    is_laptop

    get_battery_info

    last_notified_percentage=$battery_percentage
    prev_status=$battery_status
    lt=$(date +%s)

    battery_dbus_path=$(upower -e | grep battery | head -n 1)

    if [[ -z "$battery_dbus_path" ]]; then
        echo "No D-Bus path found, falling back to polling..."
        while true; do
            fn_status_change
            sleep 30
        done
    else
        echo "Monitoring D-Bus on $battery_dbus_path"
        dbus-monitor --system "type='signal',interface='org.freedesktop.DBus.Properties',path='$battery_dbus_path'" 2>/dev/null | while read -r; do
            fn_status_change
        done
    fi
}

case "$1" in
    -i|--info)
        config_info
        exit 0
        ;;
    -v|--verbose)
        verbose=true
        ;;
    -h|--help)
        cat <<HELP
Usage: $0 [options]

Options:
  -i | --info       Show current configuration
  -v | --verbose    Enable verbose output
  -h | --help       Show this help message
HELP
        exit 0
        ;;
    "")
        ;;
    *)
        echo "Unknown option: $1"
        exit 1
        ;;
esac

main
