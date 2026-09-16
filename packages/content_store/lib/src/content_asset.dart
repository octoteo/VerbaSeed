import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

final class ContentAsset {
  const ContentAsset({
    required this.id,
    required this.fileName,
    required this.mimeType,
    required this.byteLength,
    required this.sha256,
    required this.createdAt,
  });

  final String id;
  final String fileName;
  final String mimeType;
  final int byteLength;
  final String sha256;
  final DateTime createdAt;

  factory ContentAsset.fromBytes({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    DateTime? createdAt,
  }) {
    final digest = crypto.sha256.convert(bytes).toString();
    return ContentAsset(
      id: digest,
      fileName: _sanitizeDisplayName(fileName),
      mimeType: mimeType.trim().isEmpty ? 'application/octet-stream' : mimeType.trim(),
      byteLength: bytes.length,
      sha256: digest,
      createdAt: (createdAt ?? DateTime.now()).toUtc(),
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'fileName': fileName,
        'mimeType': mimeType,
        'byteLength': byteLength,
        'sha256': sha256,
        'createdAt': createdAt.toUtc().toIso8601String(),
      };

  factory ContentAsset.fromJson(Map<String, Object?> json) => ContentAsset(
        id: json['id']! as String,
        fileName: json['fileName']! as String,
        mimeType: json['mimeType']! as String,
        byteLength: (json['byteLength']! as num).toInt(),
        sha256: json['sha256']! as String,
        createdAt: DateTime.parse(json['createdAt']! as String).toUtc(),
      );
}

String _sanitizeDisplayName(String input) {
  final value = input.trim().replaceAll(RegExp(r'[\x00-\x1F]'), '');
  if (value.isEmpty) return 'imported-file';
  return value.length <= 240 ? value : value.substring(value.length - 240);
}
