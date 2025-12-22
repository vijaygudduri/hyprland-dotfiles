#!/bin/bash

# Wait until the Bluetooth adapter is powered ON and ready
echo "Waiting for Bluetooth adapter to power on..."

timeout=15
elapsed=0

until bluetoothctl show | grep -q "Powered: yes"; do
    sleep 1
    elapsed=$((elapsed + 1))

    if [ $elapsed -ge $timeout ]; then
        echo "❌ Bluetooth is OFF or unreachable. Exiting."
        exit 0
    fi
done

echo "✅ Bluetooth adapter is powered on."


# Get a list of all known devices (MAC addresses only)
# 'awk '{print $2}' isolates the MAC address from the output line
PAIRED_DEVICES=$(bluetoothctl devices | awk '{print $2}')

# Loop through each device and try to connect
for MAC_ADDR in $PAIRED_DEVICES; do

    # Check if the value looks like a valid MAC address
    if [[ $MAC_ADDR =~ ^([0-9A-Fa-f]{2}:){5}([0-9A-Fa-f]{2})$ ]]; then

        # Check if the device is already connected
        if bluetoothctl info "$MAC_ADDR" | grep -q "Connected: yes"; then
            echo "Device $MAC_ADDR already connected. ✅"
        else
            echo "Attempting to connect to $MAC_ADDR..."
            bluetoothctl connect "$MAC_ADDR" 
        fi

        # Optional: Uncomment 'break' to stop after the first device attempt
        # break 
    else
        echo "Skipping non-MAC address value: $MAC_ADDR"
    fi
done

# Wait briefly for background connection attempts to finish before script exits
sleep 2