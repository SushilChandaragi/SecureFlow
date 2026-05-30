import os
import sys
from pathlib import Path

# Add parent dir to path for imports
sys.path.append(str(Path(__file__).parent.parent))
from crypto_engine import CryptoEngine, CryptoEngineError

def check_local():
    vault_dir = Path(__file__).parent.parent / "SecureFlow_Vault"
    print("Listing files in:", vault_dir)
    
    engine = CryptoEngine()
    
    for local_path in vault_dir.glob("*.enc"):
        print(f"\nFile: {local_path.name} ({local_path.stat().st_size} bytes)")
        
        # Read header and metadata
        blob = local_path.read_bytes()
        header = blob[:4]
        mode = chr(blob[4]) if len(blob) > 4 else "N/A"
        print(f"Header: {header}, Mode: {mode}")
        
        # Try to decrypt using "MOCK" com port
        try:
            engine.hardware_handshake("MOCK")
            plain = engine.decrypt_blob(blob, com_port="MOCK")
            print("Successfully decrypted using hardware_handshake with MOCK port! Content sample:")
            print(plain[:100])
            continue
        except Exception as e:
            print("Decryption via hardware MOCK failed:", e)
            
        # Try to decrypt using mock mode directly (mode M)
        try:
            # We manually load mock secret and decrypt
            secret = Path(__file__).parent.parent / "mock_hardware_secret.txt"
            secret_bytes = secret.read_bytes().strip()
            # Try to derive key using mock mode logic
            # Let's see if we can manually derive the key
            import secrets
            from cryptography.hazmat.primitives.ciphers.aead import AESGCM
            
            # Extract nonces
            hs_nonce = blob[5:37]
            file_nonce = blob[37:49]
            ct = blob[49:]
            
            # Mock mode derivation
            derived_key = engine._derive_key(secret_bytes, hs_nonce)
            aesgcm = AESGCM(bytes(derived_key))
            plain = aesgcm.decrypt(file_nonce, ct, None)
            print("Successfully decrypted using MOCK mode manually! Content sample:")
            print(plain[:100])
        except Exception as e2:
            print("Decryption via mock manual failed:", e2)

if __name__ == "__main__":
    check_local()
