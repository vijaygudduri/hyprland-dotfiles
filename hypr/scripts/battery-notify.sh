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

log "All dependencies verified."

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

    # Plug/Unplug detection
    if [[ "$battery_status" == "Discharging" && "$last_status" != "Discharging" ]]; then
        log "Detected UNPLUGGED"
        notify_battery normal "battery-level-$icon_step-symbolic" \
            "Charger Unplugged" "Battery at $battery_percentage%"
    elif [[ "$battery_status" != "Discharging" && "$last_status" == "Discharging" ]]; then
        log "Detected PLUGGED-IN"
        notify_battery normal "battery-level-$icon_step-plugged-in-symbolic" \
            "Charger Plugged In" "Battery at $battery_percentage%"
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
                        msgs=(
                            "Battery at 20%. Early warning! Plug in now before things get emotional 📣"
                            "Battery at 20% — bro... it's not too late. Charger connect chey 🪫➡️⚡"
                            "Battery at 20%! Power is fading like your hopes on Monday morning 😭"
                            "Battery at 20%. Respect boundaries. Give charger 😤"
                            "Battery at 20%. Time to stop scrolling memes and plug in 📵⚡"
                        )
                        ;;

                    15)
                        notify_icon="battery-level-10-symbolic"
                        msgs=(
                            "Battery at 15%! Bro please… I'm literally gasping for electrons 🙏"
                            "Battery at 15%. Even your phone charges more responsibly 😒"
                            "Battery at 15%! We are entering danger zone. Charger ekkada? 🚨"
                            "Battery at 15%. I am dying like your weekend plans 💀"
                            "Battery at 15%… why are you like this? Plug-in chey anna 😩"
                        )
                        ;;

                    10)
                        notify_icon="battery-level-0-symbolic"
                        msgs=(
                            "Battery at 10%! Red alert. Countdown started! Save your work! 🚨"
                            "Battery at 10%. Next step: shutdown. Don’t test me 😡"
                            "Battery at 10%! Bro… if you don’t plug in now, I’ll embarrass you with a hard shutdown 😭"
                            "Battery at 10%. This is your FINAL warning. MOVE! ⚡"
                            "Battery at 10%. I can see the light… plug me before I go 🕯️"
                        )
                        ;;

                    esac

                    msg="${msgs[$RANDOM % ${#msgs[@]}]}"
                    log "LowBattery threshold hit: $lvl% (msg='$msg')"
                    notify_battery critical "$notify_icon" "Battery Low" "$msg"
                fi
            done

            # Critical loop every 2s
            if (( battery_percentage <= critical_threshold )); then
                log "Entering critical loop (<=${critical_threshold}%)"
                while true; do
                    get_battery_info
                    if [[ "$battery_status" != "Discharging" ]] || (( battery_percentage > critical_threshold )); then
                        log "Exiting critical loop"
                        break
                    fi
                    notify_battery critical "battery-level-0-symbolic" \
                        "Battery Critically Low" \
                        "Battery at $battery_percentage% — Just few more mins left, PLUG IN RIGHT NOW! ⚡"
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
        Charging|NotCharging|Unknown)

            for lvl in "${unplug_thresholds[@]}"; do
                if (( battery_percentage == lvl )) && [[ ! -f /tmp/.notified_unplug_$lvl ]]; then
                    touch /tmp/.notified_unplug_$lvl

                    case $lvl in

                    80)
                        icon="battery-level-80-charging-symbolic"
                        msgs=(
                            "Battery reached 80%. Ideal unplug point. Trust the science 🧪⚡"
                            "Battery reached 80%! Time to disconnect. Don’t overfeed me 😌"
                            "Battery reached 80% — the golden zone. Unplug chey bro ✋"
                            "Battery reached 80%. Charging from here is like overeating after you're full 😅"
                            "Battery reached 80%! Healthy battery habits start here. Remove charger 🚫⚡"
                        )
                        ;;

                    85)
                        icon="battery-level-80-charging-symbolic"
                        msgs=(
                            "Battery reached 85%. Enough bro, unplug now ✨"
                            "Battery reached 85%. I’m good. Remove charger and let me breathe 😮‍💨"
                            "Battery reached 85%! Continuing to charge won’t give me superpowers 😂"
                            "Battery reached 85%. Charger ki leave ivvu once 😌"
                            "Battery reached 85%. Overcharging will age me faster than stress ages humans 😭"
                        )
                        ;;

                    90)
                        icon="battery-level-90-charging-symbolic"
                        msgs=(
                            "Battery reached 90%. Beyond this is extra fat… remove charger 😅"
                            "Battery reached 90%! Even your phone charges less aggressively 😂 Unplug now."
                            "Battery reached 90%. Stop making me eat like it's Diwali 🪔😩"
                            "Battery reached 90%. Leave some space, unplug the charger 😤"
                            "Battery reached 90%. Bro why are you still charging? 😭"
                        )
                        ;;

                    95)
                        icon="battery-level-90-charging-symbolic"
                        msgs=(
                            "Battery reached 95%. Enough anna, unplug before I explode with happiness 😌"
                            "Battery reached 95%. This is more than enough. Disconnect ⚡"
                            "Battery reached 95%! You're charging me like I'm going to war 😅 Unplug now."
                            "Battery reached 95%. Give the poor charger a break 😪"
                            "Battery reached 95%! Another 5% won’t change your life bro 😆"
                        )
                        ;;

                    100)
                        icon="battery-level-100-charged-symbolic"
                        msgs=(
                            "Battery reached 100%! Fully charged. Why are we still attached? 😵"
                            "Battery reached 100%! Unplug before I start sending emotional damage 😭"
                            "Battery reached 100%. Full charge achieved. Mission accomplished soldier 🫡⚡"
                            "Battery reached 100%. Bro please… disconnect. I’m literally overflowing 😣"
                            "Battery reached 100%! Keeping the charger now is illegal in 7 countries 🚓"
                        )
                        ;;

                    esac

                    msg="${msgs[$RANDOM % ${#msgs[@]}]}"
                    log "Charging threshold hit: $lvl% (msg='$msg')"
                    notify_battery critical "$icon" "Battery Charged" "$msg"
                fi
            done

            # Reset low-battery flags
            for lvl in "${low_thresholds[@]}"; do
                rm -f /tmp/.notified_low_$lvl
            done
            ;;
    esac
}

# ────────────────────────────── CLEANUP ──────────────────────────────

_cleanup() {
    log "CLEANUP: Removing flag files & exiting."
    rm -f /tmp/.notified_low_* /tmp/.notified_unplug_*
    log "CLEANUP: Done."
    exit
}
trap _cleanup INT TERM HUP ERR

# ────────────────────────────── MAIN ──────────────────────────────

main() {
    is_laptop

    rm -f /tmp/.notified_low_* /tmp/.notified_unplug_* /tmp/.notified_critical_* /tmp/.notified_charged_* 2>/dev/null

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
