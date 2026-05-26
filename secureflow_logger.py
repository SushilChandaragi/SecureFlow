"""
secureflow_logger.py  —  SecureFlow Data Acquisition Layer v2
==============================================================
Team A-6 | KLE Technological University | Sushil Chandaragi, Tech Lead

Architecture
------------
  PRODUCER  : keyboard.hook() Win32 OS-level callback
              → Does ZERO math. Only timestamps + queues raw events.
              → Modifier state (Shift, CapsLock) tracked HERE so the
                translated character is known at press-time, before
                any key-up event occurs.

  CONSUMER  : A daemon Thread reading from queue.Queue
              → Computes Dwell, Flight time
              → Applies Outlier Rule (Flight > 2.0 s → flagged, skipped)
              → Flushes to disk every FLUSH_INTERVAL rows (RAM safety)

Design Decisions
----------------
  1.  keyboard library (not pynput) for direct Win32 hook, bypassing
      the OS event-loop latency introduced by pynput's callback model.

  2.  time.perf_counter() for all timestamps. On Windows this wraps
      QueryPerformanceCounter (~100 ns resolution). On Linux it wraps
      clock_gettime(CLOCK_MONOTONIC_RAW) (~1 µs). Either way, far
      superior to time.time() for sub-millisecond timing.

  3.  Modifier "Drop & Distinguish":
      Physical Shift / Ctrl / Alt / CapsLock key events are CONSUMED by
      the hook but NEVER placed on the queue. Instead, their effect is
      applied to the NEXT regular key press: 'a' with Shift active → 'A'.
      This keeps the timing sequence linear (no phantom modifier rows).

  4.  Auto-Repeat Guard:
      OS auto-repeat fires repeated 'down' events when a key is held.
      We track active_keys = {key: press_time}. If a 'down' arrives for
      a key already in active_keys, it is silently dropped.

  5.  Outlier Rule:
      Flight Time > 2.0 s indicates a "thought pause" between bursts.
      These rows are written with a flag column  Outlier=True  and the
      Flight_Time column is set to NaN (not dropped). This way the row
      is preserved for audit but excluded from ML training via a simple
      filter in feature_extractor.py.

CSV Columns
-----------
  Key            – translated character (e.g. 'A', '!', 'space')
  Press_Time     – perf_counter() absolute value at key-down (s)
  Release_Time   – perf_counter() absolute value at key-up (s)
  Dwell_Time     – Release_Time - Press_Time (ms stored as float s)
  Flight_Time    – Press_Time[n] - Release_Time[n-1] (s), NaN if outlier
  Outlier        – True/False (Flight_Time > 2.0 s)
  User_Name      – session metadata
  Session_Type   – session metadata

Usage
-----
  python secureflow_logger.py
  → Prompts for User_Name and Session_Type
  → Records until ESC is pressed
  → Output: <User_Name>_<Session_Type>_<unix_ts>.csv
"""

import keyboard
import time
import queue
import threading
import csv
import os
import sys
import math

# ──────────────────────────────────────────────
#  CONFIGURATION
# ──────────────────────────────────────────────

FLUSH_INTERVAL = 50          # Rows buffered in RAM before disk write.
                             # 50 rows ≈ ~3–4 KB. Safe for multi-day sessions.

FLIGHT_OUTLIER_THRESHOLD = 2.0  # Seconds. Pauses longer than this are flagged.

OUTPUT_DIR = "."             # Where CSV files are saved. Change to your
                             # RAM-disk / tmpfs mount path for SecureFlow
                             # Layer 2 integration (e.g. /mnt/secureflow_vault)

CSV_HEADERS = [
    "Key", "Press_Time", "Release_Time",
    "Dwell_Time", "Flight_Time", "Outlier",
    "User_Name", "Session_Type"
]

# ──────────────────────────────────────────────
#  MODIFIER TRANSLATION TABLES
# ──────────────────────────────────────────────

# Keys to intercept as modifiers: consume their events, update state, queue nothing.
# 'ctrl', 'alt' etc. are included because we never want ctrl-key combos in timing data.
MODIFIER_KEYS = {
    'shift', 'left shift', 'right shift',
    'ctrl', 'left ctrl', 'right ctrl',
    'alt', 'left alt', 'right alt',
    'caps lock',
    'windows', 'cmd', 'super',
}

# Keys to silently drop entirely (navigation, function keys, etc.)
# Adjust this set if your session type (Code) needs F-key timing.
DROP_KEYS = {
    'f1', 'f2', 'f3', 'f4', 'f5', 'f6',
    'f7', 'f8', 'f9', 'f10', 'f11', 'f12',
    'insert', 'delete', 'home', 'end',
    'page up', 'page down',
    'up', 'down', 'left', 'right',
    'num lock', 'scroll lock', 'print screen', 'pause',
}

# Shift-key character mapping for US QWERTY.
# Extend this if you need Dvorak / AZERTY support.
SHIFT_MAP = {
    '`': '~',  '1': '!',  '2': '@',  '3': '#',
    '4': '$',  '5': '%',  '6': '^',  '7': '&',
    '8': '*',  '9': '(',  '0': ')',  '-': '_',
    '=': '+',  '[': '{',  ']': '}', '\\': '|',
    ';': ':',  "'": '"',  ',': '<',  '.': '>',
    '/': '?',
}

# ──────────────────────────────────────────────
#  SHARED MODIFIER STATE (Producer-owned)
# ──────────────────────────────────────────────
# Accessed only from the OS hook thread → no lock needed.
# (keyboard.hook guarantees single-threaded delivery on Windows.)

modifier_state = {
    'shift': False,       # True while any Shift key is physically held
    'caps_lock': False,   # Toggled on each CapsLock down-event
}

# ──────────────────────────────────────────────
#  THREAD-SAFE QUEUE  (Producer ↔ Consumer)
# ──────────────────────────────────────────────

event_queue = queue.Queue()


# ══════════════════════════════════════════════
#  PRODUCER  (OS Hook Thread)
# ══════════════════════════════════════════════

def translate_key(raw_name: str) -> str | None:
    """
    Convert a raw keyboard.event.name to the character we actually want to log.

    Returns:
        str  – the translated character to log
        None – if this event should be silently dropped

    Why translate here (in the producer) and not the consumer?
    Because modifier state is ephemeral: by the time the consumer
    processes a queued event, the Shift key may already be released.
    We must capture the effect of the modifier at the exact moment of
    the key-down event.
    """
    key = raw_name.lower()

    # ── 1. Modifier keys: update state, produce nothing ──────────────
    if key in MODIFIER_KEYS:
        # CapsLock gets toggled; other modifiers are tracked by up/down.
        # (up/down tracking happens in producer_hook, not here.)
        return None  # Signal to caller: this is a modifier event

    # ── 2. Drop keys: silently ignore ───────────────────────────────
    if key in DROP_KEYS:
        return None

    # ── 3. Single alphabetic character ──────────────────────────────
    if len(raw_name) == 1 and raw_name.isalpha():
        # XOR: uppercase when EITHER shift OR caps_lock is active, not both.
        if modifier_state['shift'] ^ modifier_state['caps_lock']:
            return raw_name.upper()
        return raw_name.lower()

    # ── 4. Digit / punctuation with Shift ───────────────────────────
    if modifier_state['shift'] and raw_name in SHIFT_MAP:
        return SHIFT_MAP[raw_name]

    # ── 5. Special named keys we DO want to keep ────────────────────
    KEEP_NAMED = {
        'space': 'space', 'enter': 'enter', 'tab': 'tab',
        'backspace': 'backspace', 'escape': 'escape',
    }
    if key in KEEP_NAMED:
        return KEEP_NAMED[key]

    # ── 6. Single non-alpha character (digit, punctuation unshifted) ─
    if len(raw_name) == 1:
        return raw_name

    # ── 7. Anything else (unknown named key) → drop ─────────────────
    return None


def producer_hook(event):
    """
    PRODUCER — runs in the OS Win32 hook thread.

    CONTRACT: Must return in < 1 ms or risk breaking the hook chain.
    Rule: NO math, NO disk I/O. Timestamp → queue → return.

    Modifier bookkeeping is the ONLY exception to the "no logic" rule,
    because modifier state must be synchronous with each key event.
    """
    timestamp = time.perf_counter()   # Capture hardware time FIRST, unconditionally.
    raw_name = event.name

    if raw_name is None:
        return  # Malformed event from some virtual keyboards; skip.

    key_lower = raw_name.lower()

    # ── Modifier state update (synchronous, no queue) ────────────────
    if key_lower in ('shift', 'left shift', 'right shift'):
        modifier_state['shift'] = (event.event_type == 'down')
        return  # Do not queue modifier events

    if key_lower == 'caps lock' and event.event_type == 'down':
        modifier_state['caps_lock'] = not modifier_state['caps_lock']
        return  # Toggle on down-event only (standard OS behaviour)

    if key_lower in MODIFIER_KEYS:
        return  # Ctrl, Alt, etc. — consume silently

    # ── Translate key at press-time ──────────────────────────────────
    if event.event_type == 'down':
        translated = translate_key(raw_name)
        if translated is None:
            return  # DROP_KEYS or untranslatable
        event_queue.put(('down', translated, timestamp))

    elif event.event_type == 'up':
        # For 'up' events we need the translated name to match the 'down' entry
        # in active_keys. Use the same translation function.
        translated = translate_key(raw_name)
        if translated is None:
            return
        event_queue.put(('up', translated, timestamp))


# ══════════════════════════════════════════════
#  CONSUMER  (Background Daemon Thread)
# ══════════════════════════════════════════════

def consumer_thread(filename: str, user_name: str, session_type: str):
    """
    CONSUMER — reads from event_queue, computes timing features, writes CSV.

    State Machine per-key:
        active_keys[key] = (press_time, flight_time)
            ↑ populated on 'down'
            ↓ popped on 'up', row written to buffer

    Disk Write Strategy:
        We keep a list buffer. When len(buffer) >= FLUSH_INTERVAL,
        we open the file in append mode, write all rows, clear buffer.
        This avoids both RAM bloat (never hold more than FLUSH_INTERVAL rows)
        and thrashing (not one syscall per keystroke).

        Tradeoff: if the process is killed mid-buffer, the last
        < FLUSH_INTERVAL rows are lost. For a 4-day session at ~50 WPM,
        you type ~5 keys/second, so max loss ≈ 10 seconds of data.
        Acceptable for a research dataset. Reduce FLUSH_INTERVAL to 10
        if you want tighter safety; increase to 200 for pure speed.
    """
    active_keys = {}       # {translated_key: (press_time, flight_time)}
    last_release_time = None
    buffer = []            # In-RAM accumulation before flush

    # Initialise the CSV file with headers (overwrite if exists)
    with open(filename, 'w', newline='', encoding='utf-8') as f:
        csv.writer(f).writerow(CSV_HEADERS)

    print(f"  [Consumer] Initialised CSV: {filename}")

    while True:
        item = event_queue.get()

        # ── Sentinel: graceful shutdown ──────────────────────────────
        if item is None:
            if buffer:
                _flush_buffer(filename, buffer)
                print(f"  [Consumer] Final flush: {len(buffer)} rows written.")
            event_queue.task_done()
            break

        event_type, key, timestamp = item

        # ── KEY DOWN ─────────────────────────────────────────────────
        if event_type == 'down':
            if key not in active_keys:
                # Auto-repeat guard: only process if key is NOT already tracked.
                # Compute flight time NOW (before this key changes last_release_time).
                if last_release_time is not None:
                    flight_time = timestamp - last_release_time
                else:
                    flight_time = 0.0   # First key of the session has no prior release.

                active_keys[key] = (timestamp, flight_time)
            # If key IS in active_keys → held-key auto-repeat → silently ignore.

        # ── KEY UP ───────────────────────────────────────────────────
        elif event_type == 'up':
            if key in active_keys:
                press_time, flight_time = active_keys.pop(key)
                dwell_time = timestamp - press_time
                last_release_time = timestamp

                # ── Outlier Rule ─────────────────────────────────────
                # Flight times > 2.0 s indicate a deliberate pause.
                # We still record the row for audit, but set Flight_Time to NaN
                # and flag Outlier=True. The feature_extractor will skip these.
                is_outlier = flight_time > FLIGHT_OUTLIER_THRESHOLD
                logged_flight = math.nan if is_outlier else flight_time

                row = [
                    key,
                    press_time,
                    timestamp,           # Release_Time
                    dwell_time,
                    logged_flight,
                    is_outlier,
                    user_name,
                    session_type,
                ]
                buffer.append(row)

                # ── Flush to disk if threshold met ───────────────────
                if len(buffer) >= FLUSH_INTERVAL:
                    _flush_buffer(filename, buffer)
                    buffer.clear()

        event_queue.task_done()


def _flush_buffer(filename: str, buffer: list):
    """Append buffered rows to the CSV. Opens in 'a' (append) mode."""
    with open(filename, 'a', newline='', encoding='utf-8') as f:
        csv.writer(f).writerows(buffer)


# ══════════════════════════════════════════════
#  SESSION METADATA UI
# ══════════════════════════════════════════════

def prompt_session_metadata() -> tuple[str, str]:
    """
    Simple terminal UI to collect session metadata before recording starts.
    These values are baked into the CSV filename AND stored in every row,
    making the CSV self-describing when files are later mixed in a dataset.
    """
    print("=" * 55)
    print("  SecureFlow Data Acquisition — Session Setup")
    print("=" * 55)

    while True:
        user_name = input("  Enter User Name (e.g. Sushil, Ankit, Reesha and Shruti): ").strip()
        if user_name and user_name.replace('_', '').isalnum():
            break
        print("  [!] User name must be alphanumeric (underscores OK). Try again.")

    print()
    print("  Session Types:")
    print("    1 → Prose   (natural typing, emails, notes)")
    print("    2 → Code    (Python/C, identifiers, symbols)")
    print("    3 → Mixed   (both)")

    session_map = {'1': 'Prose', '2': 'Code', '3': 'Mixed'}
    while True:
        choice = input("  Select Session Type [1/2/3]: ").strip()
        if choice in session_map:
            session_type = session_map[choice]
            break
        # Also accept the type name directly
        if choice.capitalize() in session_map.values():
            session_type = choice.capitalize()
            break
        print("  [!] Enter 1, 2, or 3.")

    return user_name, session_type


def build_filename(user_name: str, session_type: str) -> str:
    """
    Constructs: <OutputDir>/<User_Name>_<Session_Type>_<unix_timestamp>.csv
    Example   : ./Sushil_Prose_1776970393.csv

    Using Unix timestamp (not perf_counter) in the filename because it's
    human-readable and absolute — perf_counter is relative to system boot.
    """
    ts = int(time.time())
    filename = f"{user_name}_{session_type}_{ts}.csv"
    return os.path.join(OUTPUT_DIR, filename)


# ══════════════════════════════════════════════
#  MAIN ENTRY POINT
# ══════════════════════════════════════════════

if __name__ == "__main__":

    # ── 0. Elevate hint (Windows requires admin for global hooks) ────
    if sys.platform == "win32":
        try:
            import ctypes
            if not ctypes.windll.shell32.IsUserAnAdmin():
                print("[WARN] Not running as Administrator.")
                print("       If keyboard hook fails, re-run in an elevated terminal.")
        except Exception:
            pass  # Non-critical; just a helpful hint.

    # ── 1. Session metadata collection ──────────────────────────────
    user_name, session_type = prompt_session_metadata()
    filename = build_filename(user_name, session_type)

    print()
    print(f"  Output file : {filename}")
    print(f"  Flush every : {FLUSH_INTERVAL} keystrokes")
    print(f"  Outlier gate: Flight_Time > {FLIGHT_OUTLIER_THRESHOLD}s → flagged NaN")
    print()

    # ── 2. Start Consumer daemon thread ─────────────────────────────
    consumer = threading.Thread(
        target=consumer_thread,
        args=(filename, user_name, session_type),
        daemon=True,   # Dies automatically if main thread dies (safety net)
    )
    consumer.start()

    # ── 3. Attach global Win32 hook ──────────────────────────────────
    keyboard.hook(producer_hook)

    print("[REC] Recording keystrokes...")
    print("      Type naturally. Press ESC to stop and save.\n")

    # ── 4. Block main thread on ESC ──────────────────────────────────
    keyboard.wait('esc')

    # ── 5. Graceful shutdown ─────────────────────────────────────────
    print("\n[...] ESC detected. Flushing remaining data...")
    keyboard.unhook_all()

    # Signal consumer to drain queue and exit
    event_queue.put(None)   # Sentinel value

    # Wait for consumer to finish final disk write (timeout=10 s safety)
    consumer.join(timeout=10)

    if consumer.is_alive():
        print("[WARN] Consumer thread did not finish within timeout.")
        print(f"       Check {filename} — last rows may be missing.")
    else:
        print(f"\n[DONE] Session saved → {filename}")
        print(f"       Run  python feature_extractor.py  to build your User Profile.")
