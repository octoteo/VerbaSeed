import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:document_processing/document_processing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_extractor_pdfrx/pdf_extractor_pdfrx.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final pdfiumPath = Platform.environment['PDFIUM_PATH'];

  test(
    'renders selected PDF pages to bounded PNG images',
    () async {
      final temporaryDirectory = await Directory.systemTemp.createTemp(
        'verbaseed-pdfrx-raster-test-',
      );
      Pdfrx.pdfiumModulePath = pdfiumPath!;
      Pdfrx.cacheDirectoryPath = temporaryDirectory.path;
      addTearDown(() async {
        if (await temporaryDirectory.exists()) {
          await temporaryDirectory.delete(recursive: true);
        }
      });

      const rasterizer = PdfrxPdfPageRasterizer(
        targetDpi: 144,
        maxDimension: 1200,
      );
      final pages = await rasterizer
          .rasterize(
            PdfRasterizationRequest(
              assetId: 'pdf-asset',
              mimeType: 'application/pdf',
              bytes: _buildSimplePdf(),
              sourceName: 'fixture.pdf',
              pageRange: PageRange(startPage: 1),
            ),
          )
          .toList();

      expect(pages, hasLength(1));
      final page = pages.single;
      expect(page.sourceAssetId, 'pdf-asset');
      expect(page.pageNumber, 1);
      expect(page.mimeType, 'image/png');
      expect(page.width, greaterThan(0));
      expect(page.height, greaterThan(0));
      expect(page.width, lessThanOrEqualTo(1200));
      expect(page.height, lessThanOrEqualTo(1200));
      expect(
        page.bytes.take(8).toList(),
        [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a],
      );
    },
    skip: pdfiumPath == null
        ? 'Set PDFIUM_PATH to run the real PDFium raster fixture.'
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
