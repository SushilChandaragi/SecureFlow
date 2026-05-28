/// SecureFlow Mobile — TOTP Service
/// Generates time-based one-time passwords using the otp package.
library;

import 'package:otp/otp.dart';

// Base32 character set (RFC 4648)
const _kBase32Chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

class TotpService {
  /// Validate that [secret] is a valid non-empty Base32 string.
  /// Returns null if valid, or an error message string if invalid.
  static String? validateBase32(String? value) {
    if (value == null || value.isEmpty) return 'SECRET IS REQUIRED';
    final cleaned = value.trim().replaceAll(' ', '').toUpperCase();
    if (cleaned.length < 8) return 'SECRET TOO SHORT (MIN 8 CHARS)';
    for (final char in cleaned.split('')) {
      if (!_kBase32Chars.contains(char) && char != '=') {
        return 'INVALID BASE32 CHARACTER: "$char"';
      }
    }
    return null;
  }

  /// Generate the current TOTP code for a given Base32 [secret].
  /// Returns '------' if the secret is invalid (never throws).
  static String generateCode(String secret, {int period = 30}) {
    try {
      final cleaned = secret.trim().replaceAll(' ', '').toUpperCase();
      if (cleaned.isEmpty) return '------';
      return OTP.generateTOTPCodeString(
        cleaned,
        DateTime.now().millisecondsSinceEpoch,
        interval: period,
        algorithm: Algorithm.SHA1,
        isGoogle: true,
      );
    } catch (_) {
      return '------';
    }
  }

  /// Returns true if the secret produces a valid code (i.e. is not corrupt).
  static bool isSecretValid(String secret) =>
      generateCode(secret) != '------';

  /// Remaining seconds until the next TOTP window.
  static int remainingSeconds({int period = 30}) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return period - (now % period);
  }

  /// Progress (0.0 → 1.0) for a circular countdown ring.
  static double ringProgress({int period = 30}) {
    return remainingSeconds(period: period) / period;
  }

  /// Format a raw 6-digit code as "XXX XXX" for display.
  static String formatCode(String code) {
    if (code.length < 6) return code;
    return '${code.substring(0, 3)} ${code.substring(3)}';
  }
}
