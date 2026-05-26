"""SecureFlow MVP entry point."""
from __future__ import annotations

import logging
import sys
from pathlib import Path

import customtkinter as ctk
from dotenv import load_dotenv

from crypto_engine import CryptoEngine
from vault_gui import VaultGUI


def main() -> None:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s | %(levelname)s | %(name)s | %(message)s",
    )

    # Ensure .env is loaded from the executable's directory when frozen.
    if getattr(sys, "frozen", False):
        base_dir = Path(sys.executable).resolve().parent
    else:
        base_dir = Path(__file__).resolve().parent

    load_dotenv(dotenv_path=base_dir / ".env", override=False)

    ctk.set_appearance_mode("dark")

    engine = CryptoEngine()

    app = VaultGUI(engine)
    try:
        app.mainloop()
    except KeyboardInterrupt:
        try:
            app._on_close()
        except Exception:
            pass


if __name__ == "__main__":
    main()
