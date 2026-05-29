import os
import sys
from pathlib import Path
from dotenv import load_dotenv

# Load env variables
base_dir = Path(__file__).resolve().parent
load_dotenv(dotenv_path=base_dir / ".env")

from crypto_engine import CryptoEngine
import boto3

def main():
    print("=" * 60)
    print("SecureFlow Fresh Encryption Test")
    print("=" * 60)

    # 1. Create a fresh test file
    test_file = base_dir / "fresh_test.txt"
    plaintext = b"SecureFlow Zero-Knowledge Verification: Cross-platform parity achieved successfully!"
    test_file.write_bytes(plaintext)
    print(f"[+] Created test file: {test_file}")

    # 2. Initialize CryptoEngine
    engine = CryptoEngine()

    # 3. Perform simulated hardware handshake
    print("[*] Performing simulated hardware handshake...")
    success = engine.hardware_handshake(com_port="MOCK")
    print(f"[+] Handshake status: {success}")
    print(f"    Handshake Mode  : {engine._handshake_mode}")
    print(f"    Handshake Nonce : {engine._handshake_nonce.hex() if engine._handshake_nonce else 'None'}")

    # 4. Encrypt the file
    print("[*] Encrypting test file...")
    enc_path = engine.encrypt_file(test_file)
    print(f"[+] Encrypted file saved to: {enc_path}")

    # 5. Read the encrypted blob to inspect
    blob = enc_path.read_bytes()
    print(f"    Blob Size   : {len(blob)} bytes")
    print(f"    Header      : {blob[:4]!r}")
    print(f"    Mode Byte   : {blob[4:5]!r}")
    print(f"    HS Nonce    : {blob[5:37].hex()}")
    print(f"    File Nonce  : {blob[37:49].hex()}")

    # 6. Upload to AWS S3
    bucket = os.environ.get('S3_BUCKET_NAME')
    region = os.environ.get('AWS_DEFAULT_REGION', 'ap-south-1')
    key_id = os.environ.get('AWS_ACCESS_KEY_ID')
    key_sec = os.environ.get('AWS_SECRET_ACCESS_KEY')

    if not bucket or not key_id or not key_sec:
        print("[-] AWS S3 credentials or bucket name not fully configured in .env!")
        return

    print(f"[*] Uploading encrypted file to S3 bucket '{bucket}'...")
    try:
        s3 = boto3.client(
            's3',
            region_name=region,
            aws_access_key_id=key_id,
            aws_secret_access_key=key_sec
        )
        s3_key = enc_path.name
        s3.upload_file(str(enc_path), bucket, s3_key)
        print(f"[+] Successfully uploaded {s3_key} to S3!")
    except Exception as e:
        print(f"[-] S3 upload failed: {e}")
        return

    print("\n" + "=" * 60)
    print("Now run 'python test_decrypt.py' or check mobile app sync!")
    print("=" * 60)

if __name__ == "__main__":
    main()
