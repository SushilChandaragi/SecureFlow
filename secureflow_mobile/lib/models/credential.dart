// Credential — maps to passwords.enc JSON payload
// JSON payload format (from desktop): [{website, username, password, notes?}, ...]
class Credential {
  final String website;
  final String username;
  final String password;
  final String notes;

  const Credential({
    required this.website,
    required this.username,
    required this.password,
    this.notes = '',
  });

  factory Credential.fromJson(Map<String, dynamic> json) => Credential(
        website:  (json['website']  as String?) ?? '',
        username: (json['username'] as String?) ?? '',
        password: (json['password'] as String?) ?? '',
        notes:    (json['notes']    as String?) ?? '',
      );

  Map<String, dynamic> toJson() => {
        'website':  website,
        'username': username,
        'password': password,
        'notes':    notes,
      };

  /// Composite key used by the desktop to index credentials.
  String get storeKey => '$website|$username';

  @override
  String toString() => 'Credential($website, $username)';
}
