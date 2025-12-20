#!/usr/bin/env bash

LOG="$HOME/.cache/autoswitch.log"
PIDFILE="$HOME/.cache/autoswitch.pid"
mkdir -p "$HOME/.cache"

# Dependency check
for cmd in hyprctl jq socat; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "$(date): Missing dependency: $cmd" | tee -a "$LOG"
    exit 1
  fi
done

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

# Prevent duplicate instances
if [ -f "$PIDFILE" ]; then
    oldpid=$(cat "$PIDFILE" 2>/dev/null)
    if kill -0 "$oldpid" 2>/dev/null; then
        log "Already running (pid $oldpid). Exiting."
        exit 0
    else
        log "Removing stale PID file."
        rm -f "$PIDFILE"
    fi
fi

echo $$ > "$PIDFILE"

cleanup() {
    rm -f "$PIDFILE"
    log "Autoswitch exited."
}
trap cleanup EXIT INT TERM

# Hyprland socket
SOCKET="${XDG_RUNTIME_DIR}/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock"

# Wait for socket
for i in {1..30}; do
    if [ -S "$SOCKET" ]; then break; fi
    log "Waiting for Hyprland socket..."
    sleep 1
done

if [ ! -S "$SOCKET" ]; then
    log "Socket not found: $SOCKET"
    exit 1
fi

log "Socket found. Starting socat listener."

last_ws=""

# -------- SWITCH LOGIC -------- #

switch_if_needed() {
    local ws="$1"

    local clients_json
    clients_json=$(hyprctl clients -j 2>/dev/null)
    [ -z "$clients_json" ] && return

    local result
    result=$(echo "$clients_json" | jq -c --argjson ws "$ws" '{
        win_count: ([.[] | select(.workspace.id==$ws)] | length),
        ws_list: ([.[] | .workspace.id] | unique | sort)
    }')

    [ -z "$result" ] && return

    local win_count
    win_count=$(echo "$result" | jq -r '.win_count')

    mapfile -t ws_with_windows < <(echo "$result" | jq -r '.ws_list[]')

    if [ "$win_count" -eq 0 ] && [ "$last_ws" = "$ws" ]; then
        if [ "${#ws_with_windows[@]}" -eq 0 ]; then
            log "No windows anywhere"
            return
        fi

        local candidate=""
        for id in "${ws_with_windows[@]}"; do
            if [ "$id" -gt "$ws" ]; then
                candidate="$id"
                break
            fi
        done

        if [ -z "$candidate" ]; then
            candidate="${ws_with_windows[-1]}"
        fi

        [ -z "$candidate" ] && candidate="${ws_with_windows[0]}"

        if [ "$candidate" -ne "$ws" ]; then
            if hyprctl dispatch workspace "$candidate" 2>>"$LOG"; then
                log "Switched: $ws → $candidate"
                last_ws="$candidate"
            else
                log "Failed to switch to $candidate"
            fi
        fi
    fi

    [ "$win_count" -gt 0 ] && last_ws="$ws"
}

# -------- MAIN EVENT LOOP -------- #

socat -u UNIX-CONNECT:"$SOCKET" - | while read -r event; do
    case "$event" in
        activewindow*|closewindow*)
            ws=$(hyprctl activeworkspace -j | jq -r '.id')
            [ -n "$ws" ] && switch_if_needed "$ws"
            ;;
    esac
done