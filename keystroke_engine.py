"""
keystroke_engine.py  —  SecureFlow Keystroke Dynamics Engine
=============================================================
Wraps the producer/consumer capture logic from secureflow_logger.py
into a clean OOP API that vault_gui.py can drive from the ML Insights tab.

Key design rules
----------------
- Zero UI coupling: this module has no tkinter imports.
- Thread-safe: all state shared between threads is protected by a lock.
- RAM-safe: ring buffer capped at MAX_RING_SIZE rows (200).
- Disk-safe: flushes every FLUSH_INTERVAL keystrokes (50).
- Silent start: calling start() attaches the Win32 hook with no console output.
- Model-agnostic: load_model() accepts any sklearn estimator with predict_proba().
  If the file is absent, inference methods return None gracefully.

Feature vector for inference (per rolling window of `window` clean rows):
    [mean_dwell, std_dwell, mean_flight, std_flight, p25_dwell, p75_dwell]
"""

from __future__ import annotations

import csv
import logging
import math
import queue
import threading
import time
from collections import deque
from pathlib import Path
from typing import Any

import numpy as np

logger = logging.getLogger(__name__)

# ──────────────────────────────────────────────
#  CONSTANTS
# ──────────────────────────────────────────────

FLUSH_INTERVAL         = 50     # Rows buffered before disk write
FLIGHT_OUTLIER_THR     = 2.0    # Seconds; pauses longer → flagged Outlier
MAX_RING_SIZE          = 200    # Rolling in-RAM window for live chart + inference
MIN_INFERENCE_WINDOW   = 20     # Need at least this many clean rows to infer

CSV_HEADERS = [
    "Key", "Press_Time", "Release_Time",
    "Dwell_Time", "Flight_Time", "Outlier",
    "User_Name", "Session_Type",
]

MODIFIER_KEYS = {
    "shift", "left shift", "right shift",
    "ctrl", "left ctrl", "right ctrl",
    "alt", "left alt", "right alt",
    "caps lock", "windows", "cmd", "super",
}

DROP_KEYS = {
    "f1", "f2", "f3", "f4", "f5", "f6",
    "f7", "f8", "f9", "f10", "f11", "f12",
    "insert", "delete", "home", "end",
    "page up", "page down",
    "up", "down", "left", "right",
    "num lock", "scroll lock", "print screen", "pause",
}

SHIFT_MAP = {
    "`": "~",  "1": "!",  "2": "@",  "3": "#",
    "4": "$",  "5": "%",  "6": "^",  "7": "&",
    "8": "*",  "9": "(",  "0": ")",  "-": "_",
    "=": "+",  "[": "{",  "]": "}", "\\": "|",
    ";": ":",  "'": '"',  ",": "<",  ".": ">",
    "/": "?",
}

KEEP_NAMED = {
    "space": "space", "enter": "enter", "tab": "tab",
    "backspace": "backspace", "escape": "escape",
}


# ──────────────────────────────────────────────
#  KEYSTROKE ENGINE
# ──────────────────────────────────────────────

class KeystrokeEngine:
    """
    Manages global keystroke capture, CSV persistence, and ML inference.

    Lifecycle:
        engine = KeystrokeEngine()
        engine.load_model("keystroke_model.pkl")   # optional
        engine.start(output_dir=".", user_name="Sushil")
        # ... app runs ...
        path = engine.stop()   # returns the CSV path
    """

    def __init__(self) -> None:
        self._lock = threading.Lock()

        # Producer state (only touched from hook thread — no lock needed)
        self._modifier_state = {"shift": False, "caps_lock": False}
        self._event_queue: queue.Queue = queue.Queue()

        # Consumer state (protected by _lock where accessed cross-thread)
        self._ring: deque[dict] = deque(maxlen=MAX_RING_SIZE)
        self._total_keys: int = 0
        self._session_start: float | None = None
        self._csv_path: Path | None = None
        self._user_name: str = "unknown"
        self._session_type: str = "live"

        # Thread handles
        self._consumer_thread: threading.Thread | None = None
        self._hook_attached: bool = False

        # Model
        self._model: Any = None
        self._model_path: str | None = None

        # Running state
        self._running: bool = False

    # ── Public API ────────────────────────────────────────────────────

    def start(self, output_dir: str = ".", user_name: str = "SecureFlow") -> None:
        """Attach the global Win32 keyboard hook and start the consumer thread."""
        if self._running:
            return

        try:
            import keyboard  # noqa: PLC0415
        except ImportError:
            logger.error("KeystrokeEngine: 'keyboard' package not installed. "
                         "Run: pip install keyboard")
            return

        output_path = Path(output_dir)
        output_path.mkdir(parents=True, exist_ok=True)

        ts = int(time.time())
        self._csv_path = output_path / f"{user_name}_live_{ts}.csv"
        self._user_name = user_name
        self._session_type = "live"
        self._session_start = time.perf_counter()

        with self._lock:
            self._ring.clear()
            self._total_keys = 0
            self._running = True

        # Reset modifier state for fresh session
        self._modifier_state = {"shift": False, "caps_lock": False}

        # Drain any stale events left in queue from a previous session
        while not self._event_queue.empty():
            try:
                self._event_queue.get_nowait()
            except queue.Empty:
                break

        # Start consumer thread first (it initialises the CSV)
        self._consumer_thread = threading.Thread(
            target=self._consumer_loop,
            args=(self._csv_path,),
            daemon=True,
            name="sf-ks-consumer",
        )
        self._consumer_thread.start()

        # Attach global hook
        keyboard.hook(self._producer_hook)
        self._hook_attached = True
        logger.info("KeystrokeEngine: capture started → %s", self._csv_path)

    def stop(self) -> Path | None:
        """Detach hook, flush remaining buffer, return the CSV path."""
        if not self._running:
            return self._csv_path

        try:
            import keyboard  # noqa: PLC0415
            if self._hook_attached:
                keyboard.unhook_all()
                self._hook_attached = False
        except Exception:
            pass

        # Send sentinel to consumer
        self._event_queue.put(None)

        # Wait up to 5 s for clean shutdown
        if self._consumer_thread and self._consumer_thread.is_alive():
            self._consumer_thread.join(timeout=5)

        with self._lock:
            self._running = False

        logger.info("KeystrokeEngine: capture stopped → %s", self._csv_path)
        return self._csv_path

    def is_running(self) -> bool:
        return self._running

    def get_total_keys(self) -> int:
        with self._lock:
            return self._total_keys

    def get_elapsed_seconds(self) -> float:
        if self._session_start is None:
            return 0.0
        return time.perf_counter() - self._session_start

    def get_ring_buffer(self) -> list[dict]:
        """Return a snapshot of the recent ring buffer (thread-safe copy)."""
        with self._lock:
            return list(self._ring)

    def get_csv_path(self) -> Path | None:
        return self._csv_path

    def load_model(self, model_path: str) -> bool:
        """
        Load a scikit-learn model from a .pkl file.
        Returns True on success, False if file not found or load fails.
        """
        p = Path(model_path)
        if not p.is_file():
            logger.info("KeystrokeEngine: model file not found at %s", model_path)
            self._model = None
            self._model_path = None
            return False
        try:
            import joblib  # noqa: PLC0415
            import warnings
            try:
                from sklearn.exceptions import InconsistentVersionWarning
                warnings.filterwarnings("ignore", category=InconsistentVersionWarning)
            except ImportError:
                pass
            self._model = joblib.load(p)
            self._model_path = str(p)
            logger.info("KeystrokeEngine: model loaded from %s", p)
            return True
        except Exception as exc:
            logger.warning("KeystrokeEngine: model load failed: %s", exc)
            self._model = None
            self._model_path = None
            return False

    def model_loaded(self) -> bool:
        return self._model is not None

    def model_name(self) -> str:
        if self._model_path:
            return Path(self._model_path).name
        return "Not loaded"

    def infer(self, window: int = 50) -> float | None:
        """
        Run model inference on the last `window` clean (non-outlier) rows.
        Returns anomaly probability (0.0 = legitimate, 1.0 = intruder),
        or None if model not loaded or insufficient data.
        """
        if self._model is None:
            return None

        rows = self.get_ring_buffer()
        # Keep only non-outlier rows with valid numeric values
        clean = [
            r for r in rows
            if not r.get("outlier", True)
            and r.get("dwell") is not None
            and not math.isnan(r["dwell"])
            and r.get("flight") is not None
            and not math.isnan(r["flight"])
        ]

        if len(clean) < MIN_INFERENCE_WINDOW:
            return None

        recent = clean[-window:]
        dwells  = np.array([r["dwell"]  for r in recent])
        flights = np.array([r["flight"] for r in recent])

        features = np.array([[
            float(np.mean(dwells)),
            float(np.std(dwells)),
            float(np.mean(flights)),
            float(np.std(flights)),
            float(np.percentile(dwells, 25)),
            float(np.percentile(dwells, 75)),
        ]])

        try:
            proba = self._model.predict_proba(features)
            # Assume class 1 = intruder (standard convention)
            if proba.shape[1] >= 2:
                return float(proba[0, 1])
            return float(proba[0, 0])
        except Exception as exc:
            logger.warning("KeystrokeEngine: inference failed: %s", exc)
            return None

    # ── Producer (Win32 hook thread) ──────────────────────────────────

    def _translate_key(self, raw_name: str) -> str | None:
        key = raw_name.lower()
        if key in MODIFIER_KEYS:
            return None
        if key in DROP_KEYS:
            return None
        if len(raw_name) == 1 and raw_name.isalpha():
            if self._modifier_state["shift"] ^ self._modifier_state["caps_lock"]:
                return raw_name.upper()
            return raw_name.lower()
        if self._modifier_state["shift"] and raw_name in SHIFT_MAP:
            return SHIFT_MAP[raw_name]
        if key in KEEP_NAMED:
            return KEEP_NAMED[key]
        if len(raw_name) == 1:
            return raw_name
        return None

    def _producer_hook(self, event) -> None:
        timestamp = time.perf_counter()
        raw_name = event.name
        if raw_name is None:
            return

        key_lower = raw_name.lower()

        # Modifier tracking
        if key_lower in ("shift", "left shift", "right shift"):
            self._modifier_state["shift"] = (event.event_type == "down")
            return
        if key_lower == "caps lock" and event.event_type == "down":
            self._modifier_state["caps_lock"] = not self._modifier_state["caps_lock"]
            return
        if key_lower in MODIFIER_KEYS:
            return

        if event.event_type == "down":
            translated = self._translate_key(raw_name)
            if translated is not None:
                self._event_queue.put(("down", translated, timestamp))
        elif event.event_type == "up":
            translated = self._translate_key(raw_name)
            if translated is not None:
                self._event_queue.put(("up", translated, timestamp))

    # ── Consumer (daemon thread) ───────────────────────────────────────

    def _consumer_loop(self, csv_path: Path) -> None:
        active_keys: dict[str, tuple[float, float]] = {}
        last_release_time: float | None = None
        buffer: list[list] = []

        # Initialise CSV with headers
        try:
            with open(csv_path, "w", newline="", encoding="utf-8") as f:
                csv.writer(f).writerow(CSV_HEADERS)
        except OSError as exc:
            logger.error("KeystrokeEngine: cannot write CSV %s: %s", csv_path, exc)
            return

        while True:
            item = self._event_queue.get()

            if item is None:  # Sentinel: graceful shutdown
                if buffer:
                    self._flush(csv_path, buffer)
                self._event_queue.task_done()
                break

            event_type, key, timestamp = item

            if event_type == "down":
                if key not in active_keys:
                    flight_time = (
                        timestamp - last_release_time
                        if last_release_time is not None
                        else 0.0
                    )
                    active_keys[key] = (timestamp, flight_time)

            elif event_type == "up":
                if key in active_keys:
                    press_time, flight_time = active_keys.pop(key)
                    dwell_time = timestamp - press_time
                    last_release_time = timestamp

                    is_outlier = flight_time > FLIGHT_OUTLIER_THR
                    logged_flight = math.nan if is_outlier else flight_time

                    row = [
                        key, press_time, timestamp,
                        dwell_time, logged_flight, is_outlier,
                        self._user_name, self._session_type,
                    ]
                    buffer.append(row)

                    # Update ring buffer (thread-safe)
                    ring_entry = {
                        "key":     key,
                        "dwell":   dwell_time,
                        "flight":  logged_flight,
                        "outlier": is_outlier,
                        "t":       timestamp,
                    }
                    with self._lock:
                        self._ring.append(ring_entry)
                        self._total_keys += 1

                    if len(buffer) >= FLUSH_INTERVAL:
                        self._flush(csv_path, buffer)
                        buffer.clear()

            self._event_queue.task_done()

    @staticmethod
    def _flush(csv_path: Path, buffer: list[list]) -> None:
        try:
            with open(csv_path, "a", newline="", encoding="utf-8") as f:
                csv.writer(f).writerows(buffer)
        except OSError as exc:
            logger.warning("KeystrokeEngine: flush failed: %s", exc)


# ──────────────────────────────────────────────
#  SINGLETON — used by vault_gui.py
# ──────────────────────────────────────────────

_engine: KeystrokeEngine | None = None


def get_engine() -> KeystrokeEngine:
    global _engine
    if _engine is None:
        _engine = KeystrokeEngine()
    return _engine


# ──────────────────────────────────────────────
#  SMOKE TEST
# ──────────────────────────────────────────────

if __name__ == "__main__":
    import time as _time

    print("[*] SecureFlow Keystroke Engine — smoke test")
    print("    Type for 10 seconds, then we print the ring buffer.\n")

    eng = get_engine()
    eng.start(output_dir=".", user_name="test")
    _time.sleep(10)
    path = eng.stop()

    rows = eng.get_ring_buffer()
    print(f"\n[+] Captured {eng.get_total_keys()} keystrokes")
    print(f"[+] Ring buffer entries: {len(rows)}")
    for r in rows[-10:]:
        dwell_ms = r["dwell"] * 1000
        flight_ms = r["flight"] * 1000 if not math.isnan(r["flight"]) else float("nan")
        print(f"    {r['key']:12s}  dwell={dwell_ms:6.1f}ms  flight={flight_ms:6.1f}ms  outlier={r['outlier']}")
    print(f"\n[+] CSV saved: {path}")
