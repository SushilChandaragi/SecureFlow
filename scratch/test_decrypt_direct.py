import hmac
import hashlib
from pathlib import Path
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from cryptography.hazmat.primitives import hashes

def manual_decrypt():
    secret_path = Path(__file__).parent.parent / "mock_hardware_secret.txt"
    secret = secret_path.read_bytes().strip()
    print("Secret bytes length:", len(secret))
    print("Secret:", secret)

    ansible_path = Path(__file__).parent.parent / "SecureFlow_Vault" / "Ansible.pdf.enc"
    blob = ansible_path.read_bytes()
    
    hs_nonce = blob[5:37]
    file_nonce = blob[37:49]
    ct = blob[49:]
    
    # ── Try Mock Mode Derivation ──
    try:
        hkdf = HKDF(
            algorithm=hashes.SHA256(),
            length=32,
            salt=hs_nonce,
            info=b"SecureFlow session key",
        )
        derived_key = hkdf.derive(secret)
        aesgcm = AESGCM(derived_key)
        plain = aesgcm.decrypt(file_nonce, ct, None)
        print("\nSUCCESS (Mock Mode)! Plaintext starts with:", plain[:100])
        return
    except Exception as e:
        print("\nMOCK Mode decryption failed:", e)

    # ── Try Hardware Mode Derivation ──
    try:
        hmac_resp = hmac.new(secret, hs_nonce, hashlib.sha256).digest()
        ikm = hmac_resp + hs_nonce
        hkdf = HKDF(
            algorithm=hashes.SHA256(),
            length=32,
            salt=None,
            info=b"SecureFlow session key",
        )
        derived_key = hkdf.derive(ikm)
        aesgcm = AESGCM(derived_key)
        plain = aesgcm.decrypt(file_nonce, ct, None)
        print("\nSUCCESS (Hardware Mode)! Plaintext starts with:", plain[:100])
        return
    except Exception as e:
        print("\nHARDWARE Mode decryption failed:", e)

if __name__ == "__main__":
    manual_decrypt()
