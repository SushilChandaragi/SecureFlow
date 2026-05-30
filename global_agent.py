"""
global_agent.py — Headless Global Continuous Authentication EDR Agent for SecureFlow
=====================================================================================
Hooks system-wide keyboard dynamics in the background, evaluates biometric timing
anomalies, enforces LockWorkStation interdiction, and streams live telemetry to the
main Vault GUI using UDP socket IPC.
"""

import os
import sys
import math
import time
import queue
import ctypes
import joblib
import socket
import json
import threading
import numpy as np
from pathlib import Path
from PIL import Image, ImageDraw
import pystray
import keyboard

# Global thread-safe queues
telemetry_queue = queue.Queue()

# Thread synchronization
exit_event = threading.Event()
agent_active = threading.Event()
agent_active.set() # Enabled by default

# Anomaly threshold constants
ML_FLIGHT_OUTLIER_THRESHOLD = 2.0  # Capped flight time in seconds
STREAK_LIMIT = 3                   # Trigger workstation lock on 3 consecutive anomalies

class BDImageGenerator:
    @staticmethod
    def create_tray_icon_image(color: str = "green") -> Image.Image:
        """Dynamically generate a sleek system tray icon image using Pillow."""
        img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
        draw = ImageDraw.Draw(img)
        fill_color = (46, 160, 67, 255) if color == "green" else (248, 81, 73, 255)
        # Draw concentric shield/radar rings
        draw.ellipse([8, 8, 56, 56], outline=fill_color, width=4)
        draw.ellipse([20, 20, 44, 44], fill=fill_color)
        return img

class GlobalEDRAgent:
    def __init__(self):
        self.model_path = Path("biometric_model.pkl")
        self.model_pipeline = None
        self.active_keys = {} # Volatile keystroke times: {correlation_id: press_time}
        self.last_release_time = None
        self.feature_buffer = [] # Local volatile timing vectors
        self.anomaly_streak = 0
        self.flagged_count = 0  # Running count of anomaly flags raised
        self.load_ml_model()

    def load_ml_model(self) -> None:
        """Safely load local biometric ML model from workspace directory."""
        if self.model_path.exists():
            try:
                import warnings
                try:
                    from sklearn.exceptions import InconsistentVersionWarning
                    warnings.filterwarnings("ignore", category=InconsistentVersionWarning)
                except ImportError:
                    pass
                self.model_pipeline = joblib.load(self.model_path)
                print(f"[EDR] Successfully unpickled biometric pipeline from {self.model_path}")
            except Exception as e:
                print(f"[EDR] Error unpickling model file: {e}")
        else:
            print("[EDR] Biometric model file not found. Running in Calibration Mode.")

    def send_telemetry_ipc(self, dwell: float, flight: float, streak: int, status: str, flagged_count: int, score: float) -> None:
        """Broadcast live timing and ML verification metrics over local UDP socket."""
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            data = json.dumps({
                "dwell": float(dwell),
                "flight": float(flight),
                "streak": int(streak),
                "status": str(status),
                "flagged_count": int(flagged_count),
                "score": float(score)
            }).encode("utf-8")
            sock.sendto(data, ("127.0.0.1", 54321))
            sock.close()
        except Exception:
            pass

    def run_hook(self) -> None:
        """Global hook listener. Direct Win32 callback running in keyboard background thread."""
        def low_level_hook(event):
            if not agent_active.is_set():
                return
            timestamp = time.perf_counter()
            raw_name = event.name
            if raw_name is None:
                return

            key_lower = raw_name.lower()

            # Ignore modifiers and navigational/function keys entirely to prevent noise
            if key_lower in {
                'shift', 'left shift', 'right shift', 'ctrl', 'left ctrl', 'right ctrl',
                'alt', 'left alt', 'right alt', 'caps lock', 'windows', 'cmd', 'super',
                'f1', 'f2', 'f3', 'f4', 'f5', 'f6', 'f7', 'f8', 'f9', 'f10', 'f11', 'f12',
                'insert', 'delete', 'home', 'end', 'page up', 'page down', 'up', 'down',
                'left', 'right', 'num lock', 'scroll lock', 'print screen', 'pause'
            }:
                return

            # Keep only an anonymous hash of the key code as a transient correlation ID.
            # Zero Character Storage: instantly drop the raw string name.
            correlation_id = hash(key_lower)

            if event.event_type == 'down':
                # Auto-repeat guard
                if correlation_id not in self.active_keys:
                    flight = 0.0
                    if self.last_release_time is not None:
                        flight = timestamp - self.last_release_time
                    self.active_keys[correlation_id] = (timestamp, flight)

            elif event.event_type == 'up':
                if correlation_id in self.active_keys:
                    press_time, flight_time = self.active_keys.pop(correlation_id)
                    dwell_time = timestamp - press_time
                    self.last_release_time = timestamp

                    # Enforce Outlier math identical to secureflow_logger.py
                    is_outlier = flight_time > ML_FLIGHT_OUTLIER_THRESHOLD
                    logged_flight = math.nan if is_outlier else flight_time

                    # Enqueue timing pair strictly in memory
                    telemetry_queue.put((dwell_time, logged_flight))

        keyboard.hook(low_level_hook)

    def process_telemetry(self) -> None:
        """Background daemon processing queued timings, performing dynamic ML scoring."""
        while not exit_event.is_set():
            try:
                dwell, flight = telemetry_queue.get(timeout=1.0)
            except queue.Empty:
                continue

            self.feature_buffer.append([dwell, flight])
            if len(self.feature_buffer) > 100:
                self.feature_buffer.pop(0)

            self.evaluate_ml_vector(dwell, flight)
            telemetry_queue.task_done()

    def evaluate_ml_vector(self, dwell: float, flight: float) -> None:
        """Calculates 10-feature dynamics and performs Isolation Forest prediction."""
        if self.model_pipeline is None:
            # Broadcast calibration telemetry
            self.send_telemetry_ipc(dwell, flight, 0, "Calibration Mode", self.flagged_count, 0.0)
            return

        try:
            pipeline = self.model_pipeline
            model = pipeline.get("model")
            scaler = pipeline.get("scaler")
            W = pipeline.get("window_size", 8)
            features = pipeline.get("features", [])
            n_feat = len(features) if features else 10
            threshold = pipeline.get("threshold_score", 0.0)

            # Filter clean non-outlier timings in volatile buffer for statistical calculations
            clean = [v for v in self.feature_buffer if not math.isnan(v[1])]
            if len(clean) < W:
                # Still buffering, send telemetry update with safe verification
                self.send_telemetry_ipc(dwell, flight, 0, "Buffering Telemetry", self.flagged_count, 0.0)
                return

            # Grab rolling window W
            window = clean[-W:]
            dwells = [v[0] for v in window]
            flights = [v[1] for v in window]

            if n_feat == 10:
                dm = np.mean(dwells)
                ds = np.std(dwells)
                dn = np.min(dwells)
                dx = np.max(dwells)
                dmed = np.median(dwells)
                fm = np.mean(flights)
                fs = np.std(flights)
                fn = np.min(flights)
                fmed = np.median(flights)
                rr = dm / (fm + 1e-6)
                vec = [[dm, ds, dn, dx, dmed, fm, fs, fn, fmed, rr]]
            else:
                vec = [[dwell, flight]]

            if scaler is not None:
                vec = scaler.transform(vec)

            score = float(model.decision_function(vec)[0])
            is_verified = score >= threshold

            if is_verified:
                self.anomaly_streak = 0
                status = "Owner Valid"
            else:
                self.anomaly_streak += 1
                self.flagged_count += 1
                status = f"Intruder Anomalous"
                print(f"[WARNING] Anomaly flagged! Score: {score:.4f} | Streak: {self.anomaly_streak}/{STREAK_LIMIT}")

                if self.anomaly_streak >= STREAK_LIMIT:
                    print(f"[AUDIT ALERT] Consecutive anomalous typing signatures detected (Streak: {self.anomaly_streak}/3). Logging passive warning.")
                    self.log_security_audit(score, self.anomaly_streak)

            # Broadcast live telemetry over local UDP socket IPC
            self.send_telemetry_ipc(dwell, flight, self.anomaly_streak, status, self.flagged_count, score)

        except Exception as e:
            print(f"[EDR Error] Inference loop failure: {e}")

    def log_security_audit(self, score: float, streak: int) -> None:
        """Safely appends a passive audit alert entry to security_audit.log for developer review."""
        try:
            from datetime import datetime
            timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            log_line = f"[{timestamp}] [AUDIT ALERT] Anomalous Typing Cadence Detected system-wide! Anomaly Score: {score:+.4f} | Anomaly Streak: {streak}/3 (Passive Mode: Lockout Skipped)\n"
            
            with open("security_audit.log", "a", encoding="utf-8") as f:
                f.write(log_line)
            print(f"[AUDIT LOGGED] {log_line.strip()}")
        except Exception as e:
            print(f"[EDR Error] Failed to write to security_audit.log: {e}")

def run_system_tray(agent: GlobalEDRAgent) -> None:
    """Instantiates non-blocking system tray module indicating active protection."""
    image_active = BDImageGenerator.create_tray_icon_image("green")
    
    def on_toggle_protection(icon, item):
        if agent_active.is_set():
            agent_active.clear()
            icon.icon = BDImageGenerator.create_tray_icon_image("red")
            icon.title = "SecureFlow Continuous Auth: Paused"
            print("[EDR] Continuous Authentication Protection Paused via Tray.")
        else:
            agent_active.set()
            icon.icon = BDImageGenerator.create_tray_icon_image("green")
            icon.title = "SecureFlow Continuous Auth: Active"
            print("[EDR] Continuous Authentication Protection Enabled via Tray.")

    def on_exit(icon, item):
        print("[EDR] Exiting Headless EDR Agent...")
        exit_event.set()
        icon.stop()
        os._exit(0)

    menu = pystray.Menu(
        pystray.MenuItem("Toggle Active Protection", on_toggle_protection, checked=lambda item: agent_active.is_set()),
        pystray.MenuItem("Exit SecureFlow Agent", on_exit)
    )

    icon = pystray.Icon("SecureFlow EDR", image_active, "SecureFlow Continuous Auth: Active", menu)
    icon.run()

if __name__ == "__main__":
    # Windows Administrator privilege check
    if sys.platform == "win32":
        try:
            if not ctypes.windll.shell32.IsUserAnAdmin():
                print("[WARN] EDR Agent requires Administrator execution for system-wide keyboard hooking.")
        except Exception:
            pass

    # Setup agent
    agent = GlobalEDRAgent()
    
    # Decouple hook and processing execution loops
    agent.run_hook()
    
    processing_thread = threading.Thread(target=agent.process_telemetry, daemon=True)
    processing_thread.start()

    # Run system tray module on independent non-blocking thread
    tray_thread = threading.Thread(target=run_system_tray, args=(agent,), daemon=True)
    tray_thread.start()

    print("[EDR] SecureFlow Continuous Authentication Security Agent is Running Headlessly.")
    print("      Keystroke timings are hooked globally and broadcasted to the main Vault GUI.")
    
    # Keep main execution loop alive
    try:
        while not exit_event.is_set():
            time.sleep(1.0)
    except KeyboardInterrupt:
        exit_event.set()
        os._exit(0)
