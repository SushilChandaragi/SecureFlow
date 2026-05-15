"""SecureFlow GUI built with customtkinter."""
from __future__ import annotations

from pathlib import Path
import time
from tkinter import filedialog

import customtkinter as ctk
import fitz  # PyMuPDF
from PIL import Image

from crypto_engine import CryptoEngine, CryptoEngineError


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
        self._file_buttons: list[ctk.CTkButton] = []
        self._viewer_has_content = False

        self.title("SecureFlow Vault")
        self.geometry("1280x720")
        self.minsize(1024, 640)
        self.configure(fg_color=COLORS["bg"])

        self._build_layout()
        self.refresh_vault_listing()
        self._set_unlocked_state(self.crypto.is_unlocked, message="Vault is locked. Simulate hardware tap.")

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

        self.handshake_button = ctk.CTkButton(
            self.sidebar_frame,
            text="Simulate Hardware Tap",
            fg_color=COLORS["accent"],
            hover_color=COLORS["accent_hover"],
            text_color=COLORS["text"],
            command=self._on_handshake_click,
        )
        self.handshake_button.grid(row=1, column=0, sticky="ew", padx=16, pady=6)

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

        ctk.CTkLabel(
            self.sidebar_frame,
            text="Vault Browser",
            font=FONTS["section"],
            text_color=COLORS["muted"],
        ).grid(row=3, column=0, sticky="w", padx=16, pady=(18, 8))

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
        self.viewer_frame.grid_rowconfigure(0, weight=1)

        self.viewer_content = ctk.CTkFrame(self.viewer_frame, fg_color=COLORS["panel_alt"], corner_radius=10)
        self.viewer_content.grid(row=0, column=0, sticky="nsew", padx=12, pady=12)
        self.viewer_content.grid_columnconfigure(0, weight=1)
        self.viewer_content.grid_rowconfigure(0, weight=1)

    def _set_status_message(self, message: str, is_error: bool = False) -> None:
        color = COLORS["danger"] if is_error else COLORS["muted"]
        self.status_message.configure(text=message, text_color=color)

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
        self._viewer_has_content = False

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
            self._set_badge_state(self.badge_key, False)
            self._set_badge_state(self.badge_plaintext, False)
            self._set_badge_state(self.badge_aes, False)
            self._set_badge_state(self.badge_hkdf, False)
            self._clear_viewer("Vault is locked. No data in memory.")

        if message:
            self._set_status_message(message, is_error=is_error)

    def _on_handshake_click(self) -> None:
        try:
            self.crypto.mock_handshake()
            self._set_unlocked_state(True, message="Hardware tap accepted. Session unlocked.")
            self._log_event("Hardware tap accepted. HKDF key derived in RAM.")
        except CryptoEngineError as exc:
            self._set_unlocked_state(False, message=str(exc), is_error=True)
            self._log_event(f"Hardware tap failed: {exc}")
        except Exception as exc:
            self._set_unlocked_state(False, message=f"Unexpected error: {exc}", is_error=True)
            self._log_event(f"Hardware tap failed: {exc}")

    def _on_encrypt_click(self) -> None:
        if not self.crypto.is_unlocked:
            self._set_unlocked_state(False, message="Vault is locked. Simulate hardware tap.")
            return

        filepath = filedialog.askopenfilename(
            title="Select a PDF or TXT file",
            filetypes=[("PDF or Text", "*.pdf *.txt"), ("All Files", "*.*")],
        )
        if not filepath:
            return

        try:
            dest_path = self.crypto.encrypt_file(filepath)
            self._set_status_message(f"Encrypted to: {dest_path.name}")
            self._log_event(f"File encrypted and sealed: {dest_path.name}")
            self.refresh_vault_listing()
        except CryptoEngineError as exc:
            self._set_status_message(str(exc), is_error=True)
            self._log_event(f"Encrypt failed: {exc}")
        except Exception as exc:
            self._set_status_message(f"Unexpected error: {exc}", is_error=True)
            self._log_event(f"Encrypt failed: {exc}")

    def refresh_vault_listing(self) -> None:
        for child in self.vault_list_frame.winfo_children():
            child.destroy()
        self._file_buttons.clear()

        enc_files = sorted(self.crypto.vault_dir.glob("*.enc"))
        if not enc_files:
            ctk.CTkLabel(
                self.vault_list_frame,
                text="No encrypted files yet.",
                font=FONTS["body"],
                text_color=COLORS["muted"],
            ).pack(fill="x", padx=10, pady=8)
            return

        for path in enc_files:
            button = ctk.CTkButton(
                self.vault_list_frame,
                text=path.name,
                anchor="w",
                fg_color=COLORS["panel"],
                hover_color=COLORS["panel_alt_hover"],
                text_color=COLORS["text"],
                command=lambda p=path: self._open_encrypted_file(p),
            )
            state = "normal" if self.crypto.is_unlocked else "disabled"
            button.configure(state=state)
            button.pack(fill="x", padx=8, pady=4)
            self._file_buttons.append(button)

    def _open_encrypted_file(self, path: Path) -> None:
        if not self.crypto.is_unlocked:
            self._set_unlocked_state(False, message="Vault is locked. Simulate hardware tap.")
            return

        try:
            data = self.crypto.decrypt_to_memory(path)
            self._display_bytes(data)
            self._set_status_message(f"Decrypted in memory: {path.name}")
            self._log_event(f"Decrypted in RAM: {path.name}")
        except CryptoEngineError as exc:
            self._set_status_message(str(exc), is_error=True)
            self._log_event(f"Decrypt failed: {exc}")
        except Exception as exc:
            self._set_status_message(f"Unexpected error: {exc}", is_error=True)
            self._log_event(f"Decrypt failed: {exc}")

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
        # PyMuPDF accepts bytes directly, keeping plaintext in memory only.
        doc = fitz.open(stream=data, filetype="pdf")
        page = doc.load_page(0)

        pixmap = page.get_pixmap(matrix=fitz.Matrix(2, 2), alpha=False)
        image = Image.frombytes("RGB", (pixmap.width, pixmap.height), pixmap.samples)

        self.update_idletasks()
        max_width = max(self.viewer_content.winfo_width() - 24, 200)
        scale = min(1.0, max_width / pixmap.width)
        new_size = (int(pixmap.width * scale), int(pixmap.height * scale))
        resample = getattr(Image, "Resampling", Image).LANCZOS
        image = image.resize(new_size, resample)

        self._pdf_image = ctk.CTkImage(light_image=image, dark_image=image, size=new_size)
        label = ctk.CTkLabel(self.viewer_content, image=self._pdf_image, text="")
        label.grid(row=0, column=0, sticky="nsew")

    def _on_panic(self) -> None:
        # Wipe key material and remove any decrypted content from the UI.
        self.crypto.lock_vault()
        self._set_unlocked_state(False, message="Vault locked. Key wiped from RAM.")
        self._log_event("Vault locked. RAM key wiped with memset.")

    def _on_close(self) -> None:
        # Always wipe key material when exiting.
        self.crypto.lock_vault()
        self.destroy()
