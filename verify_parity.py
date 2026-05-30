import sys
from pathlib import Path
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.hkdf import HKDF

def main():
    secret_path = Path("mock_hardware_secret.txt")
    if not secret_path.is_file():
        print("ERROR: mock_hardware_secret.txt not found")
        sys.exit(1)
        
    secret_bytes = secret_path.read_bytes().strip()
    print(f"secret_bytes repr: {repr(secret_bytes)}")
    
    vault_dir = Path("SecureFlow_Vault")
    enc_files = list(vault_dir.glob("*.enc"))
    if not enc_files:
        print("ERROR: No .enc files found in SecureFlow_Vault")
        sys.exit(1)
        
    for enc_file in enc_files:
        print(f"\nAnalyzing file: {enc_file.name}")
        blob = enc_file.read_bytes()
        
        if len(blob) < 4:
            print("  ERROR: File is too small")
            continue
            
        header = blob[:4]
        if header != b"SFV3":
            print(f"  ERROR: Unsupported header {repr(header)}")
            continue
            
        mode = blob[4:5]
        print(f"  Mode: {repr(mode)}")
        
        handshake_nonce = blob[5:37]
        file_nonce = blob[37:49]
        ciphertext = blob[49:]
        
        print(f"  handshake_nonce hex: {handshake_nonce.hex()}")
        print(f"  file_nonce hex: {file_nonce.hex()}")
        
        # Derive key depending on mode
        if mode == b"M":
            hkdf = HKDF(
                algorithm=hashes.SHA256(),
                length=32,
                salt=handshake_nonce,
                info=b"SecureFlow session key",
            )
            derived_key = hkdf.derive(secret_bytes)
        elif mode == b"H":
            # Hardware mode
            import hmac
            import hashlib
            hmac_resp = hmac.new(secret_bytes, handshake_nonce, hashlib.sha256).digest()
            ikm = hmac_resp + handshake_nonce
            hkdf = HKDF(
                algorithm=hashes.SHA256(),
                length=32,
                salt=None,
                info=b"SecureFlow session key",
            )
            derived_key = hkdf.derive(ikm)
        else:
            print(f"  ERROR: Unknown mode {repr(mode)}")
            continue
            
        print(f"  derived_key hex: {derived_key.hex()}")
        
        try:
            aesgcm = AESGCM(derived_key)
            plaintext = aesgcm.decrypt(file_nonce, ciphertext, None)
            print("  decryption result: OK")
            print(f"  first 100 bytes of plaintext: {repr(plaintext[:100])}")
        except Exception as e:
            print(f"  decryption result: FAILED ({e})")

if __name__ == "__main__":
    main()
