from pathlib import Path

def inspect_file():
    vault_dir = Path(__file__).parent.parent / "SecureFlow_Vault"
    ansible_path = vault_dir / "Ansible.pdf.enc"
    if not ansible_path.exists():
        print("Ansible.pdf.enc not found!")
        return
        
    blob = ansible_path.read_bytes()
    print(f"File size: {len(blob)} bytes")
    print(f"Header: {blob[:4]}")
    print(f"Mode byte: {blob[4]} (chr: {chr(blob[4])})")
    print(f"Handshake nonce len: {len(blob[5:37])} bytes")
    print(f"File nonce len: {len(blob[37:49])} bytes")
    print(f"Ciphertext + tag len: {len(blob[49:])} bytes")
    print(f"First 10 bytes of hs_nonce: {blob[5:15].hex()}")
    print(f"First 10 bytes of file_nonce: {blob[37:47].hex()}")
    print(f"First 10 bytes of ciphertext: {blob[49:59].hex()}")
    print(f"Last 16 bytes (tag): {blob[-16:].hex()}")

if __name__ == "__main__":
    inspect_file()
