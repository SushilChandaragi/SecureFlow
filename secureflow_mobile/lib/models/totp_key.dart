// TotpKey — maps to auth_keys.enc JSON payload
// JSON payload format (from desktop): [{id, label, issuer, account, secret, period}, ...]
class TotpKey {
  final String id;
  final String label;
  final String issuer;
  final String account;
  final String secret;  // Base32-encoded TOTP secret
  final int period;     // Usually 30 seconds

  const TotpKey({
    required this.id,
    required this.label,
    required this.issuer,
    required this.account,
    required this.secret,
    this.period = 30,
  });

  factory TotpKey.fromJson(Map<String, dynamic> json) => TotpKey(
        id: (json['id'] as String?) ?? '',
        label: (json['label'] as String?) ?? '',
        issuer: (json['issuer'] as String?) ?? '',
        account: (json['account'] as String?) ?? '',
        secret: (json['secret'] as String?) ?? '',
        period: (json['period'] as int?) ?? 30,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'issuer': issuer,
        'account': account,
        'secret': secret,
        'period': period,
      };

  String get displayName {
    if (label.isNotEmpty) return label;
    if (issuer.isNotEmpty) return issuer;
    if (account.isNotEmpty) return account;
    return 'TOTP KEY';
  }

  String get metaLine {
    final parts = [issuer, account].where((s) => s.isNotEmpty).toList();
    return parts.join(' | ');
  }
}
