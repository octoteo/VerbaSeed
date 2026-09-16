import 'dart:ui' show Rect;

import 'package:document_processing/document_processing.dart';
import 'package:pdfrx/pdfrx.dart';

final class PdfrxPdfExtractor implements DocumentExtractor {
  const PdfrxPdfExtractor();

  @override
  String get id => 'pdfrx-pdfium';

  @override
  bool supportsMimeType(String mimeType) =>
      mimeType.split(';').first.trim().toLowerCase() == 'application/pdf';

  @override
  Future<ExtractedDocument> extract(DocumentExtractionRequest request) async {
    if (!supportsMimeType(request.mimeType)) {
      throw DocumentExtractionException(
        code: 'unsupported_mime_type',
        message: 'PdfrxPdfExtractor 不支持 ${request.mimeType}',
        retryable: false,
      );
    }

    await pdfrxFlutterInitialize();

    PdfDocument? document;
    try {
      document = await PdfDocument.openData(
        request.bytes,
        sourceName: request.sourceName ?? request.assetId,
      );
      final totalPages = document.pages.length;
      final range = _resolvePageRange(request.pageRange, totalPages);
      final pages = <ExtractedPage>[];

      for (var pageNumber = range.startPage;
          pageNumber <= range.endPage;
          pageNumber++) {
        final page = document.pages[pageNumber - 1];
        final pageText = await page.loadStructuredText();
        final blocks = <DocumentTextBlock>[];

        for (final fragment in pageText.fragments) {
          final text = fragment.text.trim();
          if (text.isEmpty) continue;
          final rect = fragment.bounds.toRect(page: page);
          blocks.add(
            DocumentTextBlock(
              text: text,
              bounds: _normalizeRect(rect, page.width, page.height),
            ),
          );
        }

        pages.add(
          ExtractedPage(
            pageNumber: pageNumber,
            text: pageText.fullText,
            blocks: blocks,
          ),
        );
      }

      return ExtractedDocument(
        assetId: request.assetId,
        mimeType: 'application/pdf',
        providerId: id,
        extractedAt: DateTime.now().toUtc(),
        pages: pages,
        metadata: {
          'totalPages': totalPages,
          'startPage': range.startPage,
          'endPage': range.endPage,
          'encrypted': document.isEncrypted,
          'textLayer': true,
        },
      );
    } on DocumentExtractionException {
      rethrow;
    } on PdfPasswordException catch (error) {
      throw DocumentExtractionException(
        code: 'pdf_password_required',
        message: error.message,
        retryable: false,
      );
    } on PdfException catch (error) {
      throw DocumentExtractionException(
        code: 'pdf_parse_failed',
        message: error.message,
        retryable: false,
      );
    } on Object catch (error) {
      throw DocumentExtractionException(
        code: 'pdf_runtime_failure',
        message: '$error',
        retryable: true,
      );
    } finally {
      await document?.dispose();
    }
  }

  PageRange _resolvePageRange(PageRange? requested, int totalPages) {
    if (totalPages < 1) {
      throw const DocumentExtractionException(
        code: 'pdf_has_no_pages',
        message: 'PDF 不包含可解析页面',
        retryable: false,
      );
    }
    final range = requested ?? PageRange(startPage: 1, endPage: totalPages);
    if (range.startPage > totalPages || range.endPage > totalPages) {
      throw DocumentExtractionException(
        code: 'page_range_out_of_bounds',
        message: '请求页码 ${range.startPage}-${range.endPage} 超出 PDF 总页数 $totalPages',
        retryable: false,
      );
    }
    return range;
  }

  DocumentRect _normalizeRect(Rect rect, double pageWidth, double pageHeight) {
    if (pageWidth <= 0 || pageHeight <= 0) {
      throw const DocumentExtractionException(
        code: 'invalid_pdf_page_size',
        message: 'PDF 页面尺寸无效',
        retryable: false,
      );
    }
    final left = (rect.left / pageWidth).clamp(0.0, 1.0).toDouble();
    final top = (rect.top / pageHeight).clamp(0.0, 1.0).toDouble();
    final right = (rect.right / pageWidth).clamp(left, 1.0).toDouble();
    final bottom = (rect.bottom / pageHeight).clamp(top, 1.0).toDouble();
    return DocumentRect(
      left: left,
      top: top,
      width: right - left,
      height: bottom - top,
    );
  }
}
