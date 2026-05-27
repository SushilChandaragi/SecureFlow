/// SecureFlow Mobile — TOTP Service
/// Generates time-based one-time passwords using the otp package.
library;

import 'package:otp/otp.dart';

class TotpService {
  /// Generate the current TOTP code for a given Base32 [secret].
  static String generateCode(String secret, {int period = 30}) {
    return OTP.generateTOTPCodeString(
      secret.toUpperCase().replaceAll(' ', ''),
      DateTime.now().millisecondsSinceEpoch,
      interval: period,
      algorithm: Algorithm.SHA1,
      isGoogle: true,
    );
  }

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
