import qrcode
from PIL import Image
from pyzbar.pyzbar import decode

def check():
    try:
        data = decode(Image.open('mvk_pairing_qr.png'))
        if data:
            print("QR Content:", data[0].data.decode('utf-8'))
        else:
            print("Could not decode QR code.")
    except Exception as e:
        print("Error decoding QR:", e)

if __name__ == '__main__':
    check()
