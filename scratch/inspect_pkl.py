import joblib
from pathlib import Path

pkl_path = Path("biometric_model.pkl")
if pkl_path.exists():
    try:
        data = joblib.load(pkl_path)
        print("PKL Type:", type(data))
        if isinstance(data, dict):
            print("Keys:", list(data.keys()))
            for k in ["window_size", "features", "threshold_score"]:
                if k in data:
                    print(f"{k}: {data[k]}")
            if "scaler" in data:
                print("Scaler:", type(data["scaler"]))
            if "model" in data:
                model = data["model"]
                print("Model Type:", type(model))
                print("Model n_features_in_:", getattr(model, "n_features_in_", "unknown"))
        else:
            print("Direct Model Type:", type(data))
            print("Model n_features_in_:", getattr(data, "n_features_in_", "unknown"))
    except Exception as exc:
        print("Error loading PKL:", exc)
else:
    print("PKL not found.")
