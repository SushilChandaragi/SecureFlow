// SecureFlow Typography Scales — §8 of the UI specification
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'colors.dart';

abstract final class SFTypography {
  // ── Header 1: Inter 32px Bold -1.0px ─────────────────────────────
  static TextStyle get h1 => GoogleFonts.inter(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.0,
        color: SFColors.textMain,
      );

  // ── Card Title: Space Grotesk 18px Medium ─────────────────────────
  static TextStyle get cardTitle => GoogleFonts.spaceGrotesk(
        fontSize: 18,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.0,
        color: SFColors.textMain,
      );

  // ── Data Value: JetBrains Mono 24px Bold -0.5px ───────────────────
  // (Suisse Intl substitute — same mono aesthetic, free font)
  static TextStyle get dataValue => GoogleFonts.jetBrainsMono(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        color: SFColors.textMain,
      );

  // ── TOTP Code: JetBrains Mono 48px Bold ───────────────────────────
  static TextStyle get totpCode => GoogleFonts.jetBrainsMono(
        fontSize: 48,
        fontWeight: FontWeight.w700,
        letterSpacing: 4.0,
        color: SFColors.textMain,
      );

  // ── Metadata Tag: Inter 10px SemiBold +1.5px Uppercase ────────────
  static TextStyle get metadata => GoogleFonts.inter(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.5,
        color: SFColors.textMuted,
      );

  // ── Body: Inter 14px Regular +0.2px ──────────────────────────────
  static TextStyle get body => GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.2,
        color: SFColors.textMain,
      );

  // ── Body Muted ────────────────────────────────────────────────────
  static TextStyle get bodyMuted => body.copyWith(color: SFColors.textMuted);

  // ── Terminal / Mono: JetBrains Mono 12px ─────────────────────────
  static TextStyle get terminal => GoogleFonts.jetBrainsMono(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.8,
        color: SFColors.textMuted,
      );

  // ── Section Label: Inter 11px SemiBold +2.0px Uppercase ──────────
  static TextStyle get sectionLabel => GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 2.0,
        color: SFColors.textFaint,
      );

  // ── Button: Inter 13px SemiBold +1.5px ───────────────────────────
  static TextStyle get button => GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.5,
        color: SFColors.textMain,
      );

  // ── Danger: Inter 13px Bold ───────────────────────────────────────
  static TextStyle get danger => GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.5,
        color: SFColors.danger,
      );
}
