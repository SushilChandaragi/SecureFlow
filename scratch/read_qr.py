import cv2
from pathlib import Path

def read_qr():
    qr_path = Path(__file__).parent.parent / "mvk_pairing_qr.png"
    if not qr_path.exists():
        print("mvk_pairing_qr.png not found!")
        return
        
    img = cv2.imread(str(qr_path))
    detector = cv2.QRCodeDetector()
    data, bbox, straight_qrcode = detector.detectAndDecode(img)
    if data:
        print("QR Code Data:")
        print(repr(data))
    else:
        print("Failed to decode QR code!")

if __name__ == "__main__":
    read_qr()
