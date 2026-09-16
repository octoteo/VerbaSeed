import 'package:document_processing/document_processing.dart';

final class GoogleMlKitTextExtractor implements DocumentExtractor {
  const GoogleMlKitTextExtractor();

  static bool get isSupportedPlatform => false;

  @override
  String get id => 'google-mlkit-text-zh-latin';

  @override
  bool supportsMimeType(String mimeType) => _supportsImageMimeType(mimeType);

  @override
  Future<ExtractedDocument> extract(DocumentExtractionRequest request) {
    throw const DocumentExtractionException(
      code: 'ocr_unsupported_platform',
      message: 'Google ML Kit OCR 当前仅支持 Android/iOS 原生运行时',
      retryable: false,
    );
  }
}

bool _supportsImageMimeType(String mimeType) => switch (
      mimeType.split(';').first.trim().toLowerCase()
    ) {
      'image/jpeg' || 'image/png' || 'image/webp' => true,
      _ => false,
    };
