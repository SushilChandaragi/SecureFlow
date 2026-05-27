// SecureFlow Design Tokens — §6 of the UI specification
import 'dart:ui';

abstract final class SFColors {
  // ── Backgrounds ──────────────────────────────────────────────────────
  static const bgPrimary  = Color(0xFF050505); // App background / splash
  static const bgCard     = Color(0xFF111111); // Bento containers, modals
  static const bgElevated = Color(0xFF1A1A1A); // Hover / elevated cards

  // ── Borders ───────────────────────────────────────────────────────────
  static const borderSoft    = Color(0x14FFFFFF); // rgba(255,255,255,0.08)
  static const borderMedium  = Color(0x26FFFFFF); // rgba(255,255,255,0.15)
  static const borderDanger  = Color(0xFFFF4D4D);

  // ── Text ─────────────────────────────────────────────────────────────
  static const textMain    = Color(0xFFFFFFFF);  // Primary headings, active values
  static const textMuted   = Color(0x99FFFFFF);  // rgba(255,255,255,0.6)
  static const textFaint   = Color(0x4DFFFFFF);  // rgba(255,255,255,0.3)

  // ── Accent / Status ───────────────────────────────────────────────────
  static const danger       = Color(0xFFFF4D4D); // Panic buttons, threat alerts
  static const dangerMuted  = Color(0x33FF4D4D); // Danger zone backgrounds
  static const success      = Color(0xFF34D399); // Secure / active states
  static const successMuted = Color(0x2034D399);

  // ── Primary Action ────────────────────────────────────────────────────
  static const actionBg   = Color(0xFFEAEAEA); // Primary button background
  static const actionText = Color(0xFF050505); // Primary button text

  // ── Gradients ─────────────────────────────────────────────────────────
  static const shimmerStart = Color(0xFF111111);
  static const shimmerEnd   = Color(0xFF1E1E1E);
}

abstract final class SFRadius {
  static const double bento   = 28.0; // Master corner radius (§6)
  static const double card    = 20.0; // Inner cards
  static const double small   = 12.0; // Badges, chips
  static const double pill    = 999.0; // Nav pill, fully rounded
}

abstract final class SFSpacing {
  static const double base   = 16.0; // Grid gaps, internal padding
  static const double xs     = 8.0;
  static const double sm     = 12.0;
  static const double md     = 20.0;
  static const double lg     = 24.0;
  static const double xl     = 32.0;
  static const double xxl    = 48.0;
}
