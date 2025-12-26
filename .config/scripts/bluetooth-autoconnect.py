#!/usr/bin/env python3
import logging
import signal
import sys
from gi.repository import GLib
from pydbus import SystemBus

# --- Configuration ---
LOG_LEVEL = logging.INFO
logging.basicConfig(
    level=LOG_LEVEL,
    format='%(asctime)s [%(levelname)s] %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger("BT-Autoconnect")

bus = SystemBus()
loop = GLib.MainLoop()

try:
    manager = bus.get("org.bluez", "/")
except Exception as e:
    logger.error(f"Could not connect to BlueZ: {e}")
    sys.exit(1)

def is_adapter_powered():
    """Checks if the Bluetooth radio is actually powered on."""
    try:
        objects = manager.GetManagedObjects()
        for path, ifaces in objects.items():
            if "org.bluez.Adapter1" in ifaces:
                if ifaces["org.bluez.Adapter1"].get("Powered"):
                    return True
    except: pass
    return False

def connect_all_trusted():
    """Main scanning and connection logic."""
    if not is_adapter_powered():
        # Silent skip - no log entry to keep console clean when OFF
        return False
    
    logger.info("Checking trusted devices status...")
    objects = manager.GetManagedObjects()
    found_disconnected = False
    connected_list = []

    for path, ifaces in objects.items():
        if "org.bluez.Device1" in ifaces:
            props = ifaces["org.bluez.Device1"]
            name = props.get("Name", "Unknown Device")
            
            if props.get("Trusted"):
                if props.get("Connected"):
                    connected_list.append(name)
                else:
                    found_disconnected = True
                    try:
                        dev = bus.get("org.bluez", path)
                        logger.info(f"Connecting to: {name}...")
                        dev.Connect()
                        logger.info(f"SUCCESS: {name} is now CONNECTED.")
                    except:
                        logger.info(f"Handshake failed: {name} (Device is likely off/out of range)")
    
    if connected_list and not found_disconnected:
        logger.info(f"Current Active Connections: {', '.join(connected_list)}")
    elif not found_disconnected:
        logger.info("No trusted devices found in range.")
        
    return False

def on_properties_changed(sender, path, interface, signal, params):
    if len(params) < 2: return
    iface, changed = params[0], params[1]

    # Adapter Power Toggle
    if iface == "org.bluez.Adapter1" and "Powered" in changed:
        is_on = changed["Powered"]
        logger.info(f"ADAPTER EVENT: Bluetooth is now {'ON' if is_on else 'OFF'}")
        if is_on:
            # Wait 2 seconds for hardware/driver to stabilize before scanning
            GLib.timeout_add(2000, connect_all_trusted)

    # Device Connection Change
    elif iface == "org.bluez.Device1" and "Connected" in changed:
        try:
            dev_obj = bus.get("org.bluez", path)
            name = getattr(dev_obj, "Name", "Unknown Device")
            if not changed["Connected"]:
                if is_adapter_powered():
                    logger.info(f"DEVICE EVENT: {name} DISCONNECTED. Retrying in 2s...")
                    GLib.timeout_add(2000, connect_all_trusted)
            else:
                logger.info(f"DEVICE EVENT: {name} CONNECTED.")
        except: pass

def signal_handler(sig, frame):
    logger.info("Termination signal received. Closing daemon...")
    loop.quit() 
    sys.exit(0)

# Register signals for clean exit
signal.signal(signal.SIGINT, signal_handler)
signal.signal(signal.SIGTERM, signal_handler)

bus.subscribe(iface="org.freedesktop.DBus.Properties",
              signal="PropertiesChanged",
              signal_fired=on_properties_changed)

logger.info("Bluetooth Autoconnect Daemon Started.")
connect_all_trusted()

try:
    loop.run()
except Exception as e:
    logger.error(f"Loop error: {e}")
    loop.quit()
