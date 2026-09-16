import 'dart:typed_data';

import 'package:document_processing/document_processing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocr_google_mlkit/ocr_google_mlkit.dart';
import 'package:ocr_google_mlkit/src/layout_normalizer.dart';

void main() {
  const extractor = GoogleMlKitTextExtractor();

  test('supports the image MIME types used by VerbaSeed imports', () {
    expect(extractor.supportsMimeType('image/jpeg'), isTrue);
    expect(extractor.supportsMimeType('image/png'), isTrue);
    expect(extractor.supportsMimeType('image/webp'), isTrue);
    expect(extractor.supportsMimeType('application/pdf'), isFalse);
  });

  test('normalizes and clamps ML Kit bounding boxes', () {
    final rect = normalizeMlKitRect(
      left: -10,
      top: 20,
      right: 110,
      bottom: 90,
      imageWidth: 100,
      imageHeight: 100,
    );

    expect(rect.left, 0);
    expect(rect.top, 0.2);
    expect(rect.width, 1);
    expect(rect.height, 0.7);
  });

  test('non-mobile test hosts fail explicitly without invoking ML Kit', () async {
    if (GoogleMlKitTextExtractor.isSupportedPlatform) return;

    await expectLater(
      extractor.extract(
        DocumentExtractionRequest(
          assetId: 'asset-image',
          mimeType: 'image/jpeg',
          bytes: Uint8List.fromList([1, 2, 3]),
        ),
      ),
      throwsA(
        isA<DocumentExtractionException>()
            .having((error) => error.code, 'code', 'ocr_unsupported_platform')
            .having((error) => error.retryable, 'retryable', isFalse),
      ),
    );
  });
}
