// UserProfile — session metadata for the mobile app
class UserProfile {
  final String deviceName;
  final String sessionId;
  final DateTime sessionStart;
  final bool isBiometricAuth;  // true = fingerprint/face, false = NFC
  final bool isNfcAuth;

  const UserProfile({
    required this.deviceName,
    required this.sessionId,
    required this.sessionStart,
    this.isBiometricAuth = false,
    this.isNfcAuth = false,
  });

  String get authMethodLabel {
    if (isBiometricAuth && isNfcAuth) return 'BIO + NFC';
    if (isBiometricAuth) return 'BIOMETRIC';
    if (isNfcAuth) return 'NFC TAG';
    return 'UNKNOWN';
  }

  String get sessionDuration {
    final delta = DateTime.now().difference(sessionStart);
    final h = delta.inHours.toString().padLeft(2, '0');
    final m = (delta.inMinutes % 60).toString().padLeft(2, '0');
    final s = (delta.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}
