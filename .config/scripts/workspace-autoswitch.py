#!/usr/bin/env python3

import asyncio
import json
import os
import logging
from logging.handlers import RotatingFileHandler # Added for efficient log rotation
import signal
import sys
import fcntl # Added for robust kernel-level file locking
from pathlib import Path
from datetime import datetime

class HyprAutoswitch:
    def __init__(self):
        """Initialize paths and core state."""
        self.last_ws = None
        self.log_path = Path.home() / ".cache/autoswitch.log"
        self.pid_path = Path.home() / ".cache/autoswitch.pid"
        
        # Create cache dir if it doesn't exist
        self.log_path.parent.mkdir(parents=True, exist_ok=True)

        # ──────────────────────────────── LOGGING SETUP ────────────────────────────────
        # Setup Rotating Logger: 20KB is roughly 300-350 lines
        # backupCount=1 keeps one old log file (.log.1) before overwriting
        self.logger = logging.getLogger("HyprAutoswitch")
        self.logger.setLevel(logging.INFO)
        
        # Using RotatingFileHandler instead of manual line trimming for better performance
        handler = RotatingFileHandler(self.log_path, maxBytes=20000, backupCount=1)
        handler.setFormatter(logging.Formatter('%(asctime)s - %(message)s', '%Y-%m-%d %H:%M:%S'))
        self.logger.addHandler(handler)
        # ──────────────────────────────────────────────────────────────────────────────
        
        # This event allows us to shut down the script cleanly from anywhere
        self.stop_event = asyncio.Event()
        
        # Keep a reference to the file object to prevent it from being garbage collected (which releases the lock)
        self.lock_file = None
        
        # Ensure only one instance runs - MUST happen after logging setup
        self.handle_pid_lock()

    def handle_pid_lock(self):
        """Robust PID locking using kernel-level flock. 
        Automatically handles stale PIDs and reboots."""
        try:
            # Open file in append mode so we don't truncate it before checking the lock
            self.lock_file = open(self.pid_path, 'a+')
            
            # Try to acquire an exclusive lock (LOCK_EX) without blocking (LOCK_NB)
            fcntl.flock(self.lock_file, fcntl.LOCK_EX | fcntl.LOCK_NB)
            
            # If we reach here, we have the lock. Now we write our PID.
            self.lock_file.seek(0)
            self.lock_file.truncate()
            self.lock_file.write(str(os.getpid()))
            self.lock_file.flush()
            
        except (IOError, BlockingIOError):
            # If the lock is held by someone else, read their PID for the message
            try:
                self.lock_file.seek(0)
                old_pid = self.lock_file.read().strip()
            except:
                old_pid = "Unknown"
            
            # LOGGING THE ERROR BEFORE EXITING:
            # This ensures that even if started by exec-once, you see why it failed in the log.
            self.log(f"STARTUP ERROR: Autoswitch already running (Locked by PID {old_pid}). Exiting.")
            sys.exit(0)

    def log(self, message):
        """Log messages using the RotatingFileHandler (automatically keeps file size small)."""
        try:
            self.logger.info(message)
        except Exception as e:
            print(f"Logging error: {e}")

    async def get_hypr_data(self, command):
        """Fetch JSON data from Hyprland using async subprocess to avoid freezing."""
        try:
            proc = await asyncio.create_subprocess_exec(
                "hyprctl", command, "-j",
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            stdout, stderr = await proc.communicate()
            if proc.returncode != 0:
                self.log(f"Hyprctl error ({command}): {stderr.decode().strip()}")
                return None
            return json.loads(stdout.decode()) if stdout else None
        except Exception as e:
            self.log(f"Data Fetch Error ({command}): {e}")
            return None

    async def switch_if_needed(self, current_ws):
        """Detects if a workspace is empty and switches focus to an occupied one."""
        clients = await self.get_hypr_data("clients")
        if not clients: return

        # Check how many windows are currently on the 'current_ws'
        ws_windows = [c for c in clients if c.get('workspace', {}).get('id') == current_ws]
        
        # Get list of all workspace IDs that actually have windows
        active_ws_ids = sorted({
            c.get('workspace', {}).get('id') 
            for c in clients 
            if c.get('workspace', {}).get('id') is not None
        })

        # Logic: If 0 windows left on this workspace AND it was the one we were just looking at
        if len(ws_windows) == 0 and self.last_ws == current_ws:
            if not active_ws_ids: return
            
            # Find the best workspace to jump to (the next one or the last available)
            candidate = next((id for id in active_ws_ids if id > current_ws), None)
            if candidate is None: 
                candidate = active_ws_ids[-1]
            
            if candidate != current_ws:
                # Use async subprocess to dispatch the change to Hyprland
                proc = await asyncio.create_subprocess_exec(
                    "hyprctl", "dispatch", "workspace", str(candidate),
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.PIPE
                )
                await proc.communicate()
                
                if proc.returncode == 0:
                    self.log(f"Switched {current_ws} -> {candidate} (Workspace empty)")
                    self.last_ws = candidate

        # If the workspace has windows, update 'last_ws' so we know where focus is
        if len(ws_windows) > 0:
            self.last_ws = current_ws

    async def listen(self):
        """Connects to Hyprland socket and listens for events in real-time."""
        sig = os.getenv("HYPRLAND_INSTANCE_SIGNATURE")
        xdg_runtime = os.getenv("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
        
        if not sig:
            self.log("CRITICAL: HYPRLAND_INSTANCE_SIGNATURE not found. Are you in Hyprland?")
            return

        socket_path = Path(xdg_runtime) / "hypr" / sig / ".socket2.sock"

        # Register system signals (SIGINT/SIGTERM) to trigger our stop_event
        loop = asyncio.get_running_loop()
        for s in (signal.SIGINT, signal.SIGTERM):
            loop.add_signal_handler(s, self.stop_event.set)

        # Primary Reconnection Loop
        while not self.stop_event.is_set():
            try:
                if not socket_path.exists():
                    await asyncio.sleep(1) # Wait for Hyprland to start if necessary
                    continue

                # Open the unix socket connection
                reader, writer = await asyncio.open_unix_connection(str(socket_path))
                self.log("Successfully connected to Hyprland socket.")
                
                while not self.stop_event.is_set():
                    # We create explicit tasks to satisfy asyncio.wait requirements
                    line_task = asyncio.create_task(reader.readline())
                    stop_task = asyncio.create_task(self.stop_event.wait())
                    
                    # Wait for either a new line from Hyprland OR the script to be stopped
                    done, pending = await asyncio.wait(
                        [line_task, stop_task],
                        return_when=asyncio.FIRST_COMPLETED
                    )
                    
                    # Cleanup the task that didn't complete
                    for task in pending:
                        task.cancel()

                    # Exit inner loop if stop_event was triggered
                    if self.stop_event.is_set():
                        break
                        
                    line = await line_task
                    if not line: break # Socket connection lost
                    
                    event = line.decode().strip()
                    
                    # We check for events that signify a window was closed or moved
                    if any(event.startswith(e) for e in ("activewindow>>", "closewindow>>", "movewindow>>")):
                        active_ws_data = await self.get_hypr_data("activeworkspace")
                        if active_ws_data and 'id' in active_ws_data:
                            await self.switch_if_needed(active_ws_data['id'])

                # Close socket cleanly
                writer.close()
                await writer.wait_closed()

            except (ConnectionRefusedError, FileNotFoundError):
                # Silently retry connection if Hyprland isn't ready
                await asyncio.sleep(2)
            except Exception as e:
                self.log(f"Socket Loop Error: {e}")
                await asyncio.sleep(2)
        
        self.cleanup()

    def cleanup(self):
        """Cleanup logic called on exit."""
        if self.pid_path.exists():
            # Closing the file handle and unlinking will release the flock
            if self.lock_file:
                self.lock_file.close()
            self.pid_path.unlink()
        self.log("Autoswitch service stopped cleanly.")

if __name__ == "__main__":
    # Initialize the app
    app = HyprAutoswitch()
    try:
        # Start the async event loop
        asyncio.run(app.listen())
    except Exception as e:
        # Ensure we always log fatal crashes
        app.log(f"Fatal Crash: {e}")
        app.cleanup()
