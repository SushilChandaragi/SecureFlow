// SecureFlow App Theme — Unified ThemeData
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'colors.dart';
import 'typography.dart';

ThemeData buildSFTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: SFColors.bgPrimary,
    colorScheme: const ColorScheme.dark(
      surface: SFColors.bgPrimary,
      primary: SFColors.textMain,
      secondary: SFColors.success,
      error: SFColors.danger,
    ),

    // ── Text Theme ─────────────────────────────────────────────────
    textTheme: GoogleFonts.interTextTheme(
      ThemeData.dark().textTheme.apply(
        bodyColor: SFColors.textMain,
        displayColor: SFColors.textMain,
      ),
    ),

    // ── AppBar ─────────────────────────────────────────────────────
    appBarTheme: AppBarTheme(
      backgroundColor: SFColors.bgPrimary,
      foregroundColor: SFColors.textMain,
      elevation: 0,
      scrolledUnderElevation: 0,
      systemOverlayStyle: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: SFColors.bgPrimary,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      titleTextStyle: SFTypography.cardTitle,
    ),

    // ── Card ───────────────────────────────────────────────────────
    cardTheme: CardThemeData(
      color: SFColors.bgCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SFRadius.bento),
        side: const BorderSide(color: SFColors.borderSoft, width: 1),
      ),
      margin: EdgeInsets.zero,
    ),

    // ── Elevated Button ────────────────────────────────────────────
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: SFColors.actionBg,
        foregroundColor: SFColors.actionText,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SFRadius.small),
        ),
        textStyle: SFTypography.button,
        padding: const EdgeInsets.symmetric(
          horizontal: SFSpacing.md,
          vertical: SFSpacing.sm,
        ),
      ),
    ),

    // ── Outlined Button ────────────────────────────────────────────
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: SFColors.textMain,
        side: const BorderSide(color: SFColors.borderMedium),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SFRadius.small),
        ),
        textStyle: SFTypography.button,
      ),
    ),

    // ── Input Decoration ───────────────────────────────────────────
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: SFColors.bgCard,
      hintStyle: SFTypography.bodyMuted,
      labelStyle: SFTypography.metadata,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(SFRadius.small),
        borderSide: const BorderSide(color: SFColors.borderSoft),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(SFRadius.small),
        borderSide: const BorderSide(color: SFColors.borderSoft),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(SFRadius.small),
        borderSide: const BorderSide(color: SFColors.borderMedium),
      ),
    ),

    // ── Divider ────────────────────────────────────────────────────
    dividerTheme: const DividerThemeData(
      color: SFColors.borderSoft,
      thickness: 1,
      space: 0,
    ),

    // ── Switch ─────────────────────────────────────────────────────
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? SFColors.textMain : SFColors.textFaint),
      trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? SFColors.borderMedium : SFColors.borderSoft),
    ),
  );
}
