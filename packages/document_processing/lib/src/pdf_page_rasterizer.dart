import 'dart:typed_data';

import 'models.dart';

final class PdfRasterizationRequest {
  PdfRasterizationRequest({
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
    if (this.mimeType.split(';').first.trim() != 'application/pdf') {
      throw const FormatException('PDF rasterization requires application/pdf');
    }
    if (this.bytes.isEmpty) {
      throw const FormatException('PDF bytes cannot be empty');
    }
  }

  final String assetId;
  final String mimeType;
  final Uint8List bytes;
  final PageRange? pageRange;
  final String? sourceName;
}

final class RasterizedPdfPage {
  RasterizedPdfPage({
    required this.sourceAssetId,
    required this.pageNumber,
    required String mimeType,
    required Uint8List bytes,
    required this.width,
    required this.height,
  })  : mimeType = mimeType.trim().toLowerCase(),
        bytes = Uint8List.fromList(bytes) {
    if (sourceAssetId.trim().isEmpty) {
      throw const FormatException('sourceAssetId cannot be empty');
    }
    if (pageNumber < 1) {
      throw RangeError.range(pageNumber, 1, null, 'pageNumber');
    }
    if (this.mimeType != 'image/png' && this.mimeType != 'image/jpeg') {
      throw const FormatException('Rasterized PDF pages must be PNG or JPEG');
    }
    if (this.bytes.isEmpty) {
      throw const FormatException('Rasterized PDF page bytes cannot be empty');
    }
    if (width < 1 || height < 1) {
      throw const FormatException('Rasterized PDF page dimensions must be positive');
    }
  }

  final String sourceAssetId;
  final int pageNumber;
  final String mimeType;
  final Uint8List bytes;
  final int width;
  final int height;
}

/// Produces one bounded page image at a time so scanned-document OCR does not
/// require holding a complete multi-page PDF rasterization in memory.
abstract interface class PdfPageRasterizer {
  String get id;

  Stream<RasterizedPdfPage> rasterize(PdfRasterizationRequest request);
}
