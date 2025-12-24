#!/usr/bin/env bash

DIR="$HOME/Pictures/Screenshots"
DISPLAY_DIR="~/Pictures/Screenshots"

mkdir -p "$DIR"
NAME="screenshot_$(date +%Y-%m-%d_%H:%M:%S).png"

case "$1" in
  area)
    grimblast --scale 1 copysave area "$DIR/$NAME"
    ;;
  screen)
    grimblast --scale 1 copysave screen "$DIR/$NAME"
    ;;
esac

notify-send -i camera-photo -t 3500 \
  "Screenshot saved" \
  "Saved in $DISPLAY_DIR and copied to clipboard"
