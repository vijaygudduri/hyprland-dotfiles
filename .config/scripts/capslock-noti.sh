#!/bin/bash

CAPS_LED=$(ls /sys/class/leds | grep -i '::capslock' | head -n1)
[ -z "$CAPS_LED" ] && exit 1

LED_PATH="/sys/class/leds/$CAPS_LED/brightness"

# read initial state
old=$(cat "$LED_PATH")

# wait up to ~300ms for it to change
for _ in {1..15}; do
    sleep 0.02
    new=$(cat "$LED_PATH")
    [ "$new" != "$old" ] && break
done

if [ "$new" = "1" ]; then
    msg="Caps Lock: ON"
else
    msg="Caps Lock: OFF"
fi

notify-send -i input-keyboard -t 3000 \
  -h string:x-canonical-private-synchronous:caps \
  "Keyboard" "$msg"
