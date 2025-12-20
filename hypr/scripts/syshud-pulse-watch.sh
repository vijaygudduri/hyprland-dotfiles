#!/usr/bin/env bash

# ───── Runtime dir & lock ─────
cache_dir="${XDG_RUNTIME_DIR:-$HOME/.cache}"
mkdir -p "$cache_dir"

LOCK="$cache_dir/syshud-pulse-watch.lock"
exec 9>"$LOCK" || exit 1
flock -n 9 || exit 0

# ───── Command ─────
SYSHUD_CMD=(syshud -p right -o v -m "0 40 0 0")

# ───── Start / restart syshud ─────
start_syshud() {
    pkill -x syshud 2>/dev/null
    "${SYSHUD_CMD[@]}" &
}

# Start once initially
start_syshud

# ───── Watch PulseAudio events (auto-retry) ─────
while :; do
    pactl subscribe | while read -r line; do
        case $line in
            *"on server"*)
                start_syshud
                ;;
        esac
    done
    # If pactl exits (PulseAudio restart), wait a bit and retry
    sleep 2
done
