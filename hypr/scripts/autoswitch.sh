#!/usr/bin/env bash
# autoswitch.sh - robust autoswitch for Hyprland
# Improved: handles hyprctl/jq errors, empty JSON, cleans up PID file, logs sensibly, and refined logic.

LOG="$HOME/.cache/autoswitch.log"
PIDFILE="$HOME/.cache/autoswitch.pid"
SOCKET="${XDG_RUNTIME_DIR}/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock"

# Dependency check
for cmd in hyprctl jq socat; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "$(date): Missing dependency: $cmd" | tee -a "$LOG"
    exit 1
  fi
done

# Prevent multiple instances and handle stale PID
if [ -f "$PIDFILE" ]; then
  oldpid=$(cat "$PIDFILE" 2>/dev/null)
  if [ -n "$oldpid" ] && kill -0 "$oldpid" 2>/dev/null; then
    echo "$(date): already running (pid $oldpid). exiting." >> "$LOG"
    exit 0
  else
    echo "$(date): removing stale PID file." >> "$LOG"
    rm -f "$PIDFILE"
  fi
fi
echo $$ > "$PIDFILE"

# Trap improved: added HUP for more robust daemon-like behavior.
trap 'rm -f "$PIDFILE"; echo "$(date): autoswitch exited." >> "$LOG"; exit' INT TERM HUP ERR

last_ws=""

switch_if_needed() {
  local ws="$1"

  # Refined logic: Get all workspaces with windows in a single, efficient jq call.
  local ws_with_windows
  local clients_json
  clients_json=$(hyprctl clients -j 2>/dev/null)
  
  if [ -z "$clients_json" ]; then
    win_count=0
    ws_with_windows=()
  else
    # Improved jq query: get active window count and a sorted list of workspaces with windows in one go.
    local query_result
    query_result=$(echo "$clients_json" | jq -c --argjson ws "$ws" '{
      win_count: ([.[] | select(.workspace.id==$ws)] | length),
      ws_list: ([.[] | .workspace.id] | unique | sort)
    }' 2>/dev/null)

    if [ -z "$query_result" ] || [ "$query_result" = "null" ]; then
      echo "$(date): cannot parse client count/workspaces. Defaulting to zero." >> "$LOG"
      win_count=0
      ws_with_windows=()
    else
      win_count=$(echo "$query_result" | jq -r '.win_count')
      # mapfile is a robust way to read array from output
      mapfile -t ws_with_windows < <(echo "$query_result" | jq -r '.ws_list[]')
    fi
  fi

  if [ "$win_count" -eq 0 ] && [ "$last_ws" = "$ws" ]; then
    if [ "${#ws_with_windows[@]}" -eq 0 ]; then
      echo "$(date): no windows in any workspace (no action)" >> "$LOG"
    else
      local candidate=""
      
      # Use a single loop to find the best candidate.
      for id in "${ws_with_windows[@]}"; do
        if [ "$id" -gt "$ws" ]; then
          candidate="$id"
          break
        fi
      done
      
      # Fallback to the highest available workspace below the current one.
      if [ -z "$candidate" ]; then
        for (( idx=${#ws_with_windows[@]}-1 ; idx>=0 ; idx-- )); do
          if [ "${ws_with_windows[$idx]}" -lt "$ws" ]; then
            candidate="${ws_with_windows[$idx]}"
            break
          fi
        done
      fi

      # Final fallback to the lowest available workspace if no other candidate found.
      if [ -z "$candidate" ]; then
        candidate="${ws_with_windows[0]}"
      fi
      
      if [ -n "$candidate" ] && [ "$candidate" -ne "$ws" ]; then
        if hyprctl dispatch workspace "$candidate" 2>>"$LOG"; then
          echo "$(date): autoswitched from ws $ws to $candidate (nearest available)" >> "$LOG"
          last_ws="$candidate"
        else
          echo "$(date): failed to switch workspace to $candidate" >> "$LOG"
        fi
      else
        echo "$(date): no valid candidate (staying on $ws)" >> "$LOG"
      fi
    fi
  fi

  # Update last_ws if windows exist
  if [ "$win_count" -gt 0 ]; then
    last_ws="$ws"
  fi
}

# Wait up to 30s for the Hyprland socket
for i in {1..30}; do
  if [ -S "$SOCKET" ]; then
    break
  fi
  echo "$(date): waiting for Hyprland socket..." >> "$LOG"
  sleep 1
done

if [ ! -S "$SOCKET" ]; then
  echo "$(date): Hyprland socket not found after 30s: $SOCKET" | tee -a "$LOG"
  rm -f "$PIDFILE"
  exit 1
fi

echo "$(date): Hyprland socket found. Starting event listener." >> "$LOG"

# Main event loop.
socat -u UNIX-CONNECT:"$SOCKET" - | while read -r event; do
  # Optimized: Get active workspace ID once per event.
  ws=$(hyprctl activeworkspace -j 2>/dev/null | jq -r '.id' 2>/dev/null)
  
  if [ -z "$ws" ] || [ "$ws" = "null" ]; then
    echo "$(date): Could not get active workspace ID." >> "$LOG"
    continue
  fi

  case "$event" in
    "activewindow"*|"closewindow"*)
      switch_if_needed "$ws"
      ;;
  esac
done
