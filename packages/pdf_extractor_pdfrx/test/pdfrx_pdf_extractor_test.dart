import 'dart:typed_data';

import 'package:document_processing/document_processing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_extractor_pdfrx/pdf_extractor_pdfrx.dart';

void main() {
  const extractor = PdfrxPdfExtractor();

  test('advertises PDF MIME support only', () {
    expect(extractor.supportsMimeType('application/pdf'), isTrue);
    expect(
      extractor.supportsMimeType('application/pdf; charset=binary'),
      isTrue,
    );
    expect(extractor.supportsMimeType('image/png'), isFalse);
  });

  test('rejects non-PDF requests before initializing PDFium', () async {
    final request = DocumentExtractionRequest(
      assetId: 'asset-1',
      mimeType: 'image/png',
      bytes: Uint8List.fromList([1, 2, 3]),
      sourceName: 'image.png',
    );

    await expectLater(
      extractor.extract(request),
      throwsA(
        isA<DocumentExtractionException>()
            .having((error) => error.code, 'code', 'unsupported_mime_type')
            .having((error) => error.retryable, 'retryable', isFalse),
      ),
    );
  });
}
