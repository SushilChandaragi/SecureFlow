import sys
from pathlib import Path

from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.hkdf import HKDF


def _load_secret() -> bytes:
    secret_path = Path("mock_hardware_secret.txt")
    if not secret_path.is_file():
        print("ERROR: mock_hardware_secret.txt not found")
        sys.exit(1)
    secret_bytes = secret_path.read_bytes().strip()
    print(f"secret bytes: {secret_bytes!r}")
    print(f"secret hex: {secret_bytes.hex()}")
    return secret_bytes


def _load_blob(path: Path) -> bytes:
    if not path.is_file():
        print(f"ERROR: Encrypted file not found: {path}")
        sys.exit(1)
    return path.read_bytes()


def main() -> None:
    if len(sys.argv) < 2:
        print("USAGE: python verify_parity.py <path-to-.enc>")
        sys.exit(1)

    secret_bytes = _load_secret()
    enc_file = Path(sys.argv[1])
    blob = _load_blob(enc_file)

    print(f"enc file: {enc_file}")
    print(f"blob size: {len(blob)} bytes")

    if len(blob) < 4:
        print("ERROR: File is too small")
        sys.exit(1)

    magic = blob[0:4]
    print(f"magic: {magic!r}")

    if magic != b"SFV3":
        print(f"ERROR: Unsupported header {magic!r}")
        sys.exit(1)

    mode = blob[4:5]
    handshake_nonce = blob[5:37]
    file_nonce = blob[37:49]
    ciphertext = blob[49:]

    print(f"mode byte: {mode!r}")
    print(f"handshake_nonce hex: {handshake_nonce.hex()}")
    print(f"file_nonce hex: {file_nonce.hex()}")
    print(f"ciphertext+tag hex (first 64): {ciphertext[:64].hex()}")

    if mode == b"M":
        hkdf = HKDF(
            algorithm=hashes.SHA256(),
            length=32,
            salt=handshake_nonce,
            info=b"SecureFlow session key",
        )
        derived_key = hkdf.derive(secret_bytes)
    elif mode == b"H":
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
        print(f"ERROR: Unknown mode {mode!r}")
        sys.exit(1)

    print(f"derived_key hex: {derived_key.hex()}")

    try:
        aesgcm = AESGCM(derived_key)
        plaintext = aesgcm.decrypt(file_nonce, ciphertext, None)
        print("decryption result: SUCCESS")
        print(f"plaintext prefix (first 100 bytes): {plaintext[:100]!r}")
    except Exception as exc:
        print(f"decryption result: FAILED ({exc})")


if __name__ == "__main__":
    main()
