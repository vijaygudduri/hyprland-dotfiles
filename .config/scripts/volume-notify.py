#!/usr/bin/env python3

import subprocess
import re
import sys

# Store the last known volume to prevent duplicate notifications
last_volume = None

def get_volume():
    """Fetches the current volume using wpctl."""
    try:
        # We use @DEFAULT_AUDIO_SINK@ to automatically target the active output
        out = subprocess.check_output(
            ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"],
            text=True
        )
        # Parse output like: "Volume: 0.45 [MUTED]" or "Volume: 0.45"
        m = re.search(r"([\d.]+)", out)
        if m:
            vol = int(float(m.group(1)) * 100)
            # Check for muted state to show 0% or a mute icon if preferred
            if "[MUTED]" in out:
                return "Muted"
            return vol
        return None
    except subprocess.CalledProcessError:
        return None

def notify(vol):
    """Sends the notification."""
    # Determine icon and text based on volume state
    if vol == "Muted":
        icon = "audio-volume-muted"
        text = "Muted"
        value_text = "Muted"
    else:
        icon = "audio-volume-high"
        text = "Volume"
        value_text = f"{vol}%"

    subprocess.run([
        "notify-send",
        "-t", "3000",
        "-h", "int:transient:1",
        "-h", "string:x-canonical-private-synchronous:volume",
        "-i", icon,
        text,
        value_text
    ])

def listen_for_events():
    global last_volume
    
    # Initialize volume on startup
    last_volume = get_volume()

    # Start pw-mon to listen to native PipeWire events
    # We filter slightly inside python, but pw-mon dumps everything.
    process = subprocess.Popen(
        ["pw-mon"],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        bufsize=1  # Line buffered
    )

    print("Listening for PipeWire events...")

    try:
        # Iterate over stdout line by line. This is a blocking operation.
        for line in process.stdout:
            # We look for "Param:Props". 
            # This parameter changes when volume, mute, or device routes change.
            if "Enum:Param:Props" in line or "Param:Route" in line:
                
                current_vol = get_volume()
                
                # Only notify if the volume/mute state actually changed
                if current_vol is not None and current_vol != last_volume:
                    last_volume = current_vol
                    notify(current_vol)
                    
    except KeyboardInterrupt:
        process.terminate()
        sys.exit(0)

if __name__ == "__main__":
    listen_for_events()
