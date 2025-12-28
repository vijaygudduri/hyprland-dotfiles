#!/usr/bin/env python3
import os
import sys
import logging
from logging.handlers import RotatingFileHandler # Added for log rotation
import asyncio
import signal

# ──────────────────────────────── LOGGING SETUP ────────────────────────────────
# Configured early to catch any startup or dependency errors.
LOG_FILE = os.path.expanduser("~/.cache/battery-notify.log")
os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)

# Using RotatingFileHandler to limit log size to ~20KB (approx 300-400 lines)
handler = RotatingFileHandler(LOG_FILE, maxBytes=20000, backupCount=1)
handler.setFormatter(logging.Formatter('%(asctime)s - %(levelname)s - %(message)s'))

logger = logging.getLogger("BatteryMonitor")
logger.setLevel(logging.INFO)
logger.addHandler(handler)

# ──────────────────────────────── CONFIGURATION ────────────────────────────────
LOCK_FILE = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), ".battery-notify.lock")

# ICON FORMATTING GUIDE:
# Use {0} for padded format (e.g., 080)
# Use {1} for unpadded format (e.g., 80)
MESSAGES = {
    "CRITICAL_THRESHOLD": 5,

    # --- STATUS CHANGE EVENTS ---
    # Example using padded {0} (080 format)
    "PLUGGED":   ("Charger Plugged In", "Battery at {}%. Charging started.", "battery-{0}-charging", "normal"),
    "UNPLUGGED": ("Charger Unplugged", "Battery at {}%. Running on battery.", "battery-{0}-symbolic", "normal"),

    # --- REPEATING CRITICAL ALERT ---
    "CRITICAL_LOOP": ("Battery Critically Low", "Battery at {}% — PLUG IN IMMEDIATELY!", "battery-000-symbolic", "critical"),

    # --- DISCHARGING LEVELS (Status 2) ---
    (2, 20): ("Battery Low", "Battery at 20% — consider plugging in.", "battery-020-symbolic", "critical"),
    (2, 15): ("Battery Low", "Battery at 15% — low power.", "battery-010-symbolic", "critical"),
    (2, 10): ("Battery Low", "Battery at 10% — critically low.", "battery-000-symbolic", "critical"),
    
    # --- CHARGING LEVELS (Status 1) ---
    (1, 80): ("Battery Charged", "Battery at 80% — good time to unplug.", "battery-080-charging", "normal"),
    (1, 85): ("Battery Charged", "Battery at 85% - unplug please", "battery-080-charging", "normal"),
    (1, 90): ("Battery Charged", "Battery at 90% - unplug the cable", "battery-090-charging", "normal"),
    (1, 95): ("Battery Charged", "Battery at 95% - lets remove the cord", "battery-090-charging", "normal"),
    (1, 100):("Battery Charged", "Battery fully charged - Please unplug", "battery-100-charging", "normal"),
}

# ──────────────────────────────── CORE LOGIC ────────────────────────────────

class BatteryMonitor:
    def __init__(self):
        self.last_state = None
        self.notified_levels = set()
        self.critical_task = None
        self.current_percentage = 0 

    def get_icon_formats(self, percentage):
        """Returns a tuple of (padded_string, unpadded_string) for icon names."""
        val = min(100, (int(percentage) + 5) // 10 * 10)
        return f"{val:03}", str(val)

    async def notify(self, urgency, icon, title, message):
        """Sends notification via notify-send without blocking the async loop."""
        logger.info(f"NOTIFY [{urgency}] {title} — {message}")
        try:
            await asyncio.create_subprocess_exec(
                "notify-send", "-u", urgency, "-i", icon, title, message
            )
        except Exception as e:
            logger.error(f"Failed to send notification: {e}")

    async def critical_loop(self):
        """Alerts the user every 2 seconds until plugged in."""
        title, msg_tmpl, icon, urgency = MESSAGES["CRITICAL_LOOP"]
        while True:
            await self.notify(urgency, icon, title, msg_tmpl.format(self.current_percentage))
            await asyncio.sleep(2)

    async def handle_change(self, percentage, state):
        self.current_percentage = percentage
        # Treat Fully Charged (4) the same as Charging (1)
        lookup_state = 1 if state in [1, 4] else state
        padded, unpadded = self.get_icon_formats(percentage)

        # 1. Handle Plug/Unplug Status Changes
        if state == 2 and self.last_state != 2 and self.last_state is not None:
            title, msg, icon_tmpl, urgency = MESSAGES["UNPLUGGED"]
            await self.notify(urgency, icon_tmpl.format(padded, unpadded), title, msg.format(percentage))
            self.notified_levels.clear()
        
        elif state in [1, 4] and self.last_state == 2:
            title, msg, icon_tmpl, urgency = MESSAGES["PLUGGED"]
            await self.notify(urgency, icon_tmpl.format(padded, unpadded), title, msg.format(percentage))
            self.notified_levels.clear()
            await self.stop_critical_loop()

        self.last_state = state

        # 2. Handle Specific Percentage Thresholds
        msg_key = (lookup_state, percentage)
        if msg_key in MESSAGES and msg_key not in self.notified_levels:
            title, msg, icon, urgency = MESSAGES[msg_key]
            # Formats icon name using either {0} (padded) or {1} (unpadded)
            formatted_icon = icon.format(padded, unpadded) if "{" in icon else icon
            await self.notify(urgency, formatted_icon, title, msg.format(percentage))
            self.notified_levels.add(msg_key)

        # 3. Critical Loop Control
        crit_val = MESSAGES.get("CRITICAL_THRESHOLD", 5)
        if state == 2 and percentage <= crit_val:
            if not self.critical_task:
                self.critical_task = asyncio.create_task(self.critical_loop())
        else:
            await self.stop_critical_loop()

    async def stop_critical_loop(self):
        if self.critical_task:
            self.critical_task.cancel()
            try:
                await self.critical_task
            except asyncio.CancelledError:
                pass
            self.critical_task = None

# ──────────────────────────────── MAIN SYSTEM ────────────────────────────────

async def run_monitor():
    # Deferred imports to log dependency errors
    try:
        from dbus_next.aio import MessageBus
        from dbus_next import BusType
    except ImportError as e:
        logger.error(f"DEPENDENCY MISSING: {e}. Install 'python-dbus-next'.")
        return

    # Robust Lock Mechanism using O_EXCL to prevent race conditions
    try:
        lock_fd = os.open(LOCK_FILE, os.O_CREAT | os.O_WRONLY | os.O_EXCL)
        os.write(lock_fd, str(os.getpid()).encode())
    except FileExistsError:
        with open(LOCK_FILE, 'r') as f:
            try:
                pid = int(f.read().strip())
                os.kill(pid, 0)
                return # Process is active
            except (ProcessLookupError, ValueError):
                os.remove(LOCK_FILE) # Stale lock, clean it up
                return await run_monitor() 

    logger.info("========== Battery Monitor Service Started ==========")
    
    try:
        # Connect to System Bus for UPower
        bus = await MessageBus(bus_type=BusType.SYSTEM).connect()
        intro = await bus.introspect('org.freedesktop.UPower', '/org/freedesktop/UPower')
        obj = bus.get_proxy_object('org.freedesktop.UPower', '/org/freedesktop/UPower', intro)
        upower = obj.get_interface('org.freedesktop.UPower')
        
        # Auto-select the battery device
        devices = await upower.call_enumerate_devices()
        bat_path = next((d for d in devices if 'battery' in d), None)
        if not bat_path:
            logger.error("No battery detected.")
            return

        bat_intro = await bus.introspect('org.freedesktop.UPower', bat_path)
        bat_obj = bus.get_proxy_object('org.freedesktop.UPower', bat_path, bat_intro)
        props = bat_obj.get_interface('org.freedesktop.DBus.Properties')
        
        monitor = BatteryMonitor()

        async def on_changed(interface, changed_props, invalidated):
            if 'Percentage' in changed_props or 'State' in changed_props:
                p = (await props.call_get('org.freedesktop.UPower.Device', 'Percentage')).value
                s = (await props.call_get('org.freedesktop.UPower.Device', 'State')).value
                await monitor.handle_change(int(p), s)

        props.on_properties_changed(on_changed)
        
        # Run initial status check on startup
        p_init = (await props.call_get('org.freedesktop.UPower.Device', 'Percentage')).value
        s_init = (await props.call_get('org.freedesktop.UPower.Device', 'State')).value
        await monitor.handle_change(int(p_init), s_init)

        # Handle SIGINT and SIGTERM for graceful systemd shutdown
        loop = asyncio.get_running_loop()
        stop_event = asyncio.Event()
        for sig in (signal.SIGINT, signal.SIGTERM):
            loop.add_signal_handler(sig, stop_event.set)
        
        await stop_event.wait()
        logger.info("Stopping Battery Monitor...")

    except Exception:
        logger.exception("Fatal error in main loop:")
    finally:
        os.close(lock_fd)
        if os.path.exists(LOCK_FILE):
            os.remove(LOCK_FILE)

if __name__ == "__main__":
    try:
        asyncio.run(run_monitor())
    except Exception as e:
        logger.error(f"Failed to start script: {e}")
