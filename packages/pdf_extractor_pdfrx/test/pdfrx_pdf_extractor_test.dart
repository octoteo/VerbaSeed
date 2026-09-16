import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:document_processing/document_processing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_extractor_pdfrx/pdf_extractor_pdfrx.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const extractor = PdfrxPdfExtractor();
  final pdfiumPath = Platform.environment['PDFIUM_PATH'];

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

  test(
    'extracts text and normalized layout from a real PDF',
    () async {
      final temporaryDirectory = await Directory.systemTemp.createTemp(
        'verbaseed-pdfrx-test-',
      );
      Pdfrx.pdfiumModulePath = pdfiumPath!;
      Pdfrx.cacheDirectoryPath = temporaryDirectory.path;
      addTearDown(() async {
        if (await temporaryDirectory.exists()) {
          await temporaryDirectory.delete(recursive: true);
        }
      });

      final document = await extractor.extract(
        DocumentExtractionRequest(
          assetId: 'asset-real-pdf',
          mimeType: 'application/pdf',
          bytes: _buildSimplePdf(),
          sourceName: 'fixture.pdf',
        ),
      );

      expect(document.providerId, extractor.id);
      expect(document.pages, hasLength(1));
      expect(document.plainText, contains('Hello VerbaSeed'));
      final blocks = document.pages.single.blocks;
      expect(blocks, isNotEmpty);
      final blockText = blocks.map((block) => block.text).join(' ');
      expect(blockText, contains('Hello'));
      expect(blockText, contains('VerbaSeed'));
      for (final block in blocks) {
        final bounds = block.bounds;
        if (bounds == null) continue;
        expect(bounds.left, inInclusiveRange(0.0, 1.0));
        expect(bounds.top, inInclusiveRange(0.0, 1.0));
        expect(bounds.left + bounds.width, lessThanOrEqualTo(1.0));
        expect(bounds.top + bounds.height, lessThanOrEqualTo(1.0));
      }
    },
    skip: pdfiumPath == null
        ? 'Set PDFIUM_PATH to run the real PDFium extraction fixture.'
        : false,
  );
}

Uint8List _buildSimplePdf() {
  const textStream = 'BT\n/F1 24 Tf\n72 720 Td\n(Hello VerbaSeed) Tj\nET\n';
  final bytes = <int>[];
  final offsets = List<int>.filled(6, 0);

  void write(String value) => bytes.addAll(utf8.encode(value));

  void addObject(int number, String body) {
    offsets[number] = bytes.length;
    write('$number 0 obj\n$body\nendobj\n');
  }

  write('%PDF-1.4\n');
  addObject(1, '<< /Type /Catalog /Pages 2 0 R >>');
  addObject(2, '<< /Type /Pages /Kids [3 0 R] /Count 1 >>');
  addObject(
    3,
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
    '/Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',
  );
  addObject(4, '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>');
  addObject(
    5,
    '<< /Length ${utf8.encode(textStream).length} >>\n'
    'stream\n$textStream'
    'endstream',
  );

  final xrefOffset = bytes.length;
  write('xref\n0 6\n');
  write('0000000000 65535 f \n');
  for (var object = 1; object <= 5; object++) {
    write('${offsets[object].toString().padLeft(10, '0')} 00000 n \n');
  }
  write(
    'trailer\n<< /Size 6 /Root 1 0 R >>\n'
    'startxref\n$xrefOffset\n%%EOF\n',
  );

  return Uint8List.fromList(bytes);
}
