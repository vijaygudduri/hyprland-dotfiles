#!/bin/bash

# Get interface from argument, or by checking default route (robust method)
IFACE="${1:-$(ip route get 1.1.1.1 2>/dev/null | awk '{print $5; exit}')}"

# 1. Check if interface exists and is UP (crucial check)
STATE=$(cat /sys/class/net/$IFACE/operstate 2>/dev/null)
if [[ "$STATE" != "up" ]]; then
    echo "0 K/s"
    exit
fi

# 2. Read initial counters
RX_PREV=$(cat /sys/class/net/$IFACE/statistics/rx_bytes)
TX_PREV=$(cat /sys/class/net/$IFACE/statistics/tx_bytes)

# Set and sleep for the interval (1 second)
INTERVAL=1
sleep $INTERVAL

# 3. Read final counters
RX_NEXT=$(cat /sys/class/net/$IFACE/statistics/rx_bytes)
TX_NEXT=$(cat /sys/class/net/$IFACE/statistics/tx_bytes)

# Calculate bytes transferred in the interval (B/s since INTERVAL=1)
DOWN=$((RX_NEXT - RX_PREV))
UP=$((TX_NEXT - TX_PREV))

# Determine the higher speed
MAX=$((DOWN > UP ? DOWN : UP))

# 4. Final Output (simplified)

# If speed is less than 1 K/s (1024 Bytes/s), show 0 K/s
if (( MAX < 1024 )); then
    echo "0 K/s"
else
    # Use numfmt for consistent IEC formatting (KiB, MiB, etc.) with 2 decimals
    # e.g., 1050 B/s becomes "1.02Ki"
    formatted=$(numfmt --to=iec --format="%.2f" "$MAX")
    
    # Remove the 'i' from the IEC unit (KiB -> KB) and append '/s'
    # ${formatted%?} removes the last character ('i')
    # ${formatted: -1} extracts the unit letter ('K', 'M', 'G', etc.)
    echo "${formatted%?} ${formatted: -1}/s"
fi
