"""SecureFlow GUI built with customtkinter."""
from __future__ import annotations

from pathlib import Path
import json
import time
import gc
import logging
from tkinter import filedialog, messagebox

import customtkinter as ctk
import fitz  # PyMuPDF
from PIL import Image

from cloud_manager import CloudManager, CloudManagerError
from crypto_engine import CryptoEngine, CryptoEngineError


logger = logging.getLogger(__name__)


PASSWORD_STORE_FILENAME = "passwords.enc"


COLORS = {
    "bg": "#18181b",
    "panel": "#27272a",
    "panel_alt": "#1f1f22",
    "panel_alt_hover": "#2d2d31",
    "text": "#e4e4e7",
    "muted": "#a1a1aa",
    "accent": "#2563eb",
    "accent_hover": "#1d4ed8",
    "success": "#16a34a",
    "danger": "#dc2626",
    "danger_hover": "#b91c1c",
    "border": "#3f3f46",
    "badge_bg": "#2a2a2f",
    "badge_border": "#42424a",
    "badge_inactive": "#2f2f34",
    "badge_text_inactive": "#8a8a94",
}

FONTS = {
    "title": ("Segoe UI", 20, "bold"),
    "section": ("Segoe UI", 14, "bold"),
    "status": ("Segoe UI", 16, "bold"),
    "body": ("Segoe UI", 12),
}


class VaultGUI(ctk.CTk):
    """SecureFlow main application window."""

    def __init__(self, crypto_engine: CryptoEngine) -> None:
        super().__init__()

        self.crypto = crypto_engine
        self._pdf_image: ctk.CTkImage | None = None
        self._pdf_images: list[ctk.CTkImage] = []
        self._pdf_bytes: bytes | None = None
        self._pdf_scroll_frame: ctk.CTkScrollableFrame | None = None
        self._zoom_factor = 2.0
        self._file_buttons: list[ctk.CTkButton] = []
        self._viewer_has_content = False
        self.cloud: CloudManager | None = None
        self._hardware_port: str = ""
        self._hardware_monitor_id: str | None = None
        self._last_selected_object: tuple[str, str] | None = None
        self._password_store: dict[str, dict[str, str]] = {}

        self.title("SecureFlow Vault")
        self.geometry("1280x720")
        self.minsize(1024, 640)
        self.configure(fg_color=COLORS["bg"])

        self._build_layout()
        self._init_cloud()
        self.refresh_vault_listing()
        self._set_unlocked_state(self.crypto.is_unlocked, message="Vault is locked. Hardware tap required.")

        # Auto-tap on launch for demo convenience.
        self.after(300, self._auto_tap_on_launch)

        self.protocol("WM_DELETE_WINDOW", self._on_close)

    def _build_layout(self) -> None:
        self.grid_columnconfigure(0, weight=0)
        self.grid_columnconfigure(1, weight=1)
        self.grid_rowconfigure(0, weight=1)

        self.sidebar_frame = ctk.CTkFrame(self, fg_color=COLORS["panel"], corner_radius=14)
        self.sidebar_frame.grid(row=0, column=0, sticky="nsew", padx=(16, 8), pady=16)
        self.sidebar_frame.grid_columnconfigure(0, weight=1)
        self.sidebar_frame.grid_rowconfigure(4, weight=3)
        self.sidebar_frame.grid_rowconfigure(5, weight=1)

        ctk.CTkLabel(
            self.sidebar_frame,
            text="SecureFlow Vault",
            font=FONTS["title"],
            text_color=COLORS["text"],
        ).grid(row=0, column=0, sticky="w", padx=16, pady=(16, 10))

        self.handshake_row = ctk.CTkFrame(self.sidebar_frame, fg_color="transparent")
        self.handshake_row.grid(row=1, column=0, sticky="ew", padx=16, pady=6)
        self.handshake_row.grid_columnconfigure(0, weight=1)
        self.handshake_row.grid_columnconfigure(1, weight=0)
        self.handshake_row.grid_columnconfigure(2, weight=0)

        self.handshake_button = ctk.CTkButton(
            self.handshake_row,
            text="Hardware Tap",
            fg_color=COLORS["accent"],
            hover_color=COLORS["accent_hover"],
            text_color=COLORS["text"],
            command=self._on_handshake_click,
        )
        self.handshake_button.grid(row=0, column=0, sticky="ew", padx=(0, 8))

        self.port_entry = ctk.CTkEntry(
            self.handshake_row,
            width=90,
            placeholder_text="COM3",
            fg_color=COLORS["panel_alt"],
            text_color=COLORS["text"],
            border_color=COLORS["border"],
        )
        self.port_entry.grid(row=0, column=1, sticky="e", padx=(0, 6))

        self.detect_button = ctk.CTkButton(
            self.handshake_row,
            text="Auto",
            width=52,
            fg_color=COLORS["panel_alt"],
            hover_color=COLORS["panel_alt_hover"],
            text_color=COLORS["text"],
            border_width=1,
            border_color=COLORS["border"],
            command=self._auto_detect_port,
        )
        self.detect_button.grid(row=0, column=2, sticky="e")

        self.encrypt_button = ctk.CTkButton(
            self.sidebar_frame,
            text="Encrypt New File",
            fg_color=COLORS["panel_alt"],
            hover_color=COLORS["panel_alt_hover"],
            text_color=COLORS["text"],
            border_width=1,
            border_color=COLORS["border"],
            command=self._on_encrypt_click,
        )
        self.encrypt_button.grid(row=2, column=0, sticky="ew", padx=16, pady=6)

        self.vault_header_row = ctk.CTkFrame(self.sidebar_frame, fg_color="transparent")
        self.vault_header_row.grid(row=3, column=0, sticky="ew", padx=16, pady=(18, 8))
        self.vault_header_row.grid_columnconfigure(0, weight=1)

        ctk.CTkLabel(
            self.vault_header_row,
            text="Vault Browser",
            font=FONTS["section"],
            text_color=COLORS["muted"],
        ).grid(row=0, column=0, sticky="w")

        self.refresh_cloud_button = ctk.CTkButton(
            self.vault_header_row,
            text="Refresh Cloud",
            width=120,
            fg_color=COLORS["panel_alt"],
            hover_color=COLORS["panel_alt_hover"],
            text_color=COLORS["text"],
            border_width=1,
            border_color=COLORS["border"],
            command=self.refresh_vault_listing,
        )
        self.refresh_cloud_button.grid(row=0, column=1, sticky="e")

        self.vault_list_frame = ctk.CTkScrollableFrame(
            self.sidebar_frame,
            fg_color=COLORS["panel_alt"],
            border_width=1,
            border_color=COLORS["border"],
        )
        self.vault_list_frame.grid(row=4, column=0, sticky="nsew", padx=16, pady=(0, 12))

        ctk.CTkFrame(self.sidebar_frame, fg_color="transparent").grid(row=5, column=0, sticky="nsew")

        self.panic_button = ctk.CTkButton(
            self.sidebar_frame,
            text="🔒 LOCK VAULT & WIPE RAM",
            fg_color=COLORS["danger"],
            hover_color=COLORS["danger_hover"],
            text_color=COLORS["text"],
            command=self._on_panic,
        )
        self.panic_button.grid(row=6, column=0, sticky="ew", padx=16, pady=(0, 16))

        self.main_frame = ctk.CTkFrame(self, fg_color=COLORS["panel_alt"], corner_radius=14)
        self.main_frame.grid(row=0, column=1, sticky="nsew", padx=(8, 16), pady=16)
        self.main_frame.grid_columnconfigure(0, weight=1)
        self.main_frame.grid_rowconfigure(2, weight=1)

        self.status_frame = ctk.CTkFrame(self.main_frame, fg_color=COLORS["panel"], corner_radius=12)
        self.status_frame.grid(row=0, column=0, sticky="ew", padx=16, pady=(16, 10))
        self.status_frame.grid_columnconfigure(0, weight=1)

        self.status_label = ctk.CTkLabel(
            self.status_frame,
            text="Status: 🔴 LOCKED",
            font=FONTS["status"],
            text_color=COLORS["danger"],
        )
        self.status_label.grid(row=0, column=0, sticky="w", padx=16, pady=(12, 2))

        self.status_message = ctk.CTkLabel(
            self.status_frame,
            text="Vault is locked. No data in memory.",
            font=FONTS["body"],
            text_color=COLORS["muted"],
        )
        self.status_message.grid(row=1, column=0, sticky="w", padx=16, pady=(0, 12))

        self.badge_row = ctk.CTkFrame(self.status_frame, fg_color="transparent")
        self.badge_row.grid(row=2, column=0, sticky="w", padx=16, pady=(0, 10))

        self.badge_key = self._build_badge(self.badge_row, "KEY IN RAM")
        self.badge_key.pack(side="left", padx=(0, 8))

        self.badge_plaintext = self._build_badge(self.badge_row, "NO DISK PLAINTEXT")
        self.badge_plaintext.pack(side="left", padx=(0, 8))

        self.badge_aes = self._build_badge(self.badge_row, "AES-256-GCM")
        self.badge_aes.pack(side="left", padx=(0, 8))

        self.badge_hkdf = self._build_badge(self.badge_row, "HKDF-SHA256")
        self.badge_hkdf.pack(side="left")

        self.timeline_label = ctk.CTkLabel(
            self.status_frame,
            text="Security Timeline",
            font=FONTS["section"],
            text_color=COLORS["muted"],
        )
        self.timeline_label.grid(row=3, column=0, sticky="w", padx=16, pady=(4, 6))

        self.timeline_box = ctk.CTkTextbox(
            self.status_frame,
            height=110,
            fg_color=COLORS["panel_alt"],
            text_color=COLORS["text"],
            border_width=1,
            border_color=COLORS["border"],
            font=FONTS["body"],
        )
        self.timeline_box.grid(row=4, column=0, sticky="ew", padx=16, pady=(0, 12))
        self.timeline_box.configure(state="disabled")

        self.viewer_frame = ctk.CTkFrame(self.main_frame, fg_color=COLORS["panel"], corner_radius=12)
        self.viewer_frame.grid(row=2, column=0, sticky="nsew", padx=16, pady=(0, 16))
        self.viewer_frame.grid_columnconfigure(0, weight=1)
        self.viewer_frame.grid_rowconfigure(1, weight=1)

        self.viewer_toolbar = ctk.CTkFrame(self.viewer_frame, fg_color=COLORS["panel_alt"], corner_radius=10)
        self.viewer_toolbar.grid(row=0, column=0, sticky="ew", padx=12, pady=(12, 6))
        self.viewer_toolbar.grid_columnconfigure(1, weight=1)

        self.zoom_out_button = ctk.CTkButton(
            self.viewer_toolbar,
            text="-",
            width=38,
            fg_color=COLORS["panel_alt"],
            hover_color=COLORS["panel_alt_hover"],
            text_color=COLORS["text"],
            border_width=1,
            border_color=COLORS["border"],
            command=lambda: self._adjust_zoom(-0.25),
        )
        self.zoom_out_button.grid(row=0, column=0, padx=(8, 4), pady=8)

        self.zoom_label = ctk.CTkLabel(
            self.viewer_toolbar,
            text="100%",
            font=FONTS["body"],
            text_color=COLORS["muted"],
        )
        self.zoom_label.grid(row=0, column=1)

        self.zoom_in_button = ctk.CTkButton(
            self.viewer_toolbar,
            text="+",
            width=38,
            fg_color=COLORS["panel_alt"],
            hover_color=COLORS["panel_alt_hover"],
            text_color=COLORS["text"],
            border_width=1,
            border_color=COLORS["border"],
            command=lambda: self._adjust_zoom(0.25),
        )
        self.zoom_in_button.grid(row=0, column=2, padx=(4, 8), pady=8)

        self.viewer_content = ctk.CTkFrame(self.viewer_frame, fg_color=COLORS["panel_alt"], corner_radius=10)
        self.viewer_content.grid(row=1, column=0, sticky="nsew", padx=12, pady=(0, 12))
        self.viewer_content.grid_columnconfigure(0, weight=1)
        self.viewer_content.grid_rowconfigure(0, weight=1)

    def _set_status_message(self, message: str, is_error: bool = False) -> None:
        color = COLORS["danger"] if is_error else COLORS["muted"]
        self.status_message.configure(text=message, text_color=color)

    def _init_cloud(self) -> None:
        try:
            self.cloud = CloudManager()
        except CloudManagerError as exc:
            self.cloud = None
            self._set_status_message(str(exc), is_error=True)
            messagebox.showerror("Cloud Setup", str(exc))
            logger.exception("Cloud initialization failed")

    def _build_badge(self, parent: ctk.CTkFrame, text: str) -> ctk.CTkLabel:
        return ctk.CTkLabel(
            parent,
            text=text,
            font=("Segoe UI", 11, "bold"),
            text_color=COLORS["text"],
            fg_color=COLORS["badge_bg"],
            corner_radius=12,
            padx=10,
            pady=4,
        )

    def _set_badge_state(self, badge: ctk.CTkLabel, active: bool) -> None:
        if active:
            badge.configure(fg_color=COLORS["badge_bg"], text_color=COLORS["text"])
        else:
            badge.configure(fg_color=COLORS["badge_inactive"], text_color=COLORS["badge_text_inactive"])

    def _log_event(self, message: str) -> None:
        timestamp = time.strftime("%H:%M:%S")
        line = f"[{timestamp}] {message}\n"
        self.timeline_box.configure(state="normal")
        self.timeline_box.insert("end", line)
        self.timeline_box.see("end")
        self.timeline_box.configure(state="disabled")

    def _clear_viewer(self, placeholder_text: str | None = None) -> None:
        for child in self.viewer_content.winfo_children():
            child.destroy()
        self._pdf_image = None
        self._pdf_images.clear()
        self._pdf_bytes = None
        self._pdf_scroll_frame = None
        self._viewer_has_content = False
        gc.collect()  # Ensure dereferenced images are cleared promptly.

        if placeholder_text is not None:
            placeholder = ctk.CTkLabel(
                self.viewer_content,
                text=placeholder_text,
                font=FONTS["body"],
                text_color=COLORS["muted"],
            )
            placeholder.grid(row=0, column=0, sticky="nsew", padx=16, pady=16)

    def _set_unlocked_state(self, unlocked: bool, message: str | None = None, is_error: bool = False) -> None:
        if unlocked:
            self.status_label.configure(text="Status: 🟢 UNLOCKED", text_color=COLORS["success"])
            self.encrypt_button.configure(state="normal")
            for button in self._file_buttons:
                button.configure(state="normal")
            self._set_badge_state(self.badge_key, True)
            self._set_badge_state(self.badge_plaintext, True)
            self._set_badge_state(self.badge_aes, True)
            self._set_badge_state(self.badge_hkdf, True)
            if not self._viewer_has_content:
                self._clear_viewer("Select an encrypted file to view it.")
        else:
            self.status_label.configure(text="Status: 🔴 LOCKED", text_color=COLORS["danger"])
            self.encrypt_button.configure(state="disabled")
            for button in self._file_buttons:
                button.configure(state="disabled")
            self._stop_hardware_monitor()
            self._set_badge_state(self.badge_key, False)
            self._set_badge_state(self.badge_plaintext, False)
            self._set_badge_state(self.badge_aes, False)
            self._set_badge_state(self.badge_hkdf, False)
            self._clear_viewer("Vault is locked. No data in memory.")
            self._clear_passwords_memory()

        if message:
            self._set_status_message(message, is_error=is_error)

    def _save_passwords_to_vault(self) -> None:
        if not self.crypto.is_unlocked:
            return

        vault_path = self.crypto.vault_dir / PASSWORD_STORE_FILENAME
        if not self._password_store:
            if vault_path.exists():
                vault_path.unlink()
            return

        payload: dict[str, dict[str, str]] = {}
        for key, entry in self._password_store.items():
            row = {
                "website": str(entry.get("website") or ""),
                "username": str(entry.get("username") or ""),
                "password": str(entry.get("password") or ""),
            }
            if "notes" in entry and entry.get("notes") is not None:
                row["notes"] = str(entry.get("notes"))
            payload[str(key)] = row

        blob = json.dumps(payload, ensure_ascii=True).encode("utf-8")
        try:
            encrypted = self.crypto.encrypt_bytes(blob)
            vault_path.write_bytes(encrypted)
        except CryptoEngineError as exc:
            self._set_status_message(str(exc), is_error=True)
            self._log_event(f"Failed to save passwords: {exc}")
            logger.warning("Failed to save passwords: %s", exc)

    def _load_passwords_from_vault(self) -> None:
        if not self.crypto.is_unlocked:
            return

        vault_path = self.crypto.vault_dir / PASSWORD_STORE_FILENAME
        if not vault_path.is_file():
            self._password_store.clear()
            return

        port = self._hardware_port or self.port_entry.get().strip()
        try:
            raw = self.crypto.decrypt_to_memory(vault_path, com_port=port)
            data = json.loads(raw.decode("utf-8"))
        except Exception as exc:
            self._set_status_message("Failed to load passwords.", is_error=True)
            self._log_event(f"Failed to load passwords: {exc}")
            logger.warning("Failed to load passwords: %s", exc)
            return

        self._password_store.clear()
        if isinstance(data, dict):
            for key, entry in data.items():
                if not isinstance(entry, dict):
                    continue
                website = str(entry.get("website") or "")
                username = str(entry.get("username") or "")
                password = str(entry.get("password") or "")
                if not website or not username:
                    continue
                normalized_key = str(key) if key else f"{website}|{username}"
                self._password_store[normalized_key] = {
                    "website": website,
                    "username": username,
                    "password": password,
                }
                if "notes" in entry and entry.get("notes") is not None:
                    self._password_store[normalized_key]["notes"] = str(entry.get("notes"))
        elif isinstance(data, list):
            for entry in data:
                if not isinstance(entry, dict):
                    continue
                website = str(entry.get("website") or "")
                username = str(entry.get("username") or "")
                password = str(entry.get("password") or "")
                if not website or not username:
                    continue
                key = f"{website}|{username}"
                self._password_store[key] = {
                    "website": website,
                    "username": username,
                    "password": password,
                }
                if "notes" in entry and entry.get("notes") is not None:
                    self._password_store[key]["notes"] = str(entry.get("notes"))

    def _clear_passwords_memory(self) -> None:
        self._password_store.clear()

    def _on_handshake_click(self) -> None:
        port = self.port_entry.get().strip()
        if not port:
            messagebox.showerror("Hardware Tap", "Enter a COM port (e.g., COM3).")
            return

        try:
            self.crypto.hardware_handshake(port)
            self._hardware_port = port
            self._start_hardware_monitor()
            self._set_unlocked_state(True, message="Hardware tap accepted. Session unlocked.")
            self._log_event("Hardware tap accepted. HKDF key derived in RAM.")

            self.refresh_vault_listing()
            self._load_passwords_from_vault()

            # Auto-open the last selection, then fallback to local, then cloud.
            target = (
                self._last_selected_object
                or self._get_latest_local_object()
                or self._get_latest_cloud_object()
            )
            if target is not None:
                self._open_encrypted_file(target[0], target[1])
        except CryptoEngineError as exc:
            self._set_unlocked_state(False, message=str(exc), is_error=True)
            self._log_event(f"Hardware tap failed: {exc}")
            messagebox.showerror("Hardware Tap Failed", str(exc))
            logger.warning("Hardware tap failed: %s", exc)
        except Exception as exc:
            self._set_unlocked_state(False, message=f"Unexpected error: {exc}", is_error=True)
            self._log_event(f"Hardware tap failed: {exc}")
            messagebox.showerror("Hardware Tap Failed", str(exc))
            logger.exception("Hardware tap failed")

    def _auto_detect_port(self) -> None:
        try:
            import serial.tools.list_ports

            ports = list(serial.tools.list_ports.comports())
        except Exception as exc:
            messagebox.showerror("Auto Detect", f"Unable to scan serial ports: {exc}")
            return

        if not ports:
            messagebox.showerror("Auto Detect", "No serial devices detected.")
            return

        preferred = None
        for port in ports:
            description = (port.description or "").lower()
            if any(token in description for token in ("usb", "uart", "cp210", "ch340", "esp32")):
                preferred = port
                break

        selected = preferred or ports[0]
        self.port_entry.delete(0, "end")
        self.port_entry.insert(0, selected.device)
        self._set_status_message(f"Detected device on {selected.device}")
        self._log_event(f"Auto-detected serial port: {selected.device}")

    def _auto_tap_on_launch(self) -> None:
        if self.crypto.is_unlocked:
            return

        port = self.port_entry.get().strip()
        if not port:
            self._auto_detect_port()
            port = self.port_entry.get().strip()

        if not port:
            self._set_status_message("No COM port found for auto-tap.", is_error=True)
            return

        # Reuse the existing handshake flow.
        self._on_handshake_click()

    def _on_encrypt_click(self) -> None:
        if not self.crypto.is_unlocked:
            self._set_unlocked_state(False, message="Vault is locked. Hardware tap required.")
            return

        filepath = filedialog.askopenfilename(
            title="Select a PDF or TXT file",
            filetypes=[("PDF or Text", "*.pdf *.txt"), ("All Files", "*.*")],
        )
        if not filepath:
            return

        try:
            dest_path = self.crypto.encrypt_file(filepath)
            self._set_status_message(f"Saved locally: {dest_path.name}")
            self._log_event(f"File encrypted and sealed locally: {dest_path.name}")

            if self.cloud:
                self._set_status_message("Uploading to AWS...")
                self._log_event("Uploading encrypted file to AWS S3.")
                self.cloud.upload_vault_file(str(dest_path), dest_path.name, delete_local=False)
                self._set_status_message(f"Uploaded to AWS: {dest_path.name}")
                self._log_event(f"Uploaded to AWS: {dest_path.name}")

            self.refresh_vault_listing()
        except CloudManagerError as exc:
            self._set_status_message(str(exc), is_error=True)
            self._log_event(f"Cloud upload failed: {exc}")
            messagebox.showerror("Cloud Upload Failed", str(exc))
            logger.warning("Cloud upload failed: %s", exc)
        except CryptoEngineError as exc:
            self._set_status_message(str(exc), is_error=True)
            self._log_event(f"Encrypt failed: {exc}")
            logger.warning("Encrypt failed: %s", exc)
        except Exception as exc:
            self._set_status_message(f"Unexpected error: {exc}", is_error=True)
            self._log_event(f"Encrypt failed: {exc}")
            logger.exception("Encrypt failed")

    def refresh_vault_listing(self) -> None:
        for child in self.vault_list_frame.winfo_children():
            child.destroy()
        self._file_buttons.clear()

        items_added = 0

        enc_files = sorted(self.crypto.vault_dir.glob("*.enc"))
        for path in enc_files:
            if path.name == PASSWORD_STORE_FILENAME:
                continue
            label = f"LOCAL | {path.name}"
            self._add_vault_button(label, "local", str(path))
            items_added += 1

        if self.cloud:
            try:
                objects = self.cloud.get_vault_inventory()
            except CloudManagerError as exc:
                self._set_status_message(str(exc), is_error=True)
                messagebox.showerror("Cloud Error", str(exc))
                logger.warning("Cloud list failed: %s", exc)
            else:
                enc_objects = [name for name in objects if name.lower().endswith(".enc")]
                for name in enc_objects:
                    label = f"CLOUD | {name}"
                    self._add_vault_button(label, "cloud", name)
                    items_added += 1

        if items_added == 0:
            ctk.CTkLabel(
                self.vault_list_frame,
                text="No encrypted files yet.",
                font=FONTS["body"],
                text_color=COLORS["muted"],
            ).pack(fill="x", padx=10, pady=8)

    def _open_encrypted_file(self, source: str, identifier: str) -> None:
        if not self.crypto.is_unlocked:
            self._set_unlocked_state(False, message="Vault is locked. Hardware tap required.")
            return

        try:
            port = self._hardware_port or self.port_entry.get().strip()

            if source == "local":
                path = Path(identifier)
                if not path.is_file():
                    raise CryptoEngineError(f"Encrypted file not found: {path}")
                data = self.crypto.decrypt_to_memory(path, com_port=port)
                display_name = path.name
            else:
                if not self.cloud:
                    raise CloudManagerError("Cloud not configured.")

                self._set_status_message(f"Downloading from AWS: {identifier}")
                buffer = self.cloud.download_to_buffer(identifier)
                data = self.crypto.decrypt_blob(buffer.getvalue(), com_port=port)
                display_name = identifier

            self._last_selected_object = (source, identifier)
            self._display_bytes(data)
            self._set_status_message(f"Decrypted in memory: {display_name}")
            self._log_event(f"Decrypted in RAM: {display_name}")
        except CloudManagerError as exc:
            self._set_status_message(str(exc), is_error=True)
            self._log_event(f"Cloud download failed: {exc}")
            messagebox.showerror("Cloud Download Failed", str(exc))
            logger.warning("Cloud download failed: %s", exc)
        except CryptoEngineError as exc:
            self._set_status_message(str(exc), is_error=True)
            self._log_event(f"Decrypt failed: {exc}")
            logger.warning("Decrypt failed: %s", exc)
        except Exception as exc:
            self._set_status_message(f"Unexpected error: {exc}", is_error=True)
            self._log_event(f"Decrypt failed: {exc}")
            logger.exception("Decrypt failed")

    def _display_bytes(self, data: bytes) -> None:
        self._clear_viewer()

        # Inspect header bytes to decide how to render without touching disk.
        is_pdf = len(data) >= 4 and data[:4] == b"%PDF"
        if is_pdf:
            self._display_pdf(data)
        else:
            self._display_text(data)

        self._viewer_has_content = True

    def _display_text(self, data: bytes) -> None:
        # Decode with replacement to prevent crashes on non-UTF-8 content.
        text = data.decode("utf-8", errors="replace")

        textbox = ctk.CTkTextbox(
            self.viewer_content,
            wrap="word",
            fg_color=COLORS["panel_alt"],
            text_color=COLORS["text"],
            border_width=1,
            border_color=COLORS["border"],
            font=FONTS["body"],
        )
        textbox.insert("1.0", text)
        textbox.configure(state="disabled")
        textbox.grid(row=0, column=0, sticky="nsew")

    def _display_pdf(self, data: bytes) -> None:
        # Keep bytes in memory only; do not touch disk.
        self._pdf_bytes = data
        self._zoom_factor = max(self._zoom_factor, 0.5)
        self._render_pdf_pages()

    def _render_pdf_pages(self) -> None:
        # Clear previous images/widgets to avoid retaining plaintext in memory.
        for child in self.viewer_content.winfo_children():
            child.destroy()
        self._pdf_images.clear()
        self._pdf_scroll_frame = None
        gc.collect()

        if not self._pdf_bytes:
            return

        # Requirement: load PDF from memory buffer only.
        doc = fitz.open("pdf", self._pdf_bytes)
        self._pdf_scroll_frame = ctk.CTkScrollableFrame(
            self.viewer_content,
            fg_color=COLORS["panel_alt"],
            border_width=0,
        )
        self._pdf_scroll_frame.grid(row=0, column=0, sticky="nsew")
        self._pdf_scroll_frame.grid_columnconfigure(0, weight=1)

        for page_index in range(doc.page_count):
            page = doc.load_page(page_index)
            pixmap = page.get_pixmap(matrix=fitz.Matrix(self._zoom_factor, self._zoom_factor), alpha=False)
            image = Image.frombytes("RGB", (pixmap.width, pixmap.height), pixmap.samples)

            size = (pixmap.width, pixmap.height)
            page_image = ctk.CTkImage(light_image=image, dark_image=image, size=size)
            self._pdf_images.append(page_image)

            label = ctk.CTkLabel(self._pdf_scroll_frame, image=page_image, text="")
            label.pack(fill="x", padx=12, pady=(0, 12))

        doc.close()
        self._update_zoom_label()

    def _adjust_zoom(self, delta: float) -> None:
        if not self._pdf_bytes:
            return

        self._zoom_factor = max(0.5, min(4.0, self._zoom_factor + delta))
        # Re-render pages at the new zoom; old images are destroyed and GC'd.
        self._render_pdf_pages()

    def _update_zoom_label(self) -> None:
        percent = int(self._zoom_factor * 50)
        self.zoom_label.configure(text=f"{percent}%")

    def _on_panic(self) -> None:
        # Wipe key material and remove any decrypted content from the UI.
        self.crypto.lock_vault()
        self._hardware_port = ""
        self._set_unlocked_state(False, message="Vault locked. Key wiped from RAM.")
        self._log_event("Vault locked. RAM key wiped with memset.")

    def _on_close(self) -> None:
        # Always wipe key material when exiting.
        self.crypto.lock_vault()
        self._stop_hardware_monitor()
        self.destroy()

    def _get_latest_local_object(self) -> tuple[str, str] | None:
        enc_files = list(self.crypto.vault_dir.glob("*.enc"))
        if not enc_files:
            return None

        try:
            latest = max(enc_files, key=lambda path: path.stat().st_mtime)
        except OSError:
            latest = enc_files[0]

        return ("local", str(latest))

    def _get_latest_cloud_object(self) -> tuple[str, str] | None:
        if not self.cloud:
            return None

        try:
            objects = self.cloud.get_vault_inventory()
        except CloudManagerError:
            return None

        enc_objects = [name for name in objects if name.lower().endswith(".enc")]
        if not enc_objects:
            return None

        return ("cloud", enc_objects[-1])

    def _add_vault_button(self, label: str, source: str, identifier: str) -> None:
        button = ctk.CTkButton(
            self.vault_list_frame,
            text=label,
            anchor="w",
            fg_color=COLORS["panel"],
            hover_color=COLORS["panel_alt_hover"],
            text_color=COLORS["text"],
            command=lambda s=source, i=identifier: self._open_encrypted_file(s, i),
        )
        state = "normal" if self.crypto.is_unlocked else "disabled"
        button.configure(state=state)
        button.pack(fill="x", padx=8, pady=4)
        self._file_buttons.append(button)

    def _start_hardware_monitor(self) -> None:
        self._stop_hardware_monitor()
        self._hardware_monitor_id = self.after(1500, self._check_hardware_connection)

    def _stop_hardware_monitor(self) -> None:
        if self._hardware_monitor_id is not None:
            self.after_cancel(self._hardware_monitor_id)
            self._hardware_monitor_id = None

    def _check_hardware_connection(self) -> None:
        if not self.crypto.is_unlocked or not self._hardware_port:
            self._hardware_monitor_id = None
            return

        try:
            import serial.tools.list_ports

            ports = [port.device.upper() for port in serial.tools.list_ports.comports()]
            if self._hardware_port.upper() not in ports:
                raise RuntimeError("ESP32 disconnected")
        except Exception:
            self.crypto.lock_vault()
            self._hardware_port = ""
            self._set_unlocked_state(False, message="ESP32 disconnected. Key wiped from RAM.", is_error=True)
            self._log_event("ESP32 disconnected. Vault locked and RAM wiped.")
            self._hardware_monitor_id = None
            return

        self._hardware_monitor_id = self.after(1500, self._check_hardware_connection)
