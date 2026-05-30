from pathlib import Path
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from cryptography.hazmat.primitives import hashes

def try_alternative():
    secret_path = Path(__file__).parent.parent / "mock_hardware_secret.txt"
    secret = secret_path.read_bytes().strip()
    
    ansible_path = Path(__file__).parent.parent / "SecureFlow_Vault" / "Ansible.pdf.enc"
    blob = ansible_path.read_bytes()
    
    hs_nonce = blob[5:37]
    file_nonce = blob[37:49]
    ct = blob[49:]
    
    # Try direct concatenation key derivation (NFC mode equivalent using mock secret)
    # ikm = secret + hs_nonce
    # If the secret is 49 bytes, let's pad it or truncate it to 32 bytes?
    # Or just use the whole 49 bytes?
    for test_secret in [secret, secret[:32], secret + b"\x00"*(64-len(secret))]:
        try:
            # Let's try direct concatenation with HKDF-SHA256, salt=None
            ikm = test_secret + hs_nonce
            hkdf = HKDF(
                algorithm=hashes.SHA256(),
                length=32,
                salt=None,
                info=b"SecureFlow session key",
            )
            derived_key = hkdf.derive(ikm)
            aesgcm = AESGCM(derived_key)
            plain = aesgcm.decrypt(file_nonce, ct, None)
            print("SUCCESS with direct concatenation! Plaintext starts with:", plain[:100])
            return
        except Exception:
            pass
            
        try:
            # Let's try direct concatenation with HKDF-SHA256, salt=hs_nonce
            hkdf = HKDF(
                algorithm=hashes.SHA256(),
                length=32,
                salt=hs_nonce,
                info=b"SecureFlow session key",
            )
            derived_key = hkdf.derive(test_secret)
            aesgcm = AESGCM(derived_key)
            plain = aesgcm.decrypt(file_nonce, ct, None)
            print("SUCCESS with salt=hs_nonce! Plaintext starts with:", plain[:100])
            return
        except Exception:
            pass

    print("All alternative paths failed.")

if __name__ == "__main__":
    try_alternative()
