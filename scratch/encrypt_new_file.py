import sys
from pathlib import Path
import os

# Add parent dir to path for imports
sys.path.append(str(Path(__file__).parent.parent))
from crypto_engine import CryptoEngine

def main():
    engine = CryptoEngine()
    
    # 1. Test Mode M (Mock)
    print("\n--- Testing Mode M ---")
    engine.mock_handshake()
    test_file_m = Path("scratch/test_m.txt")
    test_file_m.write_text("This is a newly encrypted Mode M file on desktop!")
    
    enc_path_m = engine.encrypt_file(test_file_m)
    print(f"Encrypted to: {enc_path_m.name}")
    
    # Try decrypting
    decrypted_m = engine.decrypt_to_memory(enc_path_m, com_port="MOCK")
    print("Decrypted Mode M plaintext:", decrypted_m.decode('utf-8'))
    
    # 2. Test Mode H (Hardware simulated)
    print("\n--- Testing Mode H (Hardware mock) ---")
    engine.hardware_handshake("MOCK")
    test_file_h = Path("scratch/test_h.txt")
    test_file_h.write_text("This is a newly encrypted Mode H file on desktop!")
    
    enc_path_h = engine.encrypt_file(test_file_h)
    print(f"Encrypted to: {enc_path_h.name}")
    
    # Try decrypting
    decrypted_h = engine.decrypt_to_memory(enc_path_h, com_port="MOCK")
    print("Decrypted Mode H plaintext:", decrypted_h.decode('utf-8'))

if __name__ == "__main__":
    main()
