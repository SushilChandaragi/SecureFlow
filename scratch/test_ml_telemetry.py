import time
import math
import unittest
from pathlib import Path
from crypto_engine import CryptoEngine
from vault_gui import VaultGUI, COLORS
import tkinter as tk

class DummyEvent:
    def __init__(self, keycode, widget=None):
        self.keycode = keycode
        self.widget = widget

class TestMLTelemetry(unittest.TestCase):
    def setUp(self):
        # Override _init_cloud_bg to prevent background threads
        VaultGUI._init_cloud_bg = lambda s: None
        # Mock _update_totp to avoid loop scheduling
        VaultGUI._update_totp = lambda s: None
        self.engine = CryptoEngine()
        self.app = VaultGUI(self.engine)
        self.app.withdraw()

    def tearDown(self):
        # Cancel all Tkinter after tasks to prevent invalid command outputs
        try:
            for after_id in self.app.tk.call('after', 'info'):
                self.app.after_cancel(after_id)
        except Exception:
            pass
        try:
            self.app.destroy()
        except Exception:
            pass

    def test_focus_and_key_capture(self):
        # 1. Start in focused state
        self.app._handle_ml_focus_in(DummyEvent(None, self.app))
        self.assertTrue(self.app._ml_window_active)
        self.assertIn("Active", self.app._ml_session_label.cget("text"))

        # 2. Simulate key press and release
        e_press = DummyEvent(65) # Key 'A'
        self.app._on_ml_key_press(e_press)
        self.assertIn(65, self.app._ml_active_keys)
        
        # Wait slightly to simulate dwell time
        time.sleep(0.05)
        
        e_release = DummyEvent(65)
        self.app._on_ml_key_release(e_release)
        self.assertNotIn(65, self.app._ml_active_keys)
        
        # Verify feature buffer got the vector
        self.assertEqual(len(self.app._ml_feature_buffer), 1)
        vector = self.app._ml_feature_buffer[0]
        self.assertGreater(vector[0], 0.0) # Dwell > 0
        self.assertEqual(vector[1], 0.0) # Flight is 0.0 for first key

        # 3. Verify bubbling focus events DO NOT clear the session
        # Simulate FocusOut from a child entry widget (event.widget != self.app)
        child_widget = tk.Frame(self.app)
        self.app._handle_ml_focus_out(DummyEvent(None, child_widget))
        self.assertTrue(self.app._ml_window_active, "Bubbling focus out should not deactivate session")

        # 4. Verify true focus loss deactivates session
        self.app._handle_ml_focus_out(DummyEvent(None, self.app))
        # Wait for the verify_ml_focus_loss after delay
        self.app.update()
        time.sleep(0.2)
        self.app.update()
        # Since self.app.focus_get() is indeed None/withdrawn, it will verify focus loss
        self.assertFalse(self.app._ml_window_active, "True focus loss should deactivate session")
        self.assertEqual(len(self.app._ml_active_keys), 0)
        self.assertIsNone(self.app._ml_last_release_time)

    def test_calibration_mode_label_updates(self):
        # Ensure model is not present (or mock it to none)
        self.app._ml_local_model_ready = False
        self.app._ml_local_model = None

        self.app._handle_ml_focus_in(DummyEvent(None, self.app))
        
        # Send keypress and release to trigger _evaluate_ml_vector
        self.app._on_ml_key_press(DummyEvent(66))
        time.sleep(0.05)
        self.app._on_ml_key_release(DummyEvent(66))
        
        # The Classifier Status Box (self._ml_status_label) should update with Live Timing
        status_text = self.app._ml_status_label.cget("text")
        self.assertIn("Calibration Mode", status_text)
        self.assertIn("Dwell:", status_text)

if __name__ == '__main__':
    unittest.main()
