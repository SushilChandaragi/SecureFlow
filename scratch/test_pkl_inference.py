import math
import joblib
import pandas as pd
import numpy as np
from pathlib import Path

# 1. Load pipeline
pkl_path = Path("biometric_model.pkl")
pipeline = joblib.load(pkl_path)
model = pipeline["model"]
scaler = pipeline["scaler"]
W = pipeline["window_size"]
features = pipeline["features"]
threshold = pipeline["threshold_score"]

print("Loaded pipeline successfully.")
print(f"Features: {features}")
print(f"Threshold: {threshold}")

# 2. Load CSV
df = pd.read_csv("Sushil_Prose_1777010381.csv")
# Filter clean vectors
clean_df = df[df["Flight_Time"].notna() & (df["Outlier"] == False)].copy()
print(f"Clean samples in CSV: {len(clean_df)}")

# Simulate buffer
buffer = []
anomalies = 0
verified = 0

for idx, row in clean_df.iterrows():
    dwell = float(row["Dwell_Time"])
    flight = float(row["Flight_Time"])
    buffer.append([dwell, flight])
    
    if len(buffer) < W:
        continue
        
    # Extract last W
    window = buffer[-W:]
    dwells = [v[0] for v in window]
    flights = [v[1] for v in window]
    
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
    
    # Scale and infer
    scaled_vec = scaler.transform(vec)
    score = model.decision_function(scaled_vec)[0]
    
    is_verified = score >= threshold
    if is_verified:
        verified += 1
    else:
        anomalies += 1

print(f"Inference results on owner's own data:")
print(f"  Verified windows: {verified}")
print(f"  Anomaly windows flagged: {anomalies}")
print(f"  Owner acceptance rate: {verified / (verified + anomalies) * 100:.2f}%")
