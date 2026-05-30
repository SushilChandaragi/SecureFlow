import hmac
import hashlib
from pathlib import Path
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from cryptography.hazmat.primitives import hashes

def try_mvk_decrypt():
    # 1. Derive the MVK from mock secret
    secret = b"SecureFlow-Mock-Secret-Change-Me-Use-High-Entropy"
    SETUP_NONCE = b"SecureFlow-MVK-Setup-v1" + b"\x00" * 9
    
    # Compute HMAC response
    hmac_response = hmac.new(secret, SETUP_NONCE, hashlib.sha256).digest()
    
    # Derive MVK
    ikm = hmac_response + SETUP_NONCE
    hkdf = HKDF(
        algorithm=hashes.SHA256(),
        length=32,
        salt=None,
        info=b"SecureFlow session key",
    )
    mvk_bytes = hkdf.derive(ikm)
    print("MVK hex:", mvk_bytes.hex())
    
    # 2. Try to decrypt vault files using different secrets (raw secret, MVK bytes, MVK hex)
    vault_dir = Path(__file__).parent.parent / "SecureFlow_Vault"
    
    secrets_to_try = {
        "raw_secret": secret,
        "mvk_bytes": mvk_bytes,
        "mvk_hex_bytes": mvk_bytes.hex().encode('utf-8')
    }
    
    for local_path in vault_dir.glob("*.enc"):
        if local_path.name in ["auth_keys.enc", "passwords.enc"]:
            continue
        print(f"\n--- Testing File: {local_path.name} ---")
        blob = local_path.read_bytes()
        mode = chr(blob[4])
        print(f"Mode: {mode}")
        
        hs_nonce = blob[5:37]
        file_nonce = blob[37:49]
        ct = blob[49:]
        
        for name, key_mat in secrets_to_try.items():
            # Try Mock Mode Derivation
            try:
                hkdf_mock = HKDF(
                    algorithm=hashes.SHA256(),
                    length=32,
                    salt=hs_nonce,
                    info=b"SecureFlow session key",
                )
                derived_key = hkdf_mock.derive(key_mat)
                aesgcm = AESGCM(derived_key)
                plain = aesgcm.decrypt(file_nonce, ct, None)
                print(f"SUCCESS with {name} in Mode M! Plaintext sample: {plain[:60]}")
                continue
            except Exception:
                pass
                
            # Try Hardware Mode Derivation
            try:
                hmac_resp = hmac.new(key_mat, hs_nonce, hashlib.sha256).digest()
                ikm_hw = hmac_resp + hs_nonce
                hkdf_hw = HKDF(
                    algorithm=hashes.SHA256(),
                    length=32,
                    salt=None,
                    info=b"SecureFlow session key",
                )
                derived_key_hw = hkdf_hw.derive(ikm_hw)
                aesgcm_hw = AESGCM(derived_key_hw)
                plain = aesgcm_hw.decrypt(file_nonce, ct, None)
                print(f"SUCCESS with {name} in Mode H! Plaintext sample: {plain[:60]}")
                continue
            except Exception:
                pass
                
            # Let's try what mobile does if hardware secret is normal byte string but has been passed or derived differently
            
if __name__ == "__main__":
    try_mvk_decrypt()
