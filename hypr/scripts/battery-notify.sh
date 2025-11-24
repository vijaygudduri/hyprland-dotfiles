#!/usr/bin/env bash

# ────────────────────────────── LOGGING SETUP ──────────────────────────────

LOG="$HOME/.cache/battery-notify.log"
mkdir -p "$HOME/.cache"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" >> "$LOG"
}

log "===================== Battery Notify Script Starting ====================="

# ── LOG ROTATION: Keep only the last 250 log entries ───────────────────────
if [ -f "$LOG" ]; then
    line_count=$(wc -l < "$LOG")
    if (( line_count > 250 )); then
        # Keep last 250 lines
        tail -n 250 "$LOG" > "${LOG}.tmp" && mv "${LOG}.tmp" "$LOG"
        echo "$(date): LOG ROTATION: logs trimmed (previous $line_count lines)" >> "$LOG"
    fi
fi

# ────────────────────────────── CONFIG AND LANG FILE ──────────────────────────────

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
LANG_FILE="$SCRIPT_DIR/battery-notify.lang"
# Using a specific lock file for the critical loop to manage concurrency
CRITICAL_LOOP_LOCK="/tmp/.battery-critical-loop.lock" 

# ────────────────────────────── DEPENDENCY CHECK ──────────────────────────────

REQUIRED_CMDS=(upower notify-send dbus-monitor grep awk sed flock)

for cmd in "${REQUIRED_CMDS[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
        log "FATAL: Missing dependency '$cmd' — install required package. Exiting."
        echo "Missing dependency: $cmd"
        exit 1
    else
        log "OK: Found dependency '$cmd'"
    fi
done

if [ ! -f "$LANG_FILE" ]; then
    log "FATAL: Missing localization file '$LANG_FILE'. Exiting."
    echo "Missing localization file: $LANG_FILE"
    exit 1
fi

log "All dependencies and language file verified."

# ────────────────────────────── LOCKFILE ──────────────────────────────

lockfile="${XDG_RUNTIME_DIR:-/tmp}/.battery-notify.lock"
exec 9>"$lockfile"
if ! flock -n 9; then
    log "Another instance already running. Exiting."
    exit 0
fi
log "Lock acquired: running as single instance."

# ────────────────────────────── CONFIG ──────────────────────────────

unplug_thresholds=(80 85 90 95 100)
low_thresholds=(20 15 10)
critical_threshold=5
MSG_COUNT=5 # Number of messages per section in the language file

# ────────────────────────────── HELPERS ──────────────────────────────

is_laptop() {
    if ! ls /sys/class/power_supply/BAT* >/dev/null 2>&1; then
        log "FATAL: No battery device found. Exiting."
        exit 0
    fi
}

get_battery_info() {
    local total_pct=0 count=0

    for battery in /sys/class/power_supply/BAT*; do
        if [ ! -e "$battery/capacity" ] || [ ! -e "$battery/status" ]; then
            log "ERROR: Missing battery files inside $battery"
            continue
        fi

        local status=$(<"$battery/status")
        local capacity=$(<"$battery/capacity")

        if ! [[ "$capacity" =~ ^[0-9]+$ ]]; then
            log "ERROR: Invalid battery capacity '$capacity' in $battery"
            continue
        fi

        battery_status="$status"
        total_pct=$((total_pct + capacity))
        ((count++))
    done

    if ((count == 0)); then
        log "FATAL: Could not read any battery capacity. Exiting."
        exit 1
    fi

    battery_percentage=$((total_pct / count))
}

battery_step_icon() {
    local perc=$1
    local step=$(( (perc + 5) / 10 * 10 ))
    (( step > 100 )) && step=100
    (( step < 0 )) && step=0
    echo "$step"
}

get_localized_message() {
    local section=$1
    local msg_key="MSG_$(( (RANDOM % MSG_COUNT) + 1 ))"

    # Use sed to find the section and extract the specific message key, 
    # ignoring potential leading spaces before the key.
    # The sed pattern /\[$section\]/,/\[.*\]/p is correct for section range.
    local msg=$(sed -n "/\[$section\]/,/\[.*\]/{s/^[[:space:]]*$msg_key=//p}" "$LANG_FILE" | head -n 1)

    if [[ -z "$msg" ]]; then
        log "WARNING: Could not find message for section [$section] and key $msg_key. Falling back."
        echo "Notification for $section at $battery_percentage%"
        return
    fi
    
    # Replace the percentage placeholder (%%) with the actual percentage
    msg=$(echo "$msg" | sed "s/%%/$battery_percentage%/g")

    echo "$msg"
}

notify_battery() {
    log "NOTIFY [$1] icon=$2 title='$3' msg='$4'"
    if ! notify-send -t 5000 -u "$1" -i "$2" "$3" "$4"; then
        log "ERROR: notify-send failed for '$3'"
    fi
}

# ────────────────────────────── MAIN LOGIC ──────────────────────────────

fn_status_change() {
    get_battery_info
    icon_step=$(battery_step_icon "$battery_percentage")

    log "StateCheck: last=$last_status now=$battery_status pct=$battery_percentage"

    # Ignore 'Unknown' state for transition/suspend events
    if [[ "$battery_status" == "Unknown" ]]; then
        log "State ignored: Unknown (transitional state)"
        return
    fi

    # Plug/Unplug detection
    if [[ "$battery_status" == "Discharging" && "$last_status" != "Discharging" ]]; then
        log "Detected UNPLUGGED"
        local msg=$(get_localized_message "UNPLUGGED")
        notify_battery normal "battery-level-$icon_step-symbolic" \
            "Charger Unplugged" "$msg"
    elif [[ "$battery_status" != "Discharging" && "$last_status" == "Discharging" ]]; then
        log "Detected PLUGGED-IN"
        local msg=$(get_localized_message "PLUGGED_IN")
        notify_battery normal "battery-level-$icon_step-plugged-in-symbolic" \
            "Charger Plugged In" "$msg"
    fi

    last_status="$battery_status"

    case "$battery_status" in

        #######################################################################
        # DISCHARGING LOGIC
        #######################################################################
        Discharging)

            for lvl in "${low_thresholds[@]}"; do
                if (( battery_percentage == lvl )) && [[ ! -f /tmp/.notified_low_$lvl ]]; then
                    touch /tmp/.notified_low_$lvl

                    case $lvl in
                    20)
                        notify_icon="battery-level-20-symbolic"
                        notify_section="LOW_20"
                        ;;
                    15)
                        notify_icon="battery-level-10-symbolic"
                        notify_section="LOW_15"
                        ;;
                    10)
                        notify_icon="battery-level-0-symbolic"
                        notify_section="LOW_10"
                        ;;
                    esac

                    msg=$(get_localized_message "$notify_section")
                    log "LowBattery threshold hit: $lvl% (msg='$msg')"
                    notify_battery critical "$notify_icon" "Battery Low" "$msg"
                fi
            done

            # Critical loop with flag file to prevent multiple instances
            if (( battery_percentage <= critical_threshold )); then
                if [[ -f "$CRITICAL_LOOP_LOCK" ]]; then
                    log "Critical loop already running. Skipping spawn."
                    return
                fi
                
                touch "$CRITICAL_LOOP_LOCK"
                log "Entering critical loop (<=${critical_threshold}%)"

                while true; do
                    get_battery_info
                    if [[ "$battery_status" != "Discharging" ]] || (( battery_percentage > critical_threshold )); then
                        log "Exiting critical loop"
                        rm -f "$CRITICAL_LOOP_LOCK"
                        break
                    fi
                    local critical_msg=$(get_localized_message "CRITICAL")
                    notify_battery critical "battery-level-0-symbolic" \
                        "Battery Critically Low" \
                        "$critical_msg"
                    sleep 2
                done &
            fi

            # Reset charging flags
            for lvl in "${unplug_thresholds[@]}"; do
                rm -f /tmp/.notified_unplug_$lvl
            done
            ;;

        #######################################################################
        # CHARGING LOGIC
        #######################################################################
        Charging|NotCharging|FullyCharged) # Treat FullyCharged as part of Charging Logic

            for lvl in "${unplug_thresholds[@]}"; do
                if (( battery_percentage == lvl )) && [[ ! -f /tmp/.notified_unplug_$lvl ]]; then
                    touch /tmp/.notified_unplug_$lvl

                    case $lvl in
                    80)
                        notify_icon="battery-level-80-charging-symbolic"
                        notify_section="UNPLUG_80"
                        ;;
                    85)
                        notify_icon="battery-level-80-charging-symbolic"
                        notify_section="UNPLUG_85"
                        ;;
                    90)
                        notify_icon="battery-level-90-charging-symbolic"
                        notify_section="UNPLUG_90"
                        ;;
                    95)
                        notify_icon="battery-level-90-charging-symbolic"
                        notify_section="UNPLUG_95"
                        ;;
                    100)
                        notify_icon="battery-level-100-charged-symbolic"
                        notify_section="UNPLUG_100"
                        ;;
                    esac

                    msg=$(get_localized_message "$notify_section")
                    log "Charging threshold hit: $lvl% (msg='$msg')"
                    notify_battery critical "$notify_icon" "Battery Charged" "$msg"
                fi
            done

            # Reset low-battery flags (and critical loop lock if charging)
            for lvl in "${low_thresholds[@]}"; do
                rm -f /tmp/.notified_low_$lvl
            done
            rm -f "$CRITICAL_LOOP_LOCK" # Ensure lock is removed if charger is connected
            ;;
    esac
}

# ────────────────────────────── CLEANUP ──────────────────────────────

_cleanup() {
    log "CLEANUP: Removing flag files, critical lock, & exiting."
    rm -f /tmp/.notified_low_* /tmp/.notified_unplug_* "$CRITICAL_LOOP_LOCK"
    log "CLEANUP: Done."
    exit
}
trap _cleanup INT TERM HUP ERR

# ────────────────────────────── MAIN ──────────────────────────────

main() {
    is_laptop

    # Clean up old flags and critical lock at startup
    rm -f /tmp/.notified_low_* /tmp/.notified_unplug_* /tmp/.notified_critical_* /tmp/.notified_charged_* "$CRITICAL_LOOP_LOCK" 2>/dev/null

    get_battery_info
    last_status="$battery_status"
    log "Initial battery state: $battery_status ($battery_percentage%)"

    fn_status_change
    log "Initial fn_status_change executed."

    battery_dbus_path=$(upower -e | grep battery | head -n 1)
    if [[ -z "$battery_dbus_path" ]]; then
        log "FATAL: upower returned no DBus battery path. Exiting."
        exit 1
    fi

    log "Using DBus path: $battery_dbus_path"

    stdbuf -oL dbus-monitor --system \
        "type='signal',interface='org.freedesktop.DBus.Properties',path='$battery_dbus_path'" \
        2>>"$LOG" \
    | grep --line-buffered -E "Percentage|State" \
    | while read -r line; do
        log "DBus Signal: $line"
        fn_status_change
    done

    log "FATAL: dbus-monitor exited unexpectedly!"
}

main
