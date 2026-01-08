#!/usr/bin/env python3

import os
import logging
from logging.handlers import RotatingFileHandler
import signal
import sys
from gi.repository import GLib

# --- Import pydbus ---
try:
    from pydbus import SystemBus
except ImportError:
    print("Error: 'pydbus' module not found. Install via 'sudo apt install python3-pydbus' or 'pip install pydbus'")
    sys.exit(1)

# --- Configuration ---
LOG_FILE = os.path.expanduser("~/.cache/bluetooth-autoconnect.log")
os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)

# Setup Logger
handler = RotatingFileHandler(LOG_FILE, maxBytes=1024*1024, backupCount=1)
handler.setFormatter(logging.Formatter('%(asctime)s [%(levelname)s] %(message)s', '%Y-%m-%d %H:%M:%S'))
logger = logging.getLogger("BT-Autoconnect")
logger.setLevel(logging.INFO)
logger.addHandler(handler)

# Global State
bus = SystemBus()
loop = GLib.MainLoop()
manager = None

try:
    manager = bus.get("org.bluez", "/")
except Exception as e:
    logger.error(f"Failed to access BlueZ manager: {e}")
    sys.exit(1)

def get_connected_trusted_device():
    """Returns the name of a connected trusted device if one exists, else None."""
    try:
        objects = manager.GetManagedObjects()
        for path, ifaces in objects.items():
            if "org.bluez.Device1" in ifaces:
                props = ifaces["org.bluez.Device1"]
                if props.get("Trusted") and props.get("Connected"):
                    return props.get("Name", "Unknown Device")
    except Exception:
        pass
    return None

def is_adapter_powered():
    try:
        objects = manager.GetManagedObjects()
        for path, ifaces in objects.items():
            adapter = ifaces.get("org.bluez.Adapter1")
            if adapter and adapter.get("Powered"):
                return True
    except Exception:
        pass
    return False

def connect_device(path, props):
    """Attempts to connect to a single device."""
    name = props.get("Name", "Unknown Device")
    logger.info(f"Attempting to connect to: {name}...")
    
    try:
        dev_obj = bus.get("org.bluez", path)
        dev_obj.Connect()
        logger.info(f"SUCCESS: Connected to {name}")
        return True
    except Exception as e:
        # Improved Log: explicitly state failure so user knows we are moving on
        logger.info(f"Connection failed for {name} (Device likely OFF or out of range).")
        return False

def scan_and_connect():
    """
    Scans for trusted devices. 
    Aborts immediately if ANY trusted device is already connected.
    Stops scanning after the first successful connection attempt.
    """
    # [NEW LOG] Explicitly state if we are skipping due to power off
    if not is_adapter_powered():
        logger.info("Bluetooth Adapter is OFF. Skipping active scan.")
        return

    # 1. Check if we are already happy (Connected to a trusted device)
    existing_device = get_connected_trusted_device()
    if existing_device:
        logger.info(f"Scan aborted: Already connected to '{existing_device}'.")
        return

    logger.info("Scanning for available trusted devices...")
    objects = manager.GetManagedObjects()
    
    # 2. Try to connect to disconnected trusted devices
    connection_made = False
    for path, ifaces in objects.items():
        if "org.bluez.Device1" in ifaces:
            props = ifaces["org.bluez.Device1"]
            if props.get("Trusted") and not props.get("Connected"):
                # Try to connect. If successful, STOP looping.
                if connect_device(path, props):
                    connection_made = True
                    break
    
    # [NEW LOG] Explicitly state we are done scanning and going silent
    if not connection_made:
        logger.info("Scan finished. No devices connected. Entering passive event mode.")

def on_properties_changed(sender, path, interface, signal, params):
    """Handles Adapter Power and Device Connection events."""
    if len(params) < 2: return
    iface, changed = params[0], params[1]

    # CASE 1: Adapter Powered ON
    if iface == "org.bluez.Adapter1" and "Powered" in changed:
        if changed["Powered"]:
            logger.info("Adapter powered ON. Waiting 2s for stability...")
            GLib.timeout_add(2000, scan_and_connect)
        else:
            logger.info("Adapter powered OFF. Going silent.")

    # CASE 2: Device Connected (Logging only)
    if iface == "org.bluez.Device1" and "Connected" in changed:
        try:
            dev = bus.get("org.bluez", path)
            name = dev.Name
            status = "CONNECTED" if changed["Connected"] else "DISCONNECTED"
            logger.info(f"Event: {name} {status}.")
        except: pass

def on_interfaces_added(sender, object_path, iface, signal, params):
    """
    Handles new devices appearing in the tree (e.g. entering range).
    """
    if len(params) < 2: return
    
    new_path = params[0]
    interfaces = params[1]

    if "org.bluez.Device1" in interfaces:
        # Check if we are already connected to something before reacting to a new device
        existing = get_connected_trusted_device()
        if existing:
            return 

        props = interfaces["org.bluez.Device1"]
        if props.get("Trusted"):
            logger.info(f"New trusted device detected: {props.get('Name')}")
            connect_device(new_path, props)

def signal_handler(sig, frame):
    logger.info("Stopping Bluetooth Autoconnect...")
    loop.quit()

if __name__ == "__main__":
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    logger.info("Service Started. Subscribing to system events...")

    bus.subscribe(iface="org.freedesktop.DBus.Properties",
                  signal="PropertiesChanged",
                  signal_fired=on_properties_changed)

    bus.subscribe(iface="org.freedesktop.DBus.ObjectManager",
                  signal="InterfacesAdded",
                  signal_fired=on_interfaces_added)

    # Initial Run
    scan_and_connect()

    try:
        loop.run()
    except Exception as e:
        logger.error(f"Main loop crashed: {e}")
