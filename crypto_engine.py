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
        self._handshake_nonce: Optional[bytes] = None

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
        return True

    def encrypt_file(self, filepath: str | Path) -> Path:
        """Encrypt a file and store it in the SecureFlow_Vault directory.

        The original file is removed using os.remove() per MVP requirements.
        """
        self._require_key()
        if self._handshake_nonce is None:
            raise CryptoEngineError("Handshake nonce missing. Simulate hardware tap again.")

        src_path = Path(filepath)
        if not src_path.is_file():
            raise CryptoEngineError(f"File not found: {src_path}")

        plaintext = src_path.read_bytes()

        # AES-GCM requires a unique nonce for every encryption with the same key.
        file_nonce = secrets.token_bytes(self.FILE_NONCE_SIZE)
        aesgcm = AESGCM(bytes(self._key))
        ciphertext = aesgcm.encrypt(file_nonce, plaintext, None)

        # Format V2: [MAGIC][HANDSHAKE_NONCE][FILE_NONCE][CIPHERTEXT]
        blob = self.VAULT_HEADER_V2 + self._handshake_nonce + file_nonce + ciphertext

        dest_path = self._unique_path(self._vault_dir / f"{src_path.name}.enc")
        dest_path.write_bytes(blob)

        try:
            os.remove(src_path)
        except Exception as exc:
            raise CryptoEngineError(
                "Encrypted file saved, but deleting the original file failed."
            ) from exc

        return dest_path

    def decrypt_to_memory(self, enc_filepath: str | Path) -> bytes:
        """Decrypt a .enc file into memory and return raw bytes.

        No plaintext is ever written to disk.
        """
        self._require_key()

        enc_path = Path(enc_filepath)
        if not enc_path.is_file():
            raise CryptoEngineError(f"Encrypted file not found: {enc_path}")

        blob = enc_path.read_bytes()
        if len(blob) < 4:
            raise CryptoEngineError("Encrypted file is too small or corrupted.")

        header = blob[:4]
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
        self._handshake_nonce = None

    def _require_key(self) -> None:
        if self._key is None:
            raise CryptoEngineError("Vault is locked. Simulate hardware tap to unlock.")

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

    def _wipe_key(self, key: Optional[bytearray]) -> None:
        if not key:
            return

        key_len = len(key)
        if key_len == 0:
            return

        addr = ctypes.addressof(ctypes.c_char.from_buffer(key))
        ctypes.memset(addr, 0, key_len)

