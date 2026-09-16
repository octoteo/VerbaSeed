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
      message: '当前 VerbaSeed 构建仅在 Android 配置本地中英 OCR；不会自动切换到云端服务',
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
