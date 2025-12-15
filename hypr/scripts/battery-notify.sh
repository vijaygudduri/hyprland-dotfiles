#!/usr/bin/env bash

# ──────────────────────────────── LOGGING ────────────────────────────────

LOG="$HOME/.cache/battery-notify.log"
mkdir -p "$HOME/.cache"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" >> "$LOG"
}

# Log rotation
rotate_logs() {
    if [ -f "$LOG" ]; then
        local lines
        lines=$(wc -l < "$LOG")
        if [ "$lines" -gt 300 ]; then
            tail -n 300 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
        fi
    fi
}

log() {
    rotate_logs
    echo "$(date "+%F %T") - $*" >> "$LOG"
}

log "========== Battery Notify Script Starting =========="


# ──────────────────────────────── DEPENDENCIES ────────────────────────────────

REQUIRED_CMDS=(upower notify-send dbus-monitor grep awk sed flock)

for cmd in "${REQUIRED_CMDS[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Missing dependency: $cmd"
        exit 1
    fi
done


# ──────────────────────────────── SINGLE INSTANCE LOCK ────────────────────────────────

lockfile="${XDG_RUNTIME_DIR:-/tmp}/.battery-notify.lock"

# FD 9 is used exclusively for locking this file
exec 9>"$lockfile"

# If lock cannot be acquired → exit
if ! flock -n 9; then
    log "Another instance is already running — exiting."
    exit 0
fi

log "Acquired lock — running as single instance."


# ──────────────────────────────── CONFIGURATION ────────────────────────────────

# Thresholds for notifications
unplug_thresholds=(80 85 90 95 100)
low_thresholds=(20 15 10)
critical_threshold=5

# Flag file to ensure only one critical loop is running
CRITICAL_LOOP_LOCK="/tmp/.battery-critical-loop.lock"


# ──────────────────────────────── HELPER FUNCTIONS ────────────────────────────────

# Ensure a battery exists (not a desktop PC)
is_laptop() {
    if ! ls /sys/class/power_supply/BAT* >/dev/null 2>&1; then
        log "No battery detected — exiting."
        exit 0
    fi
}

# Read battery percentage + status (handles multi-battery laptops too)
get_battery_info() {
    local total=0 count=0

    for bat in /sys/class/power_supply/BAT*; do
        capacity=$(<"$bat/capacity")
        status=$(<"$bat/status")
        total=$((total + capacity))
        ((count++))
    done

    battery_percentage=$((total / count))
    battery_status=$status
}

# Select correct icon step (round to nearest 10)
battery_step_icon() {
    local perc=$1
    local step=$(( (perc + 5) / 10 * 10 ))
    ((step > 100)) && step=100
    echo "$step"
}

# Wrapper for sending notifications + logging
notify_battery() {
    local urgency="$1"
    local icon="$2"
    local title="$3"
    local message="$4"

    log "NOTIFY [$urgency] $title — $message"
    notify-send -u "$urgency" -i "$icon" "$title" "$message"
}


# ──────────────────────────────── MAIN EVENT HANDLER ────────────────────────────────

fn_status_change() {
    get_battery_info
    icon_step=$(battery_step_icon "$battery_percentage")

    log "BatteryStatus: $battery_status ($battery_percentage%) | Last: $last_status"

    # Ignore transient "Unknown" state (common during suspend/wake)
    if [[ "$battery_status" == "Unknown" ]]; then
        return
    fi

    # 1️⃣ Detect Plug / Unplug events
    if [[ "$battery_status" == "Discharging" && "$last_status" != "Discharging" ]]; then
        notify_battery normal "battery-level-$icon_step-symbolic" \
            "Charger Unplugged" "Battery at $battery_percentage%. You are now running on battery."
    elif [[ "$battery_status" != "Discharging" && "$last_status" == "Discharging" ]]; then
        notify_battery normal "battery-level-$icon_step-plugged-in-symbolic" \
            "Charger Plugged In" "Battery at $battery_percentage%. Charging started."
    fi

    last_status="$battery_status"


    # ──────────────────────────────── 2️⃣ DISCHARGING ────────────────────────────────
    if [[ "$battery_status" == "Discharging" ]]; then

        # LOW BATTERY (20%, 15%, 10%)
        for lvl in "${low_thresholds[@]}"; do
            if ((battery_percentage == lvl)) && [[ ! -f /tmp/.notified_low_$lvl ]]; then
                touch /tmp/.notified_low_$lvl

                case $lvl in
                    20) msg="Battery at 20% — consider plugging in.";   icon="battery-level-20-symbolic" ;;
                    15) msg="Battery at 15% — low power.";              icon="battery-level-10-symbolic" ;;
                    10) msg="Battery at 10% — critically low.";         icon="battery-level-0-symbolic"  ;;
                esac

                notify_battery critical "$icon" "Battery Low" "$msg"
            fi
        done

        # CRITICAL LOOP BELOW 5%
        if ((battery_percentage <= critical_threshold)); then

            if [[ ! -f "$CRITICAL_LOOP_LOCK" ]]; then
                touch "$CRITICAL_LOOP_LOCK"

                (
                    while :; do
                        get_battery_info

                        # Stop loop when charging or level rises
                        if [[ "$battery_status" != "Discharging" || $battery_percentage -gt $critical_threshold ]]; then
                            rm -f "$CRITICAL_LOOP_LOCK"
                            break
                        fi

                        notify_battery critical "battery-level-0-symbolic" \
                            "Battery Critical" \
                            "Battery under 5% — plug in immediately!"

                        sleep 2
                    done
                ) &
            fi
        fi

        # Reset charging-related flags
        rm -f /tmp/.notified_unplug_*
    fi


    # ──────────────────────────────── 3️⃣ CHARGING ────────────────────────────────
    if [[ "$battery_status" == "Charging" || "$battery_status" == "NotCharging" || "$battery_status" == "FullyCharged" ]]; then

        # CHARGING MESSAGES (80%, 85%, 90%, 95%, 100%)
        for lvl in "${unplug_thresholds[@]}"; do
            if ((battery_percentage == lvl)) && [[ ! -f /tmp/.notified_unplug_$lvl ]]; then
                touch /tmp/.notified_unplug_$lvl

                case $lvl in
                    80)  msg="Battery at 80% — good time to unplug.";     icon="battery-level-80-charging-symbolic" ;;
                    85)  msg="Battery at 85% - unplug please";            icon="battery-level-80-charging-symbolic" ;;
                    90)  msg="Battery at 90% - unplug the cable";         icon="battery-level-90-charging-symbolic" ;;
                    95)  msg="Battery at 95% - lets remove the cord";     icon="battery-level-90-charging-symbolic" ;;
                    100) msg="Battery fully charged - Please unplug";     icon="battery-level-100-charged-symbolic" ;;
                esac

                notify_battery normal "$icon" "Battery Charged" "$msg"
            fi
        done

        # Reset low battery flags + stop critical loop when plugged in
        rm -f /tmp/.notified_low_* "$CRITICAL_LOOP_LOCK"
    fi
}


# ──────────────────────────────── CLEANUP ────────────────────────────────

cleanup() {
    log "Cleaning up flag files..."
    rm -f /tmp/.notified_low_* /tmp/.notified_unplug_* "$CRITICAL_LOOP_LOCK"
    log "Exiting."
    exit
}

trap cleanup INT TERM HUP


# ──────────────────────────────── MAIN ────────────────────────────────

main() {
    is_laptop

    # Clean start
    rm -f /tmp/.notified_low_* /tmp/.notified_unplug_* "$CRITICAL_LOOP_LOCK"

    get_battery_info
    last_status="$battery_status"

    # First evaluation
    fn_status_change

    # Get DBus battery path
    battery_path=$(upower -e | grep battery | head -n 1)
    [[ -z "$battery_path" ]] && exit 1

    # Listen for state/percentage changes live
    stdbuf -oL dbus-monitor --system \
        "type='signal',interface='org.freedesktop.DBus.Properties',path='$battery_path'" \
    | grep --line-buffered -E "Percentage|State" \
    | while read -r _; do
        fn_status_change
    done
}

main
