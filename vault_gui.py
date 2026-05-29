"""SecureFlow GUI built with customtkinter."""
from __future__ import annotations

from pathlib import Path
import json
import time
import gc
import logging
import uuid
from tkinter import filedialog, messagebox, TclError

import queue
import threading
import customtkinter as ctk
import fitz  # PyMuPDF
import pyotp
import pandas as pd
import matplotlib.pyplot as plt
from matplotlib.backends.backend_tkagg import FigureCanvasTkAgg
from PIL import Image, ImageTk
import qrcode

from cloud_manager import CloudManager, CloudManagerError
from crypto_engine import CryptoEngine, CryptoEngineError


logger = logging.getLogger(__name__)


AUTH_STORE_FILENAME = "auth_keys.enc"
PASSWORD_STORE_FILENAME = "passwords.enc"

ML_MONITOR_INTERVAL_MS = 1500
ML_BASELINE_MIN_SAMPLES = 120
ML_ANOMALY_THRESHOLD = 0.6
ML_ANOMALY_STREAK = 3


COLORS = {
    "bg":                 "#09090B",
    "panel":              "#111113",
    "panel_alt":          "#18181B",
    "panel_alt_hover":    "#27272A",
    "text":               "#FAFAFA",
    "muted":              "#A1A1AA",
    "accent":             "#818CF8",
    "accent_hover":       "#6366F1",
    "success":            "#34D399",
    "danger":             "#F87171",
    "danger_hover":       "#DC2626",
    "border":             "#3F3F46",
    "badge_bg":           "#1E1B4B",
    "badge_inactive":     "#18181B",
    "badge_text_inactive":"#52525B",
}

FONTS = {
    "title":   ("Segoe UI Variable", 20, "bold"),
    "section": ("Segoe UI Variable", 14, "bold"),
    "status":  ("Segoe UI Variable", 16, "bold"),
    "body":    ("Segoe UI Variable", 13),
    "mono":    ("Consolas", 13),
    "badge":   ("Consolas", 10, "bold"),
    "totp":    ("Consolas", 42, "bold"),
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
        self._password_rows: list[ctk.CTkFrame] = []
        self._totp_store: dict[str, dict[str, object]] = {}
        self._totp_rows: list[ctk.CTkFrame] = []
        self._totp_selected_id: str | None = None
        self._totp_secret: str | None = None
        self._totp_issuer = ""
        self._totp_account = ""
        self._totp_period = 30
        self._totp_timer_id: str | None = None
        self._totp_last_step = -1
        self._ml_canvas: FigureCanvasTkAgg | None = None
        self._ml_monitor_id: str | None = None
        self._ml_last_file: Path | None = None
        self._ml_last_row = 0
        self._ml_baseline: list[list[float]] = []
        self._ml_model = None
        self._ml_anomaly_streak = 0
        self._is_closing = False

        # Thread-safe queue: bg threads post here, main thread drains every 50ms
        self._ui_queue: queue.Queue = queue.Queue()
        self._queue_pump_id = None

        self.title("SecureFlow Vault")
        self.geometry("1280x720")
        self.minsize(1024, 640)
        self.configure(fg_color=COLORS["bg"])

        self._build_layout()
        self._update_totp_status()
        self._set_unlocked_state(self.crypto.is_unlocked,
                                  message="Vault is locked. Hardware tap required.")

        self._process_ui_queue()  # start 50ms pump

        self._run_in_thread(
            self._init_cloud_bg,
            on_done=lambda r: (setattr(self, "cloud", r), self.refresh_vault_listing()),
            on_error=lambda e: (setattr(self, "cloud", None),
                                self.refresh_vault_listing(),
                                self._set_status_message(str(e), is_error=True))
        )

        self._schedule_after(300, self._auto_tap_on_launch)
        self._start_totp_loop()
        self._start_ml_monitor()

        self.protocol("WM_DELETE_WINDOW", self._on_close)

    # ------------------------------------------------------------------
    # Threading infrastructure
    # ------------------------------------------------------------------

    def _run_in_thread(self, fn, on_done=None, on_error=None) -> None:
        """Run *fn* in a daemon thread; deliver result via _ui_queue."""
        def _worker():
            try:
                result = fn()
                if on_done:
                    self._ui_queue.put(("__done__", on_done, result))
            except Exception as exc:  # noqa: BLE001
                if on_error:
                    self._ui_queue.put(("__error__", on_error, exc))
                else:
                    def _log(e, _x=exc):
                        if "Hardware port" not in str(_x):
                            logger.error("Thread error: %s", _x)
                    self._ui_queue.put(("__error__", _log, exc))
        threading.Thread(target=_worker, daemon=True).start()

    def _process_ui_queue(self) -> None:
        """Drain _ui_queue every 50 ms on the main thread."""
        if self._is_closing:
            return
        try:
            while True:
                kind, cb, payload = self._ui_queue.get_nowait()
                try:
                    cb(payload)
                except Exception as exc:  # noqa: BLE001
                    logger.exception("Queue callback error: %s", exc)
        except queue.Empty:
            pass
        self._queue_pump_id = self._schedule_after(50, self._process_ui_queue)

    # ------------------------------------------------------------------
    # Layout
    # ------------------------------------------------------------------

    def _build_layout(self) -> None:
        self.grid_columnconfigure(0, weight=0)
        self.grid_columnconfigure(1, weight=1)
        self.grid_rowconfigure(0, weight=1)

        self.sidebar_frame = ctk.CTkFrame(self, fg_color=COLORS["panel"], corner_radius=14)
        self.sidebar_frame.grid(row=0, column=0, sticky="nsew", padx=(16, 8), pady=16)
        self.sidebar_frame.grid_columnconfigure(0, weight=1)
        self.sidebar_frame.grid_rowconfigure(5, weight=1)

        ctk.CTkLabel(
            self.sidebar_frame,
            text="SecureFlow",
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
        self.encrypt_button.grid(row=3, column=0, sticky="ew", padx=16, pady=6)

        self.upload_cloud_button = ctk.CTkButton(
            self.sidebar_frame,
            text="☁ Upload to Cloud",
            fg_color=COLORS["panel_alt"],
            hover_color=COLORS["panel_alt_hover"],
            text_color=COLORS["text"],
            border_width=1,
            border_color=COLORS["border"],
            command=self._on_upload_to_cloud,
        )
        self.upload_cloud_button.grid(row=4, column=0, sticky="ew", padx=16, pady=6)

        self.pair_button = ctk.CTkButton(
            self.sidebar_frame,
            text="📱 Pair Mobile Companion",
            fg_color=COLORS["panel_alt"],
            hover_color=COLORS["panel_alt_hover"],
            text_color=COLORS["text"],
            border_width=1,
            border_color=COLORS["border"],
            command=self._on_pair_click,
        )
        self.pair_button.grid(row=5, column=0, sticky="ew", padx=16, pady=6)

        ctk.CTkFrame(self.sidebar_frame, fg_color="transparent").grid(row=6, column=0, sticky="nsew")

        self.panic_button = ctk.CTkButton(
            self.sidebar_frame,
            text="🔒 LOCK VAULT & WIPE RAM",
            fg_color=COLORS["danger"],
            hover_color=COLORS["danger_hover"],
            text_color=COLORS["text"],
            command=self._on_panic,
        )
        self.panic_button.grid(row=7, column=0, sticky="ew", padx=16, pady=(0, 16))

        self.main_frame = ctk.CTkFrame(self, fg_color=COLORS["panel_alt"], corner_radius=14)
        self.main_frame.grid(row=0, column=1, sticky="nsew", padx=(8, 16), pady=16)
        self.main_frame.grid_columnconfigure(0, weight=1)
        self.main_frame.grid_rowconfigure(0, weight=1)

        self.tabview = ctk.CTkTabview(
            self.main_frame,
            fg_color=COLORS["panel_alt"],
            segmented_button_fg_color=COLORS["panel"],
            segmented_button_selected_color=COLORS["panel_alt"],
            segmented_button_selected_hover_color=COLORS["panel_alt_hover"],
            text_color=COLORS["text"],
            text_color_disabled=COLORS["muted"],
        )
        self.tabview.grid(row=0, column=0, sticky="nsew", padx=16, pady=16)

        self.files_tab = self.tabview.add("Files")
        self.passwords_tab = self.tabview.add("Passwords")
        self.auth_tab = self.tabview.add("Authenticator")
        self.ml_tab = self.tabview.add("ML Insights")

        self._build_files_tab()
        self._build_passwords_tab()
        self._build_authenticator_tab()
        self._build_ml_tab()

    def _build_files_tab(self) -> None:
        self.files_tab.grid_columnconfigure(0, weight=1)
        self.files_tab.grid_rowconfigure(1, weight=1)

        self.status_frame = ctk.CTkFrame(self.files_tab, fg_color=COLORS["panel"], corner_radius=12)
        self.status_frame.grid(row=0, column=0, sticky="ew", padx=8, pady=(8, 4))
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
            height=72,
            fg_color=COLORS["panel_alt"],
            text_color=COLORS["text"],
            border_width=1,
            border_color=COLORS["border"],
            font=FONTS["body"],
        )
        self.timeline_box.grid(row=4, column=0, sticky="ew", padx=16, pady=(0, 12))
        self.timeline_box.configure(state="disabled")

        self.files_body = ctk.CTkFrame(self.files_tab, fg_color="transparent")
        self.files_body.grid(row=1, column=0, sticky="nsew")
        self.files_body.grid_columnconfigure(0, weight=0)
        self.files_body.grid_columnconfigure(1, weight=1)
        self.files_body.grid_rowconfigure(0, weight=1)

        self.file_panel = ctk.CTkFrame(self.files_body, fg_color=COLORS["panel"], corner_radius=12)
        self.file_panel.grid(row=0, column=0, sticky="nsew", padx=(16, 12), pady=(0, 16))
        self.file_panel.grid_columnconfigure(0, weight=1)
        self.file_panel.grid_rowconfigure(1, weight=1)

        self.vault_header_row = ctk.CTkFrame(self.file_panel, fg_color="transparent")
        self.vault_header_row.grid(row=0, column=0, sticky="ew", padx=12, pady=(12, 8))
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
            self.file_panel,
            fg_color=COLORS["panel_alt"],
            border_width=1,
            border_color=COLORS["border"],
        )
        self.vault_list_frame.grid(row=1, column=0, sticky="nsew", padx=12, pady=(0, 12))

        self.viewer_frame = ctk.CTkFrame(self.files_body, fg_color=COLORS["panel"], corner_radius=12)
        self.viewer_frame.grid(row=0, column=1, sticky="nsew", padx=(0, 16), pady=(0, 16))
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

    def _build_passwords_tab(self) -> None:
        self.passwords_tab.grid_columnconfigure(0, weight=1)
        self.passwords_tab.grid_rowconfigure(1, weight=1)

        form_frame = ctk.CTkFrame(self.passwords_tab, fg_color=COLORS["panel"], corner_radius=12)
        form_frame.grid(row=0, column=0, sticky="ew", padx=16, pady=(16, 10))
        form_frame.grid_columnconfigure(3, weight=1)

        self.website_entry = ctk.CTkEntry(
            form_frame,
            placeholder_text="Website",
            fg_color=COLORS["panel_alt"],
            text_color=COLORS["text"],
            border_color=COLORS["border"],
            font=FONTS["mono"],
        )
        self.website_entry.grid(row=0, column=0, padx=12, pady=12, sticky="ew")

        self.username_entry = ctk.CTkEntry(
            form_frame,
            placeholder_text="Username",
            fg_color=COLORS["panel_alt"],
            text_color=COLORS["text"],
            border_color=COLORS["border"],
            font=FONTS["mono"],
        )
        self.username_entry.grid(row=0, column=1, padx=12, pady=12, sticky="ew")

        self.password_entry = ctk.CTkEntry(
            form_frame,
            placeholder_text="Password",
            show="*",
            fg_color=COLORS["panel_alt"],
            text_color=COLORS["text"],
            border_color=COLORS["border"],
            font=FONTS["mono"],
        )
        self.password_entry.grid(row=0, column=2, padx=12, pady=12, sticky="ew")

        add_button = ctk.CTkButton(
            form_frame,
            text="Add Password",
            fg_color=COLORS["accent"],
            hover_color=COLORS["accent_hover"],
            text_color=COLORS["text"],
            command=self._on_add_password,
        )
        add_button.grid(row=0, column=3, padx=12, pady=12, sticky="e")

        self.password_list_frame = ctk.CTkScrollableFrame(
            self.passwords_tab,
            fg_color=COLORS["panel"],
            border_width=1,
            border_color=COLORS["border"],
        )
        self.password_list_frame.grid(row=1, column=0, sticky="nsew", padx=16, pady=(0, 16))
        self.password_list_frame.grid_columnconfigure(0, weight=1)

        header = ctk.CTkFrame(self.password_list_frame, fg_color="transparent")
        header.pack(fill="x", padx=12, pady=(12, 6))
        ctk.CTkLabel(header, text="Website", font=FONTS["mono"], text_color=COLORS["muted"]).grid(
            row=0, column=0, sticky="w"
        )
        ctk.CTkLabel(header, text="Username", font=FONTS["mono"], text_color=COLORS["muted"]).grid(
            row=0, column=1, sticky="w", padx=(24, 0)
        )
        ctk.CTkLabel(header, text="Password", font=FONTS["mono"], text_color=COLORS["muted"]).grid(
            row=0, column=2, sticky="w", padx=(24, 0)
        )
        ctk.CTkLabel(header, text="Reveal", font=FONTS["mono"], text_color=COLORS["muted"]).grid(
            row=0, column=3, sticky="w", padx=(24, 0)
        )

    def _build_authenticator_tab(self) -> None:
        self.auth_tab.grid_columnconfigure(0, weight=1)
        self.auth_tab.grid_rowconfigure(1, weight=1)

        auth_frame = ctk.CTkFrame(self.auth_tab, fg_color=COLORS["panel"], corner_radius=12)
        auth_frame.grid(row=0, column=0, sticky="ew", padx=16, pady=(16, 10))
        auth_frame.grid_columnconfigure(0, weight=1)
        auth_frame.grid_columnconfigure(1, weight=0)

        ctk.CTkLabel(
            auth_frame,
            text="TOTP Authenticator",
            font=FONTS["section"],
            text_color=COLORS["muted"],
        ).grid(row=0, column=0, sticky="w", padx=12, pady=(12, 6))

        self.totp_label_entry = ctk.CTkEntry(
            auth_frame,
            placeholder_text="Label / Website (optional)",
            fg_color=COLORS["panel_alt"],
            text_color=COLORS["text"],
            border_color=COLORS["border"],
            font=FONTS["mono"],
        )
        self.totp_label_entry.grid(row=1, column=0, sticky="ew", padx=12, pady=(0, 8))

        self.totp_secret_entry = ctk.CTkEntry(
            auth_frame,
            placeholder_text="Paste Base32 secret or otpauth:// URI",
            fg_color=COLORS["panel_alt"],
            text_color=COLORS["text"],
            border_color=COLORS["border"],
            font=FONTS["mono"],
        )
        self.totp_secret_entry.grid(row=2, column=0, sticky="ew", padx=12, pady=(0, 12))

        controls = ctk.CTkFrame(auth_frame, fg_color="transparent")
        controls.grid(row=2, column=1, padx=(0, 12), pady=(0, 12), sticky="e")

        set_button = ctk.CTkButton(
            controls,
            text="Add Key",
            width=100,
            fg_color=COLORS["accent"],
            hover_color=COLORS["accent_hover"],
            text_color=COLORS["text"],
            command=self._apply_totp_secret,
        )
        set_button.grid(row=0, column=0, padx=(0, 8))

        clear_button = ctk.CTkButton(
            controls,
            text="Remove",
            width=80,
            fg_color=COLORS["panel_alt"],
            hover_color=COLORS["panel_alt_hover"],
            text_color=COLORS["text"],
            border_width=1,
            border_color=COLORS["border"],
            command=self._clear_totp_secret,
        )
        clear_button.grid(row=0, column=1)

        self.totp_status_label = ctk.CTkLabel(
            auth_frame,
            text="No TOTP keys stored.",
            font=FONTS["mono"],
            text_color=COLORS["muted"],
        )
        self.totp_status_label.grid(row=3, column=0, columnspan=2, sticky="w", padx=12, pady=(0, 12))

        self.auth_body = ctk.CTkFrame(self.auth_tab, fg_color="transparent")
        self.auth_body.grid(row=1, column=0, sticky="nsew", padx=16, pady=(0, 16))
        self.auth_body.grid_columnconfigure(0, weight=1)
        self.auth_body.grid_columnconfigure(1, weight=1)
        self.auth_body.grid_rowconfigure(0, weight=1)

        self.totp_list_frame = ctk.CTkScrollableFrame(
            self.auth_body,
            fg_color=COLORS["panel"],
            border_width=1,
            border_color=COLORS["border"],
        )
        self.totp_list_frame.grid(row=0, column=0, sticky="nsew", padx=(0, 12))
        self.totp_list_frame.grid_columnconfigure(0, weight=1)

        self.totp_detail_frame = ctk.CTkFrame(self.auth_body, fg_color=COLORS["panel"], corner_radius=12)
        self.totp_detail_frame.grid(row=0, column=1, sticky="nsew")
        self.totp_detail_frame.grid_columnconfigure(0, weight=1)

        self.totp_detail_title = ctk.CTkLabel(
            self.totp_detail_frame,
            text="Selected Key",
            font=FONTS["section"],
            text_color=COLORS["muted"],
        )
        self.totp_detail_title.grid(row=0, column=0, sticky="w", padx=16, pady=(16, 6))

        self.totp_detail_name = ctk.CTkLabel(
            self.totp_detail_frame,
            text="No key selected",
            font=FONTS["body"],
            text_color=COLORS["text"],
        )
        self.totp_detail_name.grid(row=1, column=0, sticky="w", padx=16)

        self.totp_detail_meta = ctk.CTkLabel(
            self.totp_detail_frame,
            text="",
            font=FONTS["mono"],
            text_color=COLORS["muted"],
        )
        self.totp_detail_meta.grid(row=2, column=0, sticky="w", padx=16, pady=(2, 16))

        self.totp_label = ctk.CTkLabel(
            self.totp_detail_frame,
            text="SELECT KEY",
            font=FONTS["totp"],
            text_color=COLORS["text"],
        )
        self.totp_label.grid(row=3, column=0, pady=(10, 16))

        self.totp_progress = ctk.CTkProgressBar(
            self.totp_detail_frame,
            width=320,
            height=12,
            fg_color=COLORS["panel_alt"],
            progress_color=COLORS["accent"],
        )
        self.totp_progress.grid(row=4, column=0, pady=(0, 24))
        self.totp_progress.set(0.0)

        self.totp_remove_button = ctk.CTkButton(
            self.totp_detail_frame,
            text="Remove Selected Key",
            fg_color=COLORS["panel_alt"],
            hover_color=COLORS["panel_alt_hover"],
            text_color=COLORS["text"],
            border_width=1,
            border_color=COLORS["border"],
            command=self._clear_totp_secret,
        )
        self.totp_remove_button.grid(row=5, column=0, padx=16, pady=(0, 16), sticky="ew")

        self._render_totp_rows()

    def _build_ml_tab(self) -> None:
        self.ml_tab.grid_columnconfigure(0, weight=1)
        self.ml_tab.grid_rowconfigure(1, weight=1)

        header = ctk.CTkFrame(self.ml_tab, fg_color=COLORS["panel"], corner_radius=12)
        header.grid(row=0, column=0, sticky="ew", padx=16, pady=(16, 10))
        header.grid_columnconfigure(0, weight=1)

        ctk.CTkLabel(
            header,
            text="ML Insights",
            font=FONTS["section"],
            text_color=COLORS["muted"],
        ).grid(row=0, column=0, sticky="w", padx=12, pady=12)

        refresh_button = ctk.CTkButton(
            header,
            text="Refresh Data",
            width=140,
            fg_color=COLORS["panel_alt"],
            hover_color=COLORS["panel_alt_hover"],
            text_color=COLORS["text"],
            border_width=1,
            border_color=COLORS["border"],
            command=self._refresh_ml_chart,
        )
        refresh_button.grid(row=0, column=1, sticky="e", padx=12, pady=12)

        self.ml_chart_container = ctk.CTkFrame(self.ml_tab, fg_color=COLORS["panel"], corner_radius=12)
        self.ml_chart_container.grid(row=1, column=0, sticky="nsew", padx=16, pady=(0, 16))
        self.ml_chart_container.grid_columnconfigure(0, weight=1)
        self.ml_chart_container.grid_rowconfigure(0, weight=1)

        self._refresh_ml_chart()

    def _set_status_message(self, message: str, is_error: bool = False) -> None:
        color = COLORS["danger"] if is_error else COLORS["muted"]
        self.status_message.configure(text=message, text_color=color)

    def _init_cloud_bg(self):
        """Called in background thread. Returns a CloudManager instance."""
        return CloudManager()

    def _on_add_password(self) -> None:
        website = self.website_entry.get().strip()
        username = self.username_entry.get().strip()
        password = self.password_entry.get().strip()

        if not website or not username or not password:
            messagebox.showerror("Passwords", "Website, username, and password are required.")
            return

        key = f"{website}|{username}"
        self._password_store[key] = {
            "website": website,
            "username": username,
            "password": password,
        }

        self.website_entry.delete(0, "end")
        self.username_entry.delete(0, "end")
        self.password_entry.delete(0, "end")

        self._render_password_rows()
        self._save_passwords_to_vault()

    def _render_password_rows(self) -> None:
        for row in self._password_rows:
            row.destroy()
        self._password_rows.clear()

        for entry in self._password_store.values():
            row = ctk.CTkFrame(self.password_list_frame, fg_color="transparent")
            row.pack(fill="x", padx=12, pady=6)

            ctk.CTkLabel(row, text=entry["website"], font=FONTS["mono"], text_color=COLORS["text"]).grid(
                row=0, column=0, sticky="w"
            )
            ctk.CTkLabel(row, text=entry["username"], font=FONTS["mono"], text_color=COLORS["text"]).grid(
                row=0, column=1, sticky="w", padx=(24, 0)
            )

            password_label = ctk.CTkLabel(
                row,
                text="******",
                font=FONTS["mono"],
                text_color=COLORS["text"],
            )
            password_label.grid(row=0, column=2, sticky="w", padx=(24, 0))

            state = {"visible": False}

            def toggle() -> None:
                state["visible"] = not state["visible"]
                if state["visible"]:
                    password_label.configure(text=entry["password"])
                    reveal_button.configure(text="Hide")
                else:
                    password_label.configure(text="******")
                    reveal_button.configure(text="Reveal")

            reveal_button = ctk.CTkButton(
                row,
                text="Reveal",
                width=80,
                fg_color=COLORS["panel_alt"],
                hover_color=COLORS["panel_alt_hover"],
                text_color=COLORS["text"],
                border_width=1,
                border_color=COLORS["border"],
                command=toggle,
            )
            reveal_button.grid(row=0, column=3, sticky="w", padx=(24, 0))

            self._password_rows.append(row)

    def _load_passwords_from_vault(self) -> None:
        if not self.crypto.is_unlocked:
            return

        vault_path = self.crypto.vault_dir / PASSWORD_STORE_FILENAME
        if not vault_path.is_file():
            self._password_store.clear()
            self._render_password_rows()
            return

        port = self._hardware_port or self.port_entry.get().strip()
        try:
            encrypted_blob = vault_path.read_bytes()
            raw = self.crypto.decrypt_blob(encrypted_blob, com_port=port)
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
                self._password_store[key] = {
                    "website": website,
                    "username": username,
                    "password": password,
                }
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

        self._render_password_rows()

    def _save_passwords_to_vault(self) -> None:
        if not self.crypto.is_unlocked:
            return

        vault_path = self.crypto.vault_dir / PASSWORD_STORE_FILENAME
        if not self._password_store:
            if vault_path.exists():
                vault_path.unlink()
            return

        payload = []
        for entry in self._password_store.values():
            payload.append(
                {
                    "website": entry.get("website", ""),
                    "username": entry.get("username", ""),
                    "password": entry.get("password", ""),
                }
            )

        blob = json.dumps(payload, ensure_ascii=True).encode("utf-8")
        try:
            encrypted_blob = self.crypto.encrypt_bytes(blob)
            vault_path.write_bytes(encrypted_blob)
        except CryptoEngineError as exc:
            self._set_status_message(str(exc), is_error=True)
            self._log_event(f"Failed to save passwords: {exc}")
            logger.warning("Failed to save passwords: %s", exc)


    def _clear_passwords_memory(self) -> None:
        self._password_store.clear()
        self._render_password_rows()

    def _update_totp_status(self) -> None:
        if not self.crypto.is_unlocked:
            self.totp_status_label.configure(text="Unlock the vault to view authenticator keys.")
            return
        count = len(self._totp_store)
        if count == 0:
            text = "No TOTP keys stored."
        elif count == 1:
            text = "1 TOTP key stored."
        else:
            text = f"{count} TOTP keys stored."
        self.totp_status_label.configure(text=text)

    def _render_totp_rows(self) -> None:
        for child in self.totp_list_frame.winfo_children():
            child.destroy()
        self._totp_rows.clear()

        if not self.crypto.is_unlocked:
            ctk.CTkLabel(
                self.totp_list_frame,
                text="Unlock the vault to view keys.",
                font=FONTS["mono"],
                text_color=COLORS["muted"],
            ).pack(fill="x", padx=12, pady=12)
            return

        if not self._totp_store:
            ctk.CTkLabel(
                self.totp_list_frame,
                text="No keys yet.",
                font=FONTS["mono"],
                text_color=COLORS["muted"],
            ).pack(fill="x", padx=12, pady=12)
            return

        entries = sorted(
            self._totp_store.items(),
            key=lambda item: str(item[1].get("label", "")).lower(),
        )
        for key_id, entry in entries:
            label = str(entry.get("label") or "Unnamed key")
            issuer = str(entry.get("issuer") or "")
            account = str(entry.get("account") or "")
            meta = " | ".join([part for part in (issuer, account) if part])
            is_selected = key_id == self._totp_selected_id

            row = ctk.CTkFrame(
                self.totp_list_frame,
                fg_color=COLORS["panel_alt"] if is_selected else "transparent",
                corner_radius=8,
            )
            row.pack(fill="x", padx=12, pady=6)
            row.grid_columnconfigure(0, weight=1)

            ctk.CTkLabel(
                row,
                text=label,
                font=FONTS["body"],
                text_color=COLORS["text"],
            ).grid(row=0, column=0, sticky="w", padx=8, pady=(8, 2))

            ctk.CTkLabel(
                row,
                text=meta,
                font=FONTS["mono"],
                text_color=COLORS["muted"],
            ).grid(row=1, column=0, sticky="w", padx=8, pady=(0, 8))

            ctk.CTkButton(
                row,
                text="View",
                width=70,
                fg_color=COLORS["panel_alt"],
                hover_color=COLORS["panel_alt_hover"],
                text_color=COLORS["text"],
                border_width=1,
                border_color=COLORS["border"],
                command=lambda k=key_id: self._select_totp_key(k),
            ).grid(row=0, column=1, rowspan=2, padx=8, pady=8, sticky="e")

            self._totp_rows.append(row)

    def _select_totp_key(self, key_id: str) -> None:
        entry = self._totp_store.get(key_id)
        if not entry:
            return

        self._totp_selected_id = key_id
        self._totp_secret = str(entry.get("secret") or "")
        self._totp_issuer = str(entry.get("issuer") or "")
        self._totp_account = str(entry.get("account") or "")
        self._totp_period = int(entry.get("period") or 30)
        self._totp_last_step = -1

        label = str(entry.get("label") or "Unnamed key")
        meta = " | ".join([part for part in (self._totp_issuer, self._totp_account) if part])
        self.totp_detail_name.configure(text=label)
        self.totp_detail_meta.configure(text=meta)

        self._render_totp_rows()
        self._update_totp()

    def _clear_totp_memory(self) -> None:
        self._totp_store.clear()
        self._totp_selected_id = None
        self._totp_secret = None
        self._totp_issuer = ""
        self._totp_account = ""
        self._totp_period = 30
        self._totp_last_step = -1

        self.totp_detail_name.configure(text="No key selected")
        self.totp_detail_meta.configure(text="")
        self.totp_label.configure(text="SELECT KEY")
        self.totp_progress.set(0.0)

        self._render_totp_rows()
        self._update_totp_status()

    def _save_totp_store_to_vault(self) -> None:
        if not self.crypto.is_unlocked:
            return

        vault_path = self.crypto.vault_dir / AUTH_STORE_FILENAME
        if not self._totp_store:
            if vault_path.exists():
                vault_path.unlink()
            return

        payload = []
        for key_id, entry in self._totp_store.items():
            payload.append(
                {
                    "id": key_id,
                    "label": entry.get("label", ""),
                    "issuer": entry.get("issuer", ""),
                    "account": entry.get("account", ""),
                    "secret": entry.get("secret", ""),
                    "period": int(entry.get("period", 30)),
                }
            )

        blob = json.dumps(payload, ensure_ascii=True).encode("utf-8")
        try:
            self.crypto.encrypt_bytes_to_vault(blob, AUTH_STORE_FILENAME, overwrite=True)
        except CryptoEngineError as exc:
            self._set_status_message(str(exc), is_error=True)
            self._log_event(f"Failed to save authenticator keys: {exc}")
            logger.warning("Failed to save authenticator keys: %s", exc)

    def _load_totp_store_from_vault(self) -> None:
        if not self.crypto.is_unlocked:
            return

        vault_path = self.crypto.vault_dir / AUTH_STORE_FILENAME
        if not vault_path.is_file():
            self._update_totp_status()
            return

        port = self._hardware_port or self.port_entry.get().strip()
        try:
            raw = self.crypto.decrypt_to_memory(vault_path, com_port=port)
            data = json.loads(raw.decode("utf-8"))
        except Exception as exc:
            self._set_status_message("Failed to load authenticator keys.", is_error=True)
            self._log_event(f"Failed to load authenticator keys: {exc}")
            logger.warning("Failed to load authenticator keys: %s", exc)
            return

        self._totp_store.clear()
        if isinstance(data, list):
            for entry in data:
                if not isinstance(entry, dict):
                    continue
                secret = entry.get("secret")
                if not secret:
                    continue
                key_id = entry.get("id") or uuid.uuid4().hex
                self._totp_store[key_id] = {
                    "label": entry.get("label", ""),
                    "issuer": entry.get("issuer", ""),
                    "account": entry.get("account", ""),
                    "secret": secret,
                    "period": int(entry.get("period", 30)),
                }

        if self._totp_store:
            first_id = next(iter(self._totp_store))
            self._select_totp_key(first_id)
        else:
            self._clear_totp_memory()

        self._update_totp_status()

    def _start_ml_monitor(self) -> None:
        if self._ml_monitor_id is not None:
            self.after_cancel(self._ml_monitor_id)
        self._ml_monitor_id = self._schedule_after(ML_MONITOR_INTERVAL_MS, self._monitor_ml_anomalies)

    def _stop_ml_monitor(self) -> None:
        if self._ml_monitor_id is not None:
            self.after_cancel(self._ml_monitor_id)
            self._ml_monitor_id = None

    def _monitor_ml_anomalies(self) -> None:
        if self._is_closing:
            return
        try:
            if not self.winfo_exists():
                return
        except TclError:
            return

        csv_path = self._find_latest_telemetry_file()
        if not csv_path:
            self._ml_monitor_id = self._schedule_after(ML_MONITOR_INTERVAL_MS, self._monitor_ml_anomalies)
            return

        try:
            df = pd.read_csv(csv_path)
        except Exception:
            self._ml_monitor_id = self._schedule_after(ML_MONITOR_INTERVAL_MS, self._monitor_ml_anomalies)
            return

        if self._ml_last_file != csv_path:
            self._ml_last_file = csv_path
            self._ml_last_row = 0

        if self._ml_last_row >= len(df):
            self._ml_monitor_id = self._schedule_after(ML_MONITOR_INTERVAL_MS, self._monitor_ml_anomalies)
            return

        new_df = df.iloc[self._ml_last_row :].copy()
        self._ml_last_row = len(df)

        features = self._extract_ml_features(new_df)
        if not features:
            self._ml_monitor_id = self._schedule_after(ML_MONITOR_INTERVAL_MS, self._monitor_ml_anomalies)
            return

        if self._ml_model is None:
            self._ml_baseline.extend(features)
            if len(self._ml_baseline) >= ML_BASELINE_MIN_SAMPLES:
                self._train_ml_model()
            self._ml_monitor_id = self._schedule_after(ML_MONITOR_INTERVAL_MS, self._monitor_ml_anomalies)
            return

        scores = -self._ml_model.decision_function(features)
        max_score = float(max(scores))
        if max_score >= ML_ANOMALY_THRESHOLD:
            self._ml_anomaly_streak += 1
        else:
            self._ml_anomaly_streak = 0

        if self._ml_anomaly_streak >= ML_ANOMALY_STREAK and self.crypto.is_unlocked:
            self._lock_due_to_ml(max_score)
            self._ml_anomaly_streak = 0

        self._ml_monitor_id = self._schedule_after(ML_MONITOR_INTERVAL_MS, self._monitor_ml_anomalies)

    def _extract_ml_features(self, df: pd.DataFrame) -> list[list[float]]:
        if {"Dwell_Time", "Flight_Time"}.issubset(df.columns):
            dwell = pd.to_numeric(df["Dwell_Time"], errors="coerce")
            flight = pd.to_numeric(df["Flight_Time"], errors="coerce")
            outlier = df["Outlier"] if "Outlier" in df.columns else pd.Series([False] * len(df), index=df.index)
            outlier_mask = outlier.astype(str).str.lower().isin(["true", "1", "yes"])
            valid = ~outlier_mask
        elif {"dwell_time", "flight_time"}.issubset(df.columns):
            dwell = pd.to_numeric(df["dwell_time"], errors="coerce")
            flight = pd.to_numeric(df["flight_time"], errors="coerce")
            valid = pd.Series([True] * len(df), index=df.index)
        else:
            return []

        valid = valid & dwell.notna() & flight.notna()
        if not valid.any():
            return []

        features = []
        for dwell_val, flight_val in zip(dwell[valid].tolist(), flight[valid].tolist()):
            features.append([float(dwell_val), float(flight_val)])
        return features

    def _train_ml_model(self) -> None:
        try:
            from sklearn.ensemble import IsolationForest
        except Exception as exc:
            self._set_status_message("scikit-learn not installed. ML guard disabled.", is_error=True)
            logger.warning("ML monitor disabled: %s", exc)
            self._ml_baseline.clear()
            return

        model = IsolationForest(
            n_estimators=200,
            contamination=0.05,
            random_state=42,
        )
        model.fit(self._ml_baseline)
        self._ml_model = model
        self._ml_baseline.clear()
        self._log_event("ML baseline trained. Behavioral guard active.")

    def _lock_due_to_ml(self, score: float) -> None:
        if not self.crypto.is_unlocked:
            return
        self.crypto.lock_vault()
        self._hardware_port = ""
        self._set_unlocked_state(False, message="Behavioral anomaly detected. Vault locked.", is_error=True)
        self._log_event(f"ML anomaly score {score:.3f} exceeded threshold. Vault locked.")

        # Dispatch Telegram Bot Alert in a separate thread to keep UI interactive
        import threading
        def send_telegram_alert():
            import os
            try:
                import requests
            except ImportError:
                logger.warning("requests package is not installed. Telegram alert skipped.")
                return

            token = os.environ.get("TELEGRAM_BOT_TOKEN")
            chat_id = os.environ.get("TELEGRAM_CHAT_ID")
            if not token or not chat_id:
                logger.info("Telegram notification skipped: TELEGRAM_BOT_TOKEN or TELEGRAM_CHAT_ID not configured.")
                return

            try:
                url = f"https://api.telegram.org/bot{token}/sendMessage"
                payload = {
                    "chat_id": chat_id,
                    "text": f"🚨 SecureFlow Alert: Anomalous keystroke behavior detected. Vault locked. Anomaly score: {score:.3f}"
                }
                res = requests.post(url, json=payload, timeout=5)
                if res.status_code == 200:
                    logger.info("Telegram alert sent successfully.")
                else:
                    logger.warning("Telegram alert API returned status %d: %s", res.status_code, res.text)
            except Exception as e:
                logger.error("Failed to send Telegram alert: %s", e)

        threading.Thread(target=send_telegram_alert, daemon=True).start()


    def _start_totp_loop(self) -> None:
        if self._totp_timer_id is not None:
            self.after_cancel(self._totp_timer_id)
        self._update_totp()

    def _update_totp(self) -> None:
        if self._is_closing:
            return
        try:
            if not self.winfo_exists():
                return
        except TclError:
            return

        if not self.crypto.is_unlocked:
            self.totp_label.configure(text="LOCKED")
            self.totp_progress.set(0.0)
            self._totp_timer_id = self._schedule_after(800, self._update_totp)
            return

        if not self._totp_secret:
            self.totp_label.configure(text="SELECT KEY")
            self.totp_progress.set(0.0)
            self._totp_timer_id = self._schedule_after(500, self._update_totp)
            return

        totp = pyotp.TOTP(self._totp_secret, interval=self._totp_period)
        now = int(time.time())
        step = now // self._totp_period

        if step != self._totp_last_step:
            code = totp.now()
            self.totp_label.configure(text=f"{code[:3]} {code[3:]}")
            self._totp_last_step = step

        remaining = self._totp_period - (now % self._totp_period)
        self.totp_progress.set(remaining / self._totp_period)

        self._totp_timer_id = self._schedule_after(200, self._update_totp)

    def _apply_totp_secret(self) -> None:
        if not self.crypto.is_unlocked:
            messagebox.showerror("Authenticator", "Unlock the vault before adding keys.")
            return

        raw = self.totp_secret_entry.get().strip()
        if not raw:
            messagebox.showerror("Authenticator", "Paste a Base32 secret or otpauth:// URI.")
            return

        try:
            if raw.lower().startswith("otpauth://"):
                otp = pyotp.parse_uri(raw)
                if not hasattr(otp, "interval"):
                    raise ValueError("Only TOTP keys are supported.")
                secret = otp.secret
                issuer = getattr(otp, "issuer", "") or ""
                account = getattr(otp, "name", "") or ""
                period = int(getattr(otp, "interval", 30) or 30)
            else:
                secret = raw.replace(" ", "")
                pyotp.TOTP(secret).now()
                issuer = ""
                account = ""
                period = 30
        except Exception as exc:
            messagebox.showerror("Authenticator", f"Invalid secret or URI: {exc}")
            return

        label = self.totp_label_entry.get().strip()
        if not label:
            label = issuer or account or "TOTP Key"

        key_id = uuid.uuid4().hex
        self._totp_store[key_id] = {
            "label": label,
            "issuer": issuer,
            "account": account,
            "secret": secret,
            "period": period,
        }

        self.totp_label_entry.delete(0, "end")
        self.totp_secret_entry.delete(0, "end")

        self._select_totp_key(key_id)
        self._update_totp_status()
        self._save_totp_store_to_vault()

    def _clear_totp_secret(self) -> None:
        if not self.crypto.is_unlocked:
            messagebox.showerror("Authenticator", "Unlock the vault before removing keys.")
            return

        if not self._totp_selected_id:
            messagebox.showinfo("Authenticator", "Select a key to remove.")
            return

        self._totp_store.pop(self._totp_selected_id, None)
        self._totp_selected_id = None
        self._totp_secret = None
        self._totp_issuer = ""
        self._totp_account = ""
        self._totp_period = 30
        self._totp_last_step = -1

        if self._totp_store:
            first_id = next(iter(self._totp_store))
            self._select_totp_key(first_id)
        else:
            self.totp_detail_name.configure(text="No key selected")
            self.totp_detail_meta.configure(text="")
            self.totp_label.configure(text="SELECT KEY")
            self.totp_progress.set(0.0)

        self._render_totp_rows()
        self._update_totp_status()
        self._save_totp_store_to_vault()

    def _refresh_ml_chart(self) -> None:
        for child in self.ml_chart_container.winfo_children():
            child.destroy()
        if self._ml_canvas is not None:
            self._ml_canvas.get_tk_widget().destroy()
            self._ml_canvas = None

        csv_path = self._find_latest_telemetry_file()
        if not csv_path:
            ctk.CTkLabel(
                self.ml_chart_container,
                text="No telemetry CSV found.",
                font=FONTS["mono"],
                text_color=COLORS["muted"],
            ).grid(row=0, column=0, padx=16, pady=16)
            return

        df = pd.read_csv(csv_path)
        if df.empty:
            ctk.CTkLabel(
                self.ml_chart_container,
                text="No telemetry data available.",
                font=FONTS["mono"],
                text_color=COLORS["muted"],
            ).grid(row=0, column=0, padx=16, pady=16)
            return

        # Map SecureFlow logger columns into the chart schema.
        if {"Dwell_Time", "Flight_Time", "Outlier"}.issubset(df.columns):
            dwell = pd.to_numeric(df["Dwell_Time"], errors="coerce")
            flight = pd.to_numeric(df["Flight_Time"], errors="coerce")
            outlier = df["Outlier"].astype(str).str.lower().isin(["true", "1", "yes"])
            anomaly = outlier.astype(int)
            x_axis = df.index
        else:
            dwell = pd.to_numeric(df.get("dwell_time", pd.Series(dtype=float)), errors="coerce")
            flight = pd.to_numeric(df.get("flight_time", pd.Series(dtype=float)), errors="coerce")
            anomaly = pd.to_numeric(df.get("anomaly_score", pd.Series(dtype=float)), errors="coerce")
            x_axis = df.get("timestamp", df.index)

        plt.rcParams.update({"font.family": "Consolas"})
        fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(7, 6), dpi=100)
        fig.patch.set_facecolor(COLORS["panel"])

        ax1.set_facecolor(COLORS["panel_alt"])
        ax2.set_facecolor(COLORS["panel_alt"])

        ax1.plot(x_axis, dwell, label="dwell", color="#60a5fa")
        ax1.plot(x_axis, flight, label="flight", color="#34d399")
        ax1.set_title("Dwell/Flight Time", color=COLORS["text"])
        ax1.tick_params(axis="x", colors=COLORS["muted"])
        ax1.tick_params(axis="y", colors=COLORS["muted"])
        ax1.legend(facecolor=COLORS["panel"], edgecolor=COLORS["border"], labelcolor=COLORS["text"])

        ax2.bar(x_axis, anomaly, color="#f97316")
        ax2.set_title("Anomaly Score", color=COLORS["text"])
        ax2.tick_params(axis="x", colors=COLORS["muted"])
        ax2.tick_params(axis="y", colors=COLORS["muted"])

        fig.tight_layout(pad=2)

        self._ml_canvas = FigureCanvasTkAgg(fig, master=self.ml_chart_container)
        self._ml_canvas.draw()
        self._ml_canvas.get_tk_widget().pack(fill="both", expand=True)

    def _find_latest_telemetry_file(self) -> Path | None:
        candidates = sorted(Path(".").glob("*.csv"), key=lambda p: p.stat().st_mtime, reverse=True)
        if not candidates:
            return None

        for path in candidates:
            try:
                sample = pd.read_csv(path, nrows=2)
            except Exception:
                continue

            if {"Dwell_Time", "Flight_Time", "Outlier"}.issubset(sample.columns):
                return path
            if {"timestamp", "dwell_time", "flight_time", "anomaly_score"}.issubset(sample.columns):
                return path

        return None

    def _schedule_after(self, delay_ms: int, callback) -> str | None:
        if self._is_closing:
            return None
        try:
            if not self.winfo_exists():
                return None
            return self.after(delay_ms, callback)
        except TclError:
            return None

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
            self.pair_button.configure(state="normal")
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
            self.pair_button.configure(state="disabled")
            for button in self._file_buttons:
                button.configure(state="disabled")
            self._stop_hardware_monitor()
            self._set_badge_state(self.badge_key, False)
            self._set_badge_state(self.badge_plaintext, False)
            self._set_badge_state(self.badge_aes, False)
            self._set_badge_state(self.badge_hkdf, False)
            self._clear_viewer("Vault is locked. No data in memory.")
            self._clear_passwords_memory()
            self._clear_totp_memory()

        if message:
            self._set_status_message(message, is_error=is_error)

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
            self._load_totp_store_from_vault()
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

    def _on_upload_to_cloud(self) -> None:
        """Pick one or more already-encrypted .enc files and upload them to S3.

        Only files that already exist in the vault directory are selectable.
        The upload runs on a background thread so the UI stays responsive.
        """
        if not self.crypto.is_unlocked:
            self._set_unlocked_state(False, message="Vault is locked. Hardware tap required.")
            return

        if not self.cloud:
            messagebox.showerror(
                "Cloud Not Configured",
                "AWS S3 credentials are not set.\n\n"
                "Check your .env file for AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, "
                "AWS_DEFAULT_REGION, and S3_BUCKET_NAME.",
            )
            return

        # Default to the vault directory so the user sees only vault files.
        vault_dir = str(self.crypto.vault_dir)
        filepaths = filedialog.askopenfilenames(
            title="Select encrypted file(s) to upload",
            initialdir=vault_dir,
            filetypes=[("Encrypted vault files", "*.enc"), ("All Files", "*.*")],
        )
        if not filepaths:
            return

        # Skip internal store files — they must never leave the local vault.
        skip = {AUTH_STORE_FILENAME, PASSWORD_STORE_FILENAME}
        selected = [p for p in filepaths if Path(p).name not in skip]
        if not selected:
            messagebox.showwarning(
                "Nothing to Upload",
                "The selected file(s) are internal vault stores and cannot be uploaded.",
            )
            return

        names = ", ".join(Path(p).name for p in selected)
        self._set_status_message(f"Uploading {len(selected)} file(s) to AWS...")
        self._log_event(f"Manual cloud upload started: {names}")
        self.upload_cloud_button.configure(state="disabled", text="Uploading...")

        def _do_upload():
            results = []
            for filepath in selected:
                path = Path(filepath)
                try:
                    self.cloud.upload_vault_file(str(path), path.name, delete_local=False)
                    results.append((path.name, None))
                except (CloudManagerError, Exception) as exc:
                    results.append((path.name, exc))
            return results

        def _on_done(results):
            self.upload_cloud_button.configure(state="normal", text="☁ Upload to Cloud")
            errors = [(n, e) for n, e in results if e is not None]
            ok    = [(n, e) for n, e in results if e is None]
            for name, _ in ok:
                self._log_event(f"Uploaded to cloud: {name}")
            if errors:
                detail = "\n".join(f"{n}: {e}" for n, e in errors)
                self._set_status_message(f"{len(errors)} upload(s) failed.", is_error=True)
                messagebox.showerror("Upload Errors", detail)
            else:
                self._set_status_message(f"Uploaded {len(ok)} file(s) successfully.")
            self.refresh_vault_listing()

        def _on_error(exc):
            self.upload_cloud_button.configure(state="normal", text="☁ Upload to Cloud")
            self._set_status_message(str(exc), is_error=True)
            messagebox.showerror("Upload Failed", str(exc))

        self._run_in_thread(_do_upload, on_done=_on_done, on_error=_on_error)

    def refresh_vault_listing(self) -> None:
        for child in self.vault_list_frame.winfo_children():
            child.destroy()
        self._file_buttons.clear()

        items_added = 0

        enc_files = sorted(self.crypto.vault_dir.glob("*.enc"))
        for path in enc_files:
            if path.name in {AUTH_STORE_FILENAME, PASSWORD_STORE_FILENAME}:
                continue
            self._add_vault_button(path.name, "local", str(path))
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
                    self._add_vault_button(name, "cloud", name)
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
        # Flush unsaved in-memory data BEFORE wiping the key, otherwise the
        # is_unlocked guard inside each save method silently aborts the write.
        self._save_passwords_to_vault()
        self._save_totp_store_to_vault()
        # Wipe key material and remove any decrypted content from the UI.
        self.crypto.lock_vault()
        self._hardware_port = ""
        self._set_unlocked_state(False, message="Vault locked. Key wiped from RAM.")
        self._log_event("Vault locked. RAM key wiped with memset.")

    def _on_close(self) -> None:
        self._is_closing = True
        # Flush unsaved in-memory data BEFORE wiping the key so the
        # is_unlocked guard inside each save method doesn't abort the write.
        self._save_passwords_to_vault()
        self._save_totp_store_to_vault()
        # Wipe key material after saves are complete.
        self.crypto.lock_vault()
        self._stop_hardware_monitor()
        self._stop_ml_monitor()
        for _attr in ("_totp_timer_id", "_queue_pump_id"):
            _aid = getattr(self, _attr, None)
            if _aid:
                try:
                    self.after_cancel(_aid)
                except Exception:
                    pass
                setattr(self, _attr, None)
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
        row = ctk.CTkFrame(self.vault_list_frame, fg_color="transparent")
        row.grid_columnconfigure(0, weight=1)

        button = ctk.CTkButton(
            row,
            text=label,
            anchor="w",
            fg_color=COLORS["panel"],
            hover_color=COLORS["panel_alt_hover"],
            text_color=COLORS["text"],
            command=lambda s=source, i=identifier: self._open_encrypted_file(s, i),
        )
        button.grid(row=0, column=0, sticky="ew", padx=(0, 8))

        badge_text = "LOCAL" if source == "local" else "CLOUD"
        if source == "local":
            badge_fg = COLORS["badge_inactive"]
            badge_text_color = COLORS["badge_text_inactive"]
        else:
            badge_fg = COLORS["badge_bg"]
            badge_text_color = COLORS["text"]

        badge = ctk.CTkLabel(
            row,
            text=badge_text,
            font=FONTS["badge"],
            text_color=badge_text_color,
            fg_color=badge_fg,
            corner_radius=10,
            padx=8,
            pady=2,
        )
        badge.grid(row=0, column=1, sticky="e")

        destroy_btn = ctk.CTkButton(
            row,
            text="×",
            width=28,
            height=24,
            fg_color="transparent",
            hover_color=COLORS["danger_hover"],
            text_color=COLORS["danger"],
            font=FONTS["title"],
            command=lambda s=source, i=identifier, l=label: self._delete_vault_file(s, i, l),
        )
        destroy_btn.grid(row=0, column=2, padx=(6, 0), sticky="e")

        state = "normal" if self.crypto.is_unlocked else "disabled"
        button.configure(state=state)
        destroy_btn.configure(state=state)
        row.pack(fill="x", padx=8, pady=4)
        self._file_buttons.append(button)
        self._file_buttons.append(destroy_btn)

    def _delete_vault_file(self, source: str, identifier: str, label: str) -> None:
        if not messagebox.askyesno("Confirm Destruction", f"Are you sure you want to permanently destroy '{label}' from {source}?"):
            return

        try:
            if source == "local":
                path = Path(identifier)
                if path.is_file():
                    path.unlink()
                self._set_status_message(f"Destroyed local file: {label}")
                self._log_event(f"Destroyed local file: {label}")
            else:
                if not self.cloud:
                    raise CloudManagerError("Cloud not configured.")
                self.cloud.delete_vault_file(identifier)
                self._set_status_message(f"Destroyed cloud file: {label}")
                self._log_event(f"Destroyed cloud file: {label}")

            if self._last_selected_object == (source, identifier):
                self._clear_viewer("File destroyed. Vault is empty.")
                self._last_selected_object = None

            self.refresh_vault_listing()
        except Exception as exc:
            logger.exception("Failed to destroy file")
            self._set_status_message(str(exc), is_error=True)
            messagebox.showerror("Destruction Failed", str(exc))

    def _start_hardware_monitor(self) -> None:
        self._stop_hardware_monitor()
        self._hardware_monitor_id = self._schedule_after(1500, self._check_hardware_connection)

    def _stop_hardware_monitor(self) -> None:
        if self._hardware_monitor_id is not None:
            self.after_cancel(self._hardware_monitor_id)
            self._hardware_monitor_id = None

    def _check_hardware_connection(self) -> None:
        if not self.crypto.is_unlocked or not self._hardware_port:
            self._hardware_monitor_id = None
            return

        if self._hardware_port.upper() == "MOCK":
            self._hardware_monitor_id = self._schedule_after(1500, self._check_hardware_connection)
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

        self._hardware_monitor_id = self._schedule_after(1500, self._check_hardware_connection)

    def _on_pair_click(self) -> None:
        """Display a beautiful, custom-themed dialog with the MVK QR code for mobile pairing."""
        try:
            # Load the secret via crypto engine
            secret_bytes = self.crypto._load_hardware_secret()
            secret_str = secret_bytes.decode("utf-8").strip()
        except Exception as exc:
            messagebox.showerror("Mobile Pairing", f"Could not load master vault key: {exc}")
            return

        self._show_qr_window(secret_str)

    def _show_qr_window(self, secret: str) -> None:
        """Draws a gorgeous, premium modal containing the MVK QR code."""
        qr_win = ctk.CTkToplevel(self)
        qr_win.title("Mobile Companion Pairing")
        qr_win.geometry("420x540")
        qr_win.resizable(False, False)
        qr_win.configure(fg_color=COLORS["bg"])
        
        # Ensure it stays on top of parent window
        qr_win.transient(self)
        qr_win.grab_set()

        # Premium header
        ctk.CTkLabel(
            qr_win,
            text="PAIR COMPANION",
            font=FONTS["title"],
            text_color=COLORS["text"]
        ).pack(pady=(24, 8))

        ctk.CTkLabel(
            qr_win,
            text="Scan this QR code from the SecureFlow Mobile app\nto sync your hardware-gated encryption key.",
            font=FONTS["body"],
            text_color=COLORS["muted"],
            justify="center"
        ).pack(padx=24, pady=(0, 16))

        # Generate QR code
        qr = qrcode.QRCode(
            version=1,
            error_correction=qrcode.constants.ERROR_CORRECT_L,
            box_size=10,
            border=2,
        )
        qr.add_data(secret)
        qr.make(fit=True)

        # Style the QR image with a custom dark/light palette to pop perfectly on the dark UI
        qr_img = qr.make_image(fill_color="black", back_color="white")
        qr_img = qr_img.resize((240, 240), Image.Resampling.LANCZOS)
        
        # Convert PIL to ImageTk
        photo_img = ImageTk.PhotoImage(qr_img)
        
        # Store a reference to avoid garbage collection
        qr_win.qr_image_ref = photo_img

        # Display the QR code inside a stylish, bordered frame
        qr_frame = ctk.CTkFrame(
            qr_win,
            width=250,
            height=250,
            fg_color="white", # high contrast background for the scanner
            corner_radius=12,
        )
        qr_frame.pack(pady=12)
        qr_frame.pack_propagate(False)

        qr_label = ctk.CTkLabel(qr_frame, image=photo_img, text="")
        qr_label.pack(expand=True, fill="both")

        # Toggleable Raw Key display
        secret_visible = {"value": False}
        
        secret_box_frame = ctk.CTkFrame(
            qr_win,
            fg_color=COLORS["panel"],
            border_width=1,
            border_color=COLORS["border"],
            corner_radius=8
        )
        secret_box_frame.pack(fill="x", padx=32, pady=16)

        secret_label = ctk.CTkLabel(
            secret_box_frame,
            text="••••••••••••••••••••••••••••••••",
            font=FONTS["mono"],
            text_color=COLORS["muted"]
        )
        secret_label.pack(side="left", padx=12, pady=10, expand=True, fill="x")

        def toggle_secret():
            secret_visible["value"] = not secret_visible["value"]
            if secret_visible["value"]:
                truncated = secret[:12] + "..." + secret[-12:] if len(secret) > 24 else secret
                secret_label.configure(text=truncated, text_color=COLORS["success"])
                toggle_btn.configure(text="Hide")
            else:
                secret_label.configure(text="••••••••••••••••••••••••••••••••", text_color=COLORS["muted"])
                toggle_btn.configure(text="Show")

        toggle_btn = ctk.CTkButton(
            secret_box_frame,
            text="Show",
            width=60,
            fg_color=COLORS["panel_alt"],
            hover_color=COLORS["panel_alt_hover"],
            text_color=COLORS["text"],
            command=toggle_secret
        )
        toggle_btn.pack(side="right", padx=8, pady=8)

        # Close button
        close_btn = ctk.CTkButton(
            qr_win,
            text="Done",
            fg_color=COLORS["accent"],
            hover_color=COLORS["accent_hover"],
            text_color=COLORS["text"],
            command=qr_win.destroy
        )
        close_btn.pack(pady=(0, 24))

