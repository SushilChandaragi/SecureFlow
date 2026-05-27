// Credential — maps to passwords.enc JSON payload
// JSON payload format (from desktop): [{website, username, password}, ...]
class Credential {
  final String website;
  final String username;
  final String password;

  const Credential({
    required this.website,
    required this.username,
    required this.password,
  });

  factory Credential.fromJson(Map<String, dynamic> json) => Credential(
        website: (json['website'] as String?) ?? '',
        username: (json['username'] as String?) ?? '',
        password: (json['password'] as String?) ?? '',
      );

  Map<String, dynamic> toJson() => {
        'website': website,
        'username': username,
        'password': password,
      };

  /// Composite key used by the desktop to index credentials.
  String get storeKey => '$website|$username';

  @override
  String toString() => 'Credential($website, $username)';
}
