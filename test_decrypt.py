# Quick diagnostic: Download and decrypt a file from S3, verify the blob format.
# Run from the SecureFlowV1 directory.
# Usage: python test_decrypt.py
import sys, os
sys.path.insert(0, os.path.dirname(__file__))

from dotenv import load_dotenv
load_dotenv()

import boto3
from crypto_engine import CryptoEngine

# ── Config ──────────────────────────────────────────────────────────────────
BUCKET   = os.environ['S3_BUCKET_NAME']
REGION   = os.environ['AWS_DEFAULT_REGION']
KEY_ID   = os.environ['AWS_ACCESS_KEY_ID']
KEY_SEC  = os.environ['AWS_SECRET_ACCESS_KEY']

SECRET_FILE = os.path.join(os.path.dirname(__file__), 'mock_hardware_secret.txt')

print("=" * 60)
print("SecureFlow Decrypt Diagnostic")
print("=" * 60)

# 1. Show secret
with open(SECRET_FILE, 'rb') as f:
    raw = f.read()
stripped = raw.strip()
print(f"\n[1] mock_hardware_secret.txt")
print(f"    raw bytes  : {raw!r}")
print(f"    stripped   : {stripped!r}")
print(f"    length     : {len(stripped)} bytes")

# 2. List S3 objects
print(f"\n[2] S3 inventory - bucket={BUCKET}")
s3 = boto3.client('s3', region_name=REGION,
                  aws_access_key_id=KEY_ID,
                  aws_secret_access_key=KEY_SEC)
try:
    resp = s3.list_objects_v2(Bucket=BUCKET)
    objs = resp.get('Contents', [])
    enc_files = [o for o in objs if o['Key'].endswith('.enc')]
    if not enc_files:
        print("    [WARNING] No .enc files found in bucket!")
    else:
        for o in enc_files:
            print(f"    [{o['Size']:>8}B]  {o['Key']}")
except Exception as e:
    print(f"    ERROR listing S3: {e}")
    sys.exit(1)

if not enc_files:
    sys.exit(0)

# 3. Download + inspect and decrypt all files
for target in enc_files:
    print(f"\n[3] Downloading: {target['Key']}")
    obj = s3.get_object(Bucket=BUCKET, Key=target['Key'])
    blob = obj['Body'].read()
    print(f"    Total size : {len(blob)} bytes")
    print(f"    Header     : {blob[:4]!r}")
    if len(blob) > 4:
        print(f"    Mode byte  : {blob[4:5]!r}  ({'MOCK' if blob[4:5] == b'M' else 'HARDWARE' if blob[4:5] == b'H' else 'UNKNOWN'})")
    if len(blob) > 5:
        print(f"    HS nonce   : {blob[5:37].hex()}")
    if len(blob) > 37:
        print(f"    File nonce : {blob[37:49].hex()}")
        print(f"    Ciphertext : {len(blob[49:])} bytes (incl. 16B GCM tag)")

    # 4. Decrypt with mock handshake
    print(f"[*] Attempting decryption on {target['Key']}...")
    engine = CryptoEngine()
    engine.mock_handshake()
    try:
        plaintext = engine.decrypt_blob(blob, com_port="MOCK")
        print(f"    [SUCCESS] Decrypted {len(plaintext)} bytes")
        header4 = plaintext[:4]
        if header4 == b'%PDF':
            print(f"    File type  : PDF")
        else:
            try:
                preview = plaintext[:200].decode('utf-8')
                print(f"    File type  : TEXT")
                print(f"    Preview    : {preview[:80]!r}")
            except:
                print(f"    File type  : BINARY (first 4 bytes: {header4.hex()})")
    except Exception as e:
        print(f"    [FAILED] {e}")

print("\n" + "=" * 60)
print("Diagnostic Complete.")
print("=" * 60)


