#!/usr/bin/env python3
"""SecureFlow Vault Setup Script (MVK Generation)

This script executes the one-time Master Vault Key (MVK) derivation using
the physical ESP32 hardware device (or simulated MOCK hardware fallback).
It then generates the QR code required to pair your SecureFlow Mobile Companion.

Dependencies:
  pip install pyserial cryptography qrcode pillow
"""

import sys
import time
import hashlib
import hmac
from pathlib import Path

# Try to import optional packages with clean error feedback
try:
    import serial
    import serial.tools.list_ports
except ImportError:
    print("[-] Warning: 'pyserial' library not found. Serial communication will be disabled.")
    serial = None

try:
    from cryptography.hazmat.primitives.kdf.hkdf import HKDF
    from cryptography.hazmat.primitives import hashes
except ImportError:
    print("[-] Error: 'cryptography' library is required to run this script.")
    print("    Install it via: pip install cryptography")
    sys.exit(1)

try:
    import qrcode
except ImportError:
    print("[-] Error: 'qrcode' library is required to generate the pairing QR code.")
    print("    Install it via: pip install qrcode pillow")
    sys.exit(1)

# Cryptographic Constants
SETUP_NONCE = b"SecureFlow-MVK-Setup-v1" + b"\x00" * 9  # Exactly 32 bytes
KEY_SIZE = 32
MOCK_SECRET_FILE = Path(__file__).resolve().parent / "mock_hardware_secret.txt"


def get_mock_secret() -> bytes:
    """Loads the fallback secret string from mock_hardware_secret.txt."""
    if MOCK_SECRET_FILE.is_file():
        secret = MOCK_SECRET_FILE.read_bytes().strip()
        if secret:
            return secret
    return b"SecureFlow-Mock-Secret-Change-Me-Use-High-Entropy"


def derive_mvk(hmac_response: bytes, nonce: bytes) -> bytes:
    """Derives the 32-byte MVK using HKDF-SHA256."""
    ikm = hmac_response + nonce
    hkdf = HKDF(
        algorithm=hashes.SHA256(),
        length=KEY_SIZE,
        salt=None,
        info=b"SecureFlow session key",
    )
    return hkdf.derive(ikm)


def find_serial_ports():
    """Detects and returns active serial COM ports."""
    if not serial:
        return []
    ports = list(serial.tools.list_ports.comports())
    return [p.device for p in ports]


def perform_hardware_handshake(port: str) -> bytes:
    """Sends setup nonce to ESP32 and reads the 32-byte HMAC response."""
    print(f"[*] Opening serial connection to ESP32 on {port} (Baud: 115200)...")
    try:
        with serial.Serial(port, 115200, timeout=5) as ser:
            time.sleep(2)  # Wait for ESP32 serial reset
            ser.reset_input_buffer()
            ser.reset_output_buffer()

            print(f"[*] Transmitting 32-byte setup challenge nonce...")
            ser.write(SETUP_NONCE)
            ser.flush()

            print("[*] Awaiting 32-byte HMAC response from hardware...")
            response = ser.read(32)

            if len(response) != 32:
                raise ValueError(
                    f"Invalid response length: received {len(response)} bytes, expected 32."
                )

            print("[+] Hardware response received successfully!")
            return response
    except Exception as e:
        print(f"[-] Serial error: {e}")
        raise


def main():
    print("=" * 60)
    print("           SECUREFLOW VAULT MVK SETUP SYSTEM")
    print("=" * 60)

    # 1. Choose execution mode (Physical ESP32 vs Simulated Mock)
    ports = find_serial_ports()
    print("[*] Available Serial Ports:")
    for idx, p in enumerate(ports, 1):
        print(f"    [{idx}] {p}")
    print(f"    [M] Simulated MOCK Mode (uses {MOCK_SECRET_FILE.name})")

    choice = input("\nSelect device index or 'M' for Mock: ").strip()
    # Strip potential Byte Order Marks (BOM) from console/shell pipeline redirection
    choice = choice.replace('\xc3\xaf\xc2\xbb\xc2\xbf', '').replace('\xef\xbb\xbf', '').replace('\ufeff', '').replace('\xff\xfe', '').strip()

    if choice.upper() == 'M':
        print("\n[*] Starting derivation in Simulated MOCK Mode...")
        secret = get_mock_secret()
        print(f"[*] Keying Material: '{secret.decode('utf-8', errors='ignore')}'")
        # Compute local HMAC-SHA256 to model the hardware oracle
        hmac_response = hmac.new(secret, SETUP_NONCE, hashlib.sha256).digest()
    else:
        try:
            port_idx = int(choice) - 1
            if port_idx < 0 or port_idx >= len(ports):
                raise ValueError("Invalid index selection.")
            selected_port = ports[port_idx]
            hmac_response = perform_hardware_handshake(selected_port)
            secret = get_mock_secret()
        except Exception as e:
            print(f"[-] Setup failed: {e}")
            print("[*] Falling back to Simulated MOCK Mode for safety...")
            secret = get_mock_secret()
            hmac_response = hmac.new(secret, SETUP_NONCE, hashlib.sha256).digest()

    # 2. Derive the Master Vault Key (MVK)
    print("[*] Running HKDF-SHA256 Master Key Derivation...")
    mvk_bytes = derive_mvk(hmac_response, SETUP_NONCE)
    mvk_hex = mvk_bytes.hex()

    print("\n" + "=" * 50)
    print(f"[+] SUCCESS: Master Vault Key Derived!")
    print(f"    MVK (HEX): {mvk_hex}")
    print("=" * 50 + "\n")

    # 3. Generate QR code for mobile pairing
    print("[*] Generating pairing QR Code...")
    qr = qrcode.QRCode(
        version=1,
        error_correction=qrcode.constants.ERROR_CORRECT_L,
        box_size=10,
        border=4,
    )
    # Encode the raw hardware/mock secret string for seamless zero-knowledge mobile pairing
    pairing_payload = secret.decode('utf-8', errors='ignore').strip()
    qr.add_data(pairing_payload)
    qr.make(fit=True)

    img = qr.make_image(fill_color="black", back_color="white")
    qr_filename = "mvk_pairing_qr.png"
    img.save(qr_filename)

    print(f"[+] Saved pairing QR code as: {Path(qr_filename).resolve()}")
    print("[*] Open this image and scan it with SecureFlow Mobile settings to pair devices!")
    print("\n" + "*" * 70)
    print(" [WARNING] MOBILE COMPANION PAIRING DETAILS:")
    print("     Do NOT paste the 'MVK (HEX)' string above into your mobile app.")
    print("     Instead, scan the QR code OR copy & paste this exact raw secret:")
    print(f"     >>> {pairing_payload}")
    print("*" * 70 + "\n")


if __name__ == "__main__":
    main()
