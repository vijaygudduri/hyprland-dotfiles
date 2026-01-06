#!/bin/bash
sleep 0.2  # Give Hyprland more time to update

# Get main keyboard numLock state with fallback
state=$(hyprctl devices -j | jq -r '.keyboards[] | select(.main == true) | .numLock // empty' | head -n1 | tr -d ' \n')

if [ "$state" = "true" ] || [ "$state" = "yes" ]; then
    notify-send -i input-keyboard -t 3000 -h string:x-canonical-private-synchronous:num -h int:transient:1 "Keyboard" "Num Lock: ON"
else
    notify-send -i input-keyboard -t 3000 -h string:x-canonical-private-synchronous:num -h int:transient:1 "Keyboard" "Num Lock: OFF"
fi
