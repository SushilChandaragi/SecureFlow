// VaultFile — maps encrypted asset entries from local vault + S3
class VaultFile {
  final String name;
  final String source;          // 'local' | 'cloud'
  final DateTime? lastModified;
  final int sizeBytes;
  final String classification;  // 'CONFIDENTIAL' | 'RESTRICTED' | 'CLASSIFIED'

  const VaultFile({
    required this.name,
    required this.source,
    this.lastModified,
    this.sizeBytes = 0,
    this.classification = 'CONFIDENTIAL',
  });

  String get displayName => name.replaceAll('.enc', '');

  String get formattedSize {
    if (sizeBytes < 1024) return '${sizeBytes}B';
    if (sizeBytes < 1048576) return '${(sizeBytes / 1024).toStringAsFixed(1)}KB';
    return '${(sizeBytes / 1048576).toStringAsFixed(1)}MB';
  }

  bool get isCloud => source == 'cloud';
  bool get isLocal => source == 'local';

  @override
  String toString() => 'VaultFile($name, $source)';
}
