"""
validate_global_agent.py — Empirical Verification Suite for EDR Continuous Auth Agent
===================================================================================
Loads the real trained 10-feature biometric model and simulates sequences of
genuine and anomalous keystroke timings to verify interdiction lock triggers.
"""

import time
import math
import numpy as np
import joblib
from pathlib import Path

# Load agent processing class logic
from global_agent import GlobalEDRAgent

def test_validation():
    print("=" * 60)
    print(" EDR Continuous Authentication Agent — Validation Check")
    print("=" * 60)

    # Initialize agent
    agent = GlobalEDRAgent()
    
    if agent.model_pipeline is None:
        print("[FAIL] biometric_model.pkl not found! Place the model to run validation.")
        return

    # 1. Simulate Genuine Owner Typing Cadence
    # Genuine timing characteristics from Sushil's Prose dataset:
    # Average Dwell: ~0.08 - 0.12s
    # Average Flight: ~0.08 - 0.15s
    print("\n[Phase 1] Simulating Genuine Owner Typing Cadence...")
    
    # Reset feature buffer
    agent.feature_buffer = []
    agent.anomaly_streak = 0

    # Feed 15 clean, consistent timing entries
    for i in range(15):
        dwell = np.random.normal(0.095, 0.01) # Mean 95ms, low standard dev
        flight = np.random.normal(0.110, 0.015) # Mean 110ms
        
        # Feed into timing processing buffer
        agent.feature_buffer.append([dwell, flight])
        
        # Only evaluate if we have reached window length W (8)
        if len(agent.feature_buffer) >= 8:
            agent.evaluate_ml_vector(dwell, flight)

    print(f"--> Phase 1 Completed. Final Anomaly Streak: {agent.anomaly_streak}/{3}")
    owner_success = (agent.anomaly_streak == 0)
    if owner_success:
        print("[PASS] EDR correctly verified owner cadence with zero false locks.")
    else:
        print("[FAIL] EDR flagged genuine operator cadence as anomalous.")

    # 2. Simulate Intruder Typing Cadence
    # Intruder typing characteristics (irregular rhythm, slow thought pauses, typing hesitancy):
    # Dwell: 0.18 - 0.25s
    # Flight: 0.40 - 0.85s
    print("\n[Phase 2] Simulating Intruder Typing Cadence (Irregular/Anomalous)...")
    
    # We maintain the buffer but begin feeding slow, anomalous timings
    intruder_detected = False
    
    # Override ctypes lock screen call during automated validation to avoid locking current developer session
    def mock_lockdown():
        nonlocal intruder_detected
        intruder_detected = True
        print("[MOCK INTERDICTION] Triggering System LockWorkStation Call! [OK]")

    agent.execute_lockdown = mock_lockdown

    for i in range(10):
        dwell = np.random.normal(0.220, 0.03) # Slow, hesitant dwell
        flight = np.random.normal(0.650, 0.12) # Very hesitant, variable flight
        
        agent.feature_buffer.append([dwell, flight])
        if len(agent.feature_buffer) >= 8:
            agent.evaluate_ml_vector(dwell, flight)
            if intruder_detected:
                break

    print(f"--> Phase 2 Completed. Intruder Lock Triggered: {intruder_detected}")
    if intruder_detected:
        print("[PASS] EDR correctly intercepted threat and triggered workstation interdiction.")
    else:
        print("[FAIL] EDR allowed anomalous intruder timing signature to bypass detection.")

    print("\n" + "=" * 60)
    print(" SUMMARY OF EMPIRICAL VERIFICATION RESULTS")
    print(f" Owner Cadence Verification : {'PASS' if owner_success else 'FAIL'}")
    print(f" Intruder Cadence Blocked  : {'PASS' if intruder_detected else 'FAIL'}")
    print("=" * 60)

if __name__ == "__main__":
    test_validation()
