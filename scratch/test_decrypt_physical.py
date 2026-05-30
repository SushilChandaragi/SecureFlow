import sys
from pathlib import Path
import time
import serial
import hmac
import hashlib
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from cryptography.hazmat.primitives import hashes

def main():
    port = "COM3"
    print(f"Opening physical serial port: {port}")
    
    local_path = Path("SecureFlow_Vault/invoice.pdf.enc")
    blob = local_path.read_bytes()
    hs_nonce = blob[5:37]
    file_nonce = blob[37:49]
    ct = blob[49:]
    
    try:
        with serial.Serial(port, 115200, timeout=5) as ser:
            print("Opened. Sleeping 2 seconds for ESP32 reset...")
            time.sleep(2)
            ser.reset_input_buffer()
            ser.reset_output_buffer()
            
            print("Writing 32-byte challenge nonce...")
            ser.write(hs_nonce)
            ser.flush()
            
            print("Reading 32-byte HMAC response...")
            response = ser.read(32)
            print(f"HMAC response (length {len(response)}): {response.hex()}")
            
            if len(response) != 32:
                print("Error: short response from physical hardware.")
                return
                
            # Derive key
            ikm = response + hs_nonce
            hkdf = HKDF(
                algorithm=hashes.SHA256(),
                length=32,
                salt=None,
                info=b"SecureFlow session key",
            )
            derived_key = hkdf.derive(ikm)
            print("Derived Key hex:", derived_key.hex())
            
            # Decrypt
            aesgcm = AESGCM(derived_key)
            plain = aesgcm.decrypt(file_nonce, ct, None)
            print("SUCCESS! Decryption worked! Plaintext starts with:", plain[:100])
            
    except Exception as e:
        print("Failed to decrypt using physical ESP32:", e)

if __name__ == "__main__":
    main()
