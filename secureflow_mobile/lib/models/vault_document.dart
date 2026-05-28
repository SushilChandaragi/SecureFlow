// VaultDocument — local encrypted document stored in SQLite
class VaultDocument {
  final String id;
  final String name;
  final int size;       // bytes (plaintext size)
  final String mimeType;
  final DateTime updatedAt;
  final bool isSynced;  // true = S3 copy up-to-date

  const VaultDocument({
    required this.id,
    required this.name,
    required this.size,
    required this.mimeType,
    required this.updatedAt,
    this.isSynced = false,
  });

  VaultDocument copyWith({bool? isSynced}) => VaultDocument(
        id:        id,
        name:      name,
        size:      size,
        mimeType:  mimeType,
        updatedAt: updatedAt,
        isSynced:  isSynced ?? this.isSynced,
      );

  /// Human-readable file size string.
  String get sizeLabel {
    if (size < 1024) return '${size}B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)}KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)}MB';
  }

  /// Icon name hint based on MIME type.
  bool get isPdf   => mimeType == 'application/pdf';
  bool get isImage => mimeType.startsWith('image/');
  bool get isText  => mimeType.startsWith('text/');
}
