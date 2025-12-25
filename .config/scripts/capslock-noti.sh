#!/bin/bash
sleep 0.15

DATA=$(hyprctl devices -j)

if echo "$DATA" | jq -e '.keyboards[] | select(.capsLock == true)' > /dev/null; then
    msg="Caps Lock: ON"
else
    msg="Caps Lock: OFF"
fi

# -i sets the icon
# -t 3000 sets duration to 3 seconds
notify-send -i input-keyboard -t 3000 -h string:x-canonical-private-synchronous:caps "Keyboard" "$msg"
