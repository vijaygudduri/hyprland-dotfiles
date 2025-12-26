#!/bin/bash
sleep 0.1
# This looks specifically for the 'main: yes' keyboard and checks its numLock state
state=$(hyprctl devices -j | jq -r '.keyboards[] | select(.main == true) | .numLock')

if [ "$state" = "true" ]; then
    notify-send -i input-keyboard -t 3000 -h string:x-canonical-private-synchronous:num -h int:transient:1 "Keyboard" "Num Lock: ON"
else
    notify-send -i input-keyboard -t 3000 -h string:x-canonical-private-synchronous:num -h int:transient:1 "Keyboard" "Num Lock: OFF"
fi
