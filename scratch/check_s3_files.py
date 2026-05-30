import os
import sys
from pathlib import Path
import boto3
from dotenv import load_dotenv

# Load env
load_dotenv(Path(__file__).parent.parent / ".env")

# Add parent dir to path for imports
sys.path.append(str(Path(__file__).parent.parent))
from crypto_engine import CryptoEngine, CryptoEngineError

def check_s3():
    s3 = boto3.client(
        "s3",
        aws_access_key_id=os.environ.get("AWS_ACCESS_KEY_ID"),
        aws_secret_access_key=os.environ.get("AWS_SECRET_ACCESS_KEY"),
        region_name=os.environ.get("AWS_DEFAULT_REGION", "ap-south-1")
    )
    bucket = os.environ.get("S3_BUCKET_NAME", "secureflow-sushil")
    
    print("Listing objects in bucket:", bucket)
    resp = s3.list_objects_v2(Bucket=bucket)
    if "Contents" not in resp:
        print("Bucket is empty!")
        return
        
    engine = CryptoEngine()
    # Initialize engine in mock hardware mode
    engine.hardware_handshake("MOCK")
    
    for obj in resp["Contents"]:
        key = obj["Key"]
        print(f"\nFound object: {key} ({obj['Size']} bytes)")
        
        # Download
        local_path = Path(__file__).parent / key
        local_path.parent.mkdir(parents=True, exist_ok=True)
        s3.download_file(bucket, key, str(local_path))
        
        # Read header and metadata
        blob = local_path.read_bytes()
        header = blob[:4]
        mode = chr(blob[4]) if len(blob) > 4 else "N/A"
        print(f"Header: {header}, Mode: {mode}")
        
        # Try to decrypt
        try:
            plain = engine.decrypt_blob(blob, com_port="MOCK")
            print("Successfully decrypted! Content sample:")
            print(plain[:100])
        except Exception as e:
            print("Decryption failed:", e)
            
        # Clean up
        if local_path.exists():
            local_path.unlink()

if __name__ == "__main__":
    check_s3()
