#!/usr/bin/env bash

# ───── Prevent multiple instances ─────
LOCK="$HOME/.cache/syshud-pulse-watch.lock"
exec 9>"$LOCK" || exit 1
flock -n 9 || exit 0

# ───── Config ─────
SYSHUD_CMD='syshud -p right -o v -m "0 40 0 0"'
LOG="$HOME/.cache/syshud-pulse-watch.log"

mkdir -p "$HOME/.cache"

# ───── Log rotation (keep last 300 lines) ─────
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

# ───── Start / restart syshud ─────
start_syshud() {
    log "Restarting syshud…"
    if pkill -x syshud 2>/dev/null; then
        log "Killed existing syshud"
    fi
    eval "$SYSHUD_CMD" &
    log "Started: $SYSHUD_CMD"
}

log "================ syshud PulseAudio watcher started ================"

# Start initially
start_syshud

# ───── Watch PulseAudio events ─────
pactl subscribe | while read -r line; do
    log "Pulse event: $line"
    if echo "$line" | grep -q "on server"; then
        log "Server change detected → restarting syshud"
        start_syshud
    fi
done
