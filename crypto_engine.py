"""SecureFlow CryptoEngine.

This module is intentionally UI-agnostic. It implements key derivation,
AES-256-GCM encryption/decryption, and explicit key wiping.
"""
from __future__ import annotations

import ctypes
import os
import secrets
from pathlib import Path
from typing import Optional

from cryptography.exceptions import InvalidTag
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.hkdf import HKDF


class CryptoEngineError(Exception):
    """Raised when crypto operations fail in a user-visible way."""


class CryptoEngine:
    """Core cryptography for SecureFlow.

    The key is kept only in RAM as a mutable bytearray so we can explicitly wipe it
    using ctypes.memset when the vault is locked.
    """

    VAULT_HEADER_V1 = b"SFV1"  # Legacy format: header + file nonce + ciphertext.
    VAULT_HEADER_V2 = b"SFV2"  # Current format: header + handshake nonce + file nonce + ciphertext.
    VAULT_HEADER_V3 = b"SFV3"  # Header + mode + handshake nonce + file nonce + ciphertext.
    MODE_MOCK = b"M"
    MODE_HARDWARE = b"H"
    FILE_NONCE_SIZE = 12  # AES-GCM standard 96-bit nonce.
    KEY_SIZE = 32  # AES-256 key length in bytes.
    HKDF_NONCE_SIZE = 32  # Simulated hardware session nonce length.

    def __init__(
        self,
        vault_dir: Optional[Path] = None,
        hardware_secret_path: Optional[Path] = None,
    ) -> None:
        self._vault_dir = Path(
            vault_dir if vault_dir is not None else Path(__file__).resolve().parent / "SecureFlow_Vault"
        )
        self._vault_dir.mkdir(parents=True, exist_ok=True)

        self._hardware_secret_path = Path(
            hardware_secret_path
            if hardware_secret_path is not None
            else Path(__file__).resolve().parent / "mock_hardware_secret.txt"
        )

        self._key: Optional[bytearray] = None
        self._aes_key: Optional[bytearray] = None
        self._handshake_nonce: Optional[bytes] = None
        self._handshake_mode: Optional[str] = None
        self._hardware_port: Optional[str] = None

    @property
    def vault_dir(self) -> Path:
        return self._vault_dir

    @property
    def is_unlocked(self) -> bool:
        return self._key is not None

    def mock_handshake(self) -> bool:
        """Simulate a hardware-backed handshake to derive a session key.

        We read a local "hardware secret", then derive an AES-256-GCM key using HKDF-SHA256.
        The derived key is stored in a mutable bytearray so it can be wiped later.
        """
        secret = self._load_hardware_secret()

        # If a previous session key exists, wipe it before deriving a new one.
        if self._key is not None:
            self.lock_vault()

        # HKDF needs a random salt/nonce to model a one-time hardware handshake.
        self._handshake_nonce = secrets.token_bytes(self.HKDF_NONCE_SIZE)

        # HKDF returns bytes; we immediately move into bytearray for explicit wiping later.
        # Note: cryptography will still handle key material internally; only our copy is wiped.
        self._key = self._derive_key(secret, self._handshake_nonce)
        self._aes_key = self._key
        self._handshake_mode = "mock"
        self._hardware_port = None
        return True

    def hardware_handshake(self, com_port: str) -> bool:
        """Derive a session key using an ESP32 HMAC oracle over Serial.

        The ESP32 receives a 32-byte nonce and returns a 32-byte HMAC-SHA256.
        We then combine HMAC + nonce as input material to HKDF-SHA256, yielding
        the AES-256-GCM session key. The key is stored in a bytearray so it can
        be wiped with ctypes.memset when the vault is locked.
        """
        # If a previous session key exists, wipe it before deriving a new one.
        if self._key is not None:
            self.lock_vault()

        handshake_nonce = secrets.token_bytes(self.HKDF_NONCE_SIZE)
        self._handshake_nonce = handshake_nonce

        response = self._hardware_hmac(com_port, handshake_nonce)

        self._key = self._derive_key_from_hmac(response, handshake_nonce)
        self._aes_key = self._key
        self._handshake_mode = "hardware"
        self._hardware_port = com_port
        return True

    def encrypt_file(self, filepath: str | Path) -> Path:
        """Encrypt a file and store it in the SecureFlow_Vault directory.

        The original file is removed using os.remove() per MVP requirements.
        """
        self._require_key()
        if self._handshake_nonce is None:
            raise CryptoEngineError("Handshake nonce missing. Perform hardware tap again.")
        if self._handshake_mode is None:
            raise CryptoEngineError("Handshake mode unknown. Perform hardware tap again.")

        src_path = Path(filepath)
        if not src_path.is_file():
            raise CryptoEngineError(f"File not found: {src_path}")

        plaintext = src_path.read_bytes()

        # AES-GCM requires a unique nonce for every encryption with the same key.
        file_nonce = secrets.token_bytes(self.FILE_NONCE_SIZE)
        aesgcm = AESGCM(bytes(self._key))
        ciphertext = aesgcm.encrypt(file_nonce, plaintext, None)

        if self._handshake_mode == "hardware":
            mode = self.MODE_HARDWARE
        else:
            mode = self.MODE_MOCK

        # Format V3: [MAGIC][MODE][HANDSHAKE_NONCE][FILE_NONCE][CIPHERTEXT]
        blob = self.VAULT_HEADER_V3 + mode + self._handshake_nonce + file_nonce + ciphertext

        dest_path = self._unique_path(self._vault_dir / f"{src_path.name}.enc")
        dest_path.write_bytes(blob)

        try:
            os.remove(src_path)
        except Exception as exc:
            raise CryptoEngineError(
                "Encrypted file saved, but deleting the original file failed."
            ) from exc

        return dest_path

    def decrypt_to_memory(self, enc_filepath: str | Path, com_port: Optional[str] = None) -> bytes:
        """Decrypt a .enc file into memory and return raw bytes.

        No plaintext is ever written to disk.
        """
        enc_path = Path(enc_filepath)
        if not enc_path.is_file():
            raise CryptoEngineError(f"Encrypted file not found: {enc_path}")

        blob = enc_path.read_bytes()
        return self.decrypt_blob(blob, com_port=com_port)

    def decrypt_blob(self, blob: bytes, com_port: Optional[str] = None) -> bytes:
        """Decrypt an encrypted blob already resident in memory.

        This is used for cloud downloads where encrypted data must never touch disk.
        """
        self._require_key()

        if len(blob) < 4:
            raise CryptoEngineError("Encrypted file is too small or corrupted.")

        header = blob[:4]
        if header == self.VAULT_HEADER_V3:
            min_len = 4 + 1 + self.HKDF_NONCE_SIZE + self.FILE_NONCE_SIZE + 16
            if len(blob) < min_len:
                raise CryptoEngineError("Encrypted file is too small or corrupted.")

            mode = blob[4:5]
            handshake_start = 5
            handshake_end = handshake_start + self.HKDF_NONCE_SIZE
            file_nonce_start = handshake_end
            file_nonce_end = file_nonce_start + self.FILE_NONCE_SIZE

            handshake_nonce = blob[handshake_start:handshake_end]
            file_nonce = blob[file_nonce_start:file_nonce_end]
            ciphertext = blob[file_nonce_end:]

            if mode == self.MODE_HARDWARE:
                port = com_port or self._hardware_port
                if not port:
                    raise CryptoEngineError("Hardware port missing. Connect ESP32 and tap hardware.")

                response = self._hardware_hmac(port, handshake_nonce)
                derived_key = self._derive_key_from_hmac(response, handshake_nonce)
                try:
                    aesgcm = AESGCM(bytes(derived_key))
                    plaintext = aesgcm.decrypt(file_nonce, ciphertext, None)
                except InvalidTag as exc:
                    raise CryptoEngineError("Decryption failed. Wrong key or corrupted data.") from exc
                finally:
                    self._wipe_key(derived_key)

                return plaintext

            if mode != self.MODE_MOCK:
                raise CryptoEngineError("Unrecognized encryption mode in file.")

            secret = self._load_hardware_secret()
            derived_key = self._derive_key(secret, handshake_nonce)
            try:
                aesgcm = AESGCM(bytes(derived_key))
                plaintext = aesgcm.decrypt(file_nonce, ciphertext, None)
            except InvalidTag as exc:
                raise CryptoEngineError("Decryption failed. Wrong key or corrupted data.") from exc
            finally:
                self._wipe_key(derived_key)

            return plaintext

        if header == self.VAULT_HEADER_V2:
            min_len = 4 + self.HKDF_NONCE_SIZE + self.FILE_NONCE_SIZE + 16
            if len(blob) < min_len:
                raise CryptoEngineError("Encrypted file is too small or corrupted.")

            handshake_start = 4
            handshake_end = handshake_start + self.HKDF_NONCE_SIZE
            file_nonce_start = handshake_end
            file_nonce_end = file_nonce_start + self.FILE_NONCE_SIZE

            handshake_nonce = blob[handshake_start:handshake_end]
            file_nonce = blob[file_nonce_start:file_nonce_end]
            ciphertext = blob[file_nonce_end:]

            # If the current session key matches the file's handshake, use it directly.
            if self._handshake_nonce == handshake_nonce and self._key is not None:
                aesgcm = AESGCM(bytes(self._key))
                try:
                    return aesgcm.decrypt(file_nonce, ciphertext, None)
                except InvalidTag as exc:
                    raise CryptoEngineError("Decryption failed. Wrong key or corrupted data.") from exc

            # Otherwise, fall back to re-deriving from the local mock secret.
            secret = self._load_hardware_secret()
            derived_key = self._derive_key(secret, handshake_nonce)
            try:
                aesgcm = AESGCM(bytes(derived_key))
                plaintext = aesgcm.decrypt(file_nonce, ciphertext, None)
            except InvalidTag as exc:
                raise CryptoEngineError("Decryption failed. Wrong key or corrupted data.") from exc
            finally:
                self._wipe_key(derived_key)

            return plaintext

        if header == self.VAULT_HEADER_V1:
            min_len = 4 + self.FILE_NONCE_SIZE + 16
            if len(blob) < min_len:
                raise CryptoEngineError("Encrypted file is too small or corrupted.")

            nonce_start = 4
            nonce_end = nonce_start + self.FILE_NONCE_SIZE
            file_nonce = blob[nonce_start:nonce_end]
            ciphertext = blob[nonce_end:]

            aesgcm = AESGCM(bytes(self._key))
            try:
                plaintext = aesgcm.decrypt(file_nonce, ciphertext, None)
            except InvalidTag as exc:
                raise CryptoEngineError("Decryption failed. Wrong key or corrupted data.") from exc

            return plaintext

        raise CryptoEngineError("Unrecognized file format (missing header).")

    def lock_vault(self) -> None:
        """Wipe the in-memory key with ctypes.memset and drop references."""
        if self._key is None:
            return

        self._wipe_key(self._key)

        # Remove references to encourage GC of any lingering objects.
        self._key = None
        self._aes_key = None
        self._handshake_nonce = None
        self._handshake_mode = None
        self._hardware_port = None

    def _require_key(self) -> None:
        if self._key is None:
            raise CryptoEngineError("Vault is locked. Perform hardware tap to unlock.")

    def _unique_path(self, path: Path) -> Path:
        """Avoid overwriting existing files by adding a numeric suffix."""
        if not path.exists():
            return path

        stem = path.stem
        suffix = path.suffix
        for i in range(1, 1000):
            candidate = path.with_name(f"{stem}_{i}{suffix}")
            if not candidate.exists():
                return candidate

        raise CryptoEngineError("Too many duplicate filenames in the vault.")

    def _load_hardware_secret(self) -> bytes:
        if not self._hardware_secret_path.is_file():
            raise CryptoEngineError(
                "Missing mock_hardware_secret.txt. Create it with a high-entropy secret string."
            )

        secret = self._hardware_secret_path.read_bytes()
        if not secret:
            raise CryptoEngineError("mock_hardware_secret.txt is empty.")

        return secret

    def _derive_key(self, secret: bytes, handshake_nonce: bytes) -> bytearray:
        hkdf = HKDF(
            algorithm=hashes.SHA256(),
            length=self.KEY_SIZE,
            salt=handshake_nonce,
            info=b"SecureFlow session key",
        )
        return bytearray(hkdf.derive(secret))

    def _derive_key_from_hmac(self, hmac_response: bytes, handshake_nonce: bytes) -> bytearray:
        ikm = hmac_response + handshake_nonce
        hkdf = HKDF(
            algorithm=hashes.SHA256(),
            length=self.KEY_SIZE,
            salt=None,
            info=b"SecureFlow session key",
        )
        return bytearray(hkdf.derive(ikm))

    def _hardware_hmac(self, com_port: str, nonce: bytes) -> bytes:
        try:
            import serial
        except Exception as exc:  # pragma: no cover - import failure depends on environment
            raise CryptoEngineError("pyserial is required for hardware handshake.") from exc

        try:
            with serial.Serial(com_port, 115200, timeout=2) as ser:
                ser.reset_input_buffer()
                ser.reset_output_buffer()
                ser.write(nonce)
                ser.flush()
                response = ser.read(self.HKDF_NONCE_SIZE)
        except serial.SerialException as exc:
            raise CryptoEngineError(f"Unable to open serial port: {com_port}") from exc

        if len(response) != self.HKDF_NONCE_SIZE:
            raise CryptoEngineError("ESP32 did not return a full 32-byte HMAC response.")

        return response

    def _wipe_key(self, key: Optional[bytearray]) -> None:
        if not key:
            return

        key_len = len(key)
        if key_len == 0:
            return

        addr = ctypes.addressof(ctypes.c_char.from_buffer(key))
        ctypes.memset(addr, 0, key_len)

