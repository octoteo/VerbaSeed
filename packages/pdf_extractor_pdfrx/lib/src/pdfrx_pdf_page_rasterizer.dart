import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:document_processing/document_processing.dart';
import 'package:pdfrx/pdfrx.dart';

final class PdfrxPdfPageRasterizer implements PdfPageRasterizer {
  const PdfrxPdfPageRasterizer({
    this.targetDpi = 200,
    this.maxDimension = 3200,
  })  : assert(targetDpi > 0),
        assert(maxDimension > 0);

  final double targetDpi;
  final int maxDimension;

  @override
  String get id => 'pdfrx-pdfium-raster';

  @override
  Stream<RasterizedPdfPage> rasterize(PdfRasterizationRequest request) async* {
    await pdfrxFlutterInitialize();

    PdfDocument? document;
    try {
      document = await PdfDocument.openData(
        request.bytes,
        sourceName: request.sourceName ?? request.assetId,
      );
      final totalPages = document.pages.length;
      final range = _resolvePageRange(request.pageRange, totalPages);

      for (var pageNumber = range.startPage;
          pageNumber <= range.endPage;
          pageNumber++) {
        final page = document.pages[pageNumber - 1];
        final size = _targetSize(page.width, page.height);
        PdfImage? rendered;
        ui.Image? uiImage;
        try {
          rendered = await page.render(
            width: size.width,
            height: size.height,
            fullWidth: size.width.toDouble(),
            fullHeight: size.height.toDouble(),
            backgroundColor: 0xffffffff,
          );
          if (rendered == null) {
            throw DocumentExtractionException(
              code: 'pdf_page_render_failed',
              message: '无法渲染 PDF 第 $pageNumber 页',
              retryable: true,
            );
          }
          uiImage = await rendered.createImage();
          final encoded = await uiImage.toByteData(format: ui.ImageByteFormat.png);
          if (encoded == null || encoded.lengthInBytes == 0) {
            throw DocumentExtractionException(
              code: 'pdf_page_encode_failed',
              message: '无法编码 PDF 第 $pageNumber 页的 OCR 图片',
              retryable: true,
            );
          }
          yield RasterizedPdfPage(
            sourceAssetId: request.assetId,
            pageNumber: pageNumber,
            mimeType: 'image/png',
            bytes: Uint8List.fromList(
              encoded.buffer.asUint8List(
                encoded.offsetInBytes,
                encoded.lengthInBytes,
              ),
            ),
            width: rendered.width,
            height: rendered.height,
          );
        } finally {
          uiImage?.dispose();
          rendered?.dispose();
        }
      }
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
        code: 'pdf_rasterization_failed',
        message: error.message,
        retryable: false,
      );
    } on Object catch (error) {
      throw DocumentExtractionException(
        code: 'pdf_rasterization_runtime_failure',
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
        message: 'PDF 不包含可渲染页面',
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

  ({int width, int height}) _targetSize(double pageWidth, double pageHeight) {
    if (!pageWidth.isFinite ||
        !pageHeight.isFinite ||
        pageWidth <= 0 ||
        pageHeight <= 0) {
      throw const DocumentExtractionException(
        code: 'invalid_pdf_page_size',
        message: 'PDF 页面尺寸无效，无法进行 OCR 渲染',
        retryable: false,
      );
    }

    var scale = targetDpi / 72.0;
    final longestAtTargetDpi =
        (pageWidth > pageHeight ? pageWidth : pageHeight) * scale;
    if (longestAtTargetDpi > maxDimension) {
      scale *= maxDimension / longestAtTargetDpi;
    }
    final width = (pageWidth * scale).round().clamp(1, maxDimension);
    final height = (pageHeight * scale).round().clamp(1, maxDimension);
    return (width: width, height: height);
  }
}
