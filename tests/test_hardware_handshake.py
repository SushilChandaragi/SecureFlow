import unittest
import sys
import os
import json
import tempfile
import shutil
from pathlib import Path

# Add project root to sys.path so we can import modules
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from crypto_engine import CryptoEngine, CryptoEngineError

class TestHardwareHandshake(unittest.TestCase):
    def setUp(self):
        # Create a temporary directory for the vault
        self.test_dir = tempfile.mkdtemp()
        self.vault_dir = Path(self.test_dir) / "SecureFlow_Vault"
        self.vault_dir.mkdir(parents=True, exist_ok=True)
        
        # Create a mock hardware secret file
        self.secret_file = Path(self.test_dir) / "mock_hardware_secret.txt"
        self.secret_file.write_bytes(b"SecureFlow-Mock-Secret-Change-Me-Use-High-Entropy")
        
        # Initialize CryptoEngine
        self.crypto = CryptoEngine(
            vault_dir=self.vault_dir,
            hardware_secret_path=self.secret_file
        )

    def tearDown(self):
        # lock the vault to clean up keys
        self.crypto.lock_vault()
        # Clean up files
        shutil.rmtree(self.test_dir, ignore_errors=True)

    def test_mock_hardware_handshake_unlocks(self):
        # Ensure initial state is locked
        self.assertFalse(self.crypto.is_unlocked)
        
        # Perform handshake on the 'MOCK' port
        success = self.crypto.hardware_handshake("MOCK")
        self.assertTrue(success)
        self.assertTrue(self.crypto.is_unlocked)

    def test_cryptographic_parity_and_bytes_operations(self):
        # Perform handshake to unlock
        self.crypto.hardware_handshake("MOCK")
        
        # Plaintext to encrypt
        plaintext = b"Super-secret-password-123!"
        
        # Encrypt bytes
        encrypted_blob = self.crypto.encrypt_bytes(plaintext)
        self.assertIsNotNone(encrypted_blob)
        self.assertNotEqual(plaintext, encrypted_blob)
        
        # Decrypt bytes
        decrypted = self.crypto.decrypt_bytes(encrypted_blob)
        self.assertEqual(plaintext, decrypted)
        
        # Decrypt blob using the com_port parameter
        decrypted_with_port = self.crypto.decrypt_blob(encrypted_blob, com_port="MOCK")
        self.assertEqual(plaintext, decrypted_with_port)

    def test_lock_vault_wipes_keys(self):
        # Unlock vault
        self.crypto.hardware_handshake("MOCK")
        self.assertTrue(self.crypto.is_unlocked)
        
        # Capture reference to the key array
        key_ref = self.crypto._key
        self.assertIsNotNone(key_ref)
        self.assertNotEqual(sum(key_ref), 0) # Key is not all zeros
        
        # Lock vault
        self.crypto.lock_vault()
        self.assertFalse(self.crypto.is_unlocked)
        self.assertIsNone(self.crypto._key)
        
        # Verify memory wiping: all elements in the captured key array must be zero!
        self.assertEqual(sum(key_ref), 0)

    def test_invalid_com_port_raises_error(self):
        # Try to tap with an invalid port name that does not exist on this machine
        with self.assertRaises(CryptoEngineError):
            self.crypto.hardware_handshake("NON_EXISTENT_COM_PORT_XYZ")

    def test_password_json_serialization_flow(self):
        # Unlock vault
        self.crypto.hardware_handshake("MOCK")
        
        # Create a sample password dictionary payload
        passwords = [
            {"website": "google.com", "username": "admin", "password": "g-pass-123"},
            {"website": "github.com", "username": "dev", "password": "git-pass-456"}
        ]
        
        # Serialize to bytes
        blob = json.dumps(passwords, ensure_ascii=True).encode("utf-8")
        
        # Encrypt
        encrypted = self.crypto.encrypt_bytes(blob)
        
        # Decrypt
        decrypted = self.crypto.decrypt_bytes(encrypted)
        
        # Deserialize
        loaded_passwords = json.loads(decrypted.decode("utf-8"))
        self.assertEqual(passwords, loaded_passwords)

if __name__ == "__main__":
    unittest.main()
