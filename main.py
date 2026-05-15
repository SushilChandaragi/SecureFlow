"""SecureFlow MVP entry point."""
from __future__ import annotations

import customtkinter as ctk

from crypto_engine import CryptoEngine
from vault_gui import VaultGUI


def main() -> None:
    ctk.set_appearance_mode("dark")

    engine = CryptoEngine()

    app = VaultGUI(engine)
    app.mainloop()


if __name__ == "__main__":
    main()
