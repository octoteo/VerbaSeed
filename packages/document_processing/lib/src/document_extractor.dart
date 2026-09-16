import 'dart:typed_data';

import 'models.dart';

final class DocumentExtractionRequest {
  DocumentExtractionRequest({
    required String assetId,
    required String mimeType,
    required Uint8List bytes,
    this.pageRange,
    this.sourceName,
  })  : assetId = assetId.trim(),
        mimeType = mimeType.trim().toLowerCase(),
        bytes = Uint8List.fromList(bytes) {
    if (this.assetId.isEmpty) {
      throw const FormatException('assetId cannot be empty');
    }
    if (this.mimeType.isEmpty) {
      throw const FormatException('mimeType cannot be empty');
    }
    if (this.bytes.isEmpty) {
      throw const FormatException('document bytes cannot be empty');
    }
  }

  final String assetId;
  final String mimeType;
  final Uint8List bytes;
  final PageRange? pageRange;
  final String? sourceName;
}

abstract interface class DocumentExtractor {
  String get id;

  bool supportsMimeType(String mimeType);

  Future<ExtractedDocument> extract(DocumentExtractionRequest request);
}

final class DocumentExtractionException implements Exception {
  const DocumentExtractionException({
    required this.code,
    required this.message,
    required this.retryable,
  });

  final String code;
  final String message;
  final bool retryable;

  @override
  String toString() => 'DocumentExtractionException($code): $message';
}
