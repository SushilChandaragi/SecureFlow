import cv2
import sys
from pathlib import Path

def decode_qr():
    qr_path = Path("mvk_pairing_qr.png")
    if not qr_path.exists():
        print(f"Error: {qr_path} not found.")
        sys.exit(1)
        
    print(f"Loading QR code image: {qr_path}")
    img = cv2.imread(str(qr_path))
    detector = cv2.QRCodeDetector()
    val, points, straight_qrcode = detector.detectAndDecode(img)
    
    if val:
        print("Successfully decoded QR code!")
        print(f"Payload value: {repr(val)}")
    else:
        print("Failed to decode QR code using cv2.QRCodeDetector.")

if __name__ == "__main__":
    decode_qr()
