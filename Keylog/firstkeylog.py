import keyboard
import time
import queue
import threading
import csv

# --- CONFIGURATION ---
FLUSH_INTERVAL = 50  # Number of keys to hold in RAM before writing to disk
FILENAME = f"SecureFlow_Dataset_{int(time.time())}.csv"
HEADERS = ["Key", "Press_Time", "Release_Time", "Dwell_Time", "Flight_Time"]

# The Thread-Safe Queue acting as the buffer between Producer and Consumer
event_queue = queue.Queue()

def producer_hook(event):
    """
    PRODUCER: Runs in the OS Hook thread.
    Must be extremely fast. Captures event and immediately queues it.
    """
    # Capture hardware timestamp instantly
    timestamp = time.perf_counter()
    event_queue.put((event.event_type, event.name, timestamp))

def consumer_thread(filename):
    """
    CONSUMER: Background thread handling math and disk I/O.
    """
    active_keys = {}  # Tracks keys currently held down: {key: (press_time, flight_time)}
    last_release_time = None
    buffer = []

    # Initialize CSV with headers
    with open(filename, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(HEADERS)

    while True:
        item = event_queue.get()
        
        # Sentinel value check to gracefully shut down the thread
        if item is None: 
            if buffer:  # Flush any remaining data
                with open(filename, 'a', newline='') as f:
                    csv.writer(f).writerows(buffer)
            break

        event_type, key, timestamp = item

        if event_type == 'down':
            # AUTO-REPEAT HANDLING: Only process if key isn't already held down
            if key not in active_keys:
                flight_time = (timestamp - last_release_time) if last_release_time else 0.0
                active_keys[key] = (timestamp, flight_time)

        elif event_type == 'up':
            # Calculate Dwell and finalize record
            if key in active_keys:
                press_time, flight_time = active_keys.pop(key)
                dwell_time = timestamp - press_time
                last_release_time = timestamp

                buffer.append([key, press_time, timestamp, dwell_time, flight_time])

                # CONTINUOUS DISK STREAMING: Flush buffer when threshold is met
                if len(buffer) >= FLUSH_INTERVAL:
                    with open(filename, 'a', newline='') as f:
                        csv.writer(f).writerows(buffer)
                    buffer.clear()
        
        event_queue.task_done()

if __name__ == "__main__":
    print(f"Starting SecureFlow Data Logger...")
    print(f"Output file: {FILENAME}")
    
    # 1. Start Consumer Thread
    consumer = threading.Thread(target=consumer_thread, args=(FILENAME,), daemon=True)
    consumer.start()

    # 2. Start Producer Hook (Global Win32 Hook)
    keyboard.hook(producer_hook)

    print("\n[REC] Recording keystrokes... Press 'ESC' to stop safely and flush data.")
    
    # 3. Block main thread until ESC is pressed
    keyboard.wait('esc')
    
    # 4. Cleanup and Shutdown sequence
    keyboard.unhook_all()
    event_queue.put(None)  # Send sentinel to stop consumer
    consumer.join()        # Wait for final disk flush to complete
    
    print(f"\n[DONE] Data successfully saved to {FILENAME}")