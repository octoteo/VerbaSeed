import 'dart:io';
import 'dart:ui' as ui;

import 'package:document_processing/document_processing.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';

import 'layout_normalizer.dart';

final class GoogleMlKitTextExtractor implements DocumentExtractor {
  const GoogleMlKitTextExtractor();

  static bool get isSupportedPlatform => Platform.isAndroid || Platform.isIOS;

  @override
  String get id => 'google-mlkit-text-latin';

  @override
  bool supportsMimeType(String mimeType) => _supportsImageMimeType(mimeType);

  @override
  Future<ExtractedDocument> extract(DocumentExtractionRequest request) async {
    if (!isSupportedPlatform) {
      throw const DocumentExtractionException(
        code: 'ocr_unsupported_platform',
        message: 'Google ML Kit OCR 当前仅支持 Android/iOS 原生运行时',
        retryable: false,
      );
    }
    if (!supportsMimeType(request.mimeType)) {
      throw DocumentExtractionException(
        code: 'unsupported_mime_type',
        message: 'Google ML Kit OCR 不支持 ${request.mimeType}',
        retryable: false,
      );
    }

    final dimensions = await _decodeImageDimensions(request.bytes);
    final directory = await getTemporaryDirectory();
    final extension = _extensionForMimeType(request.mimeType);
    final safeAssetId = request.assetId.replaceAll(
      RegExp('[^A-Za-z0-9._-]'),
      '_',
    );
    final file = File(
      '${directory.path}/verbaseed-ocr-$safeAssetId-'
      '${DateTime.now().microsecondsSinceEpoch}.$extension',
    );
    TextRecognizer? recognizer;

    try {
      await file.writeAsBytes(request.bytes, flush: true);
      recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final recognized = await recognizer.processImage(
        InputImage.fromFilePath(file.path),
      );
      final blocks = <DocumentTextBlock>[];
      for (final block in recognized.blocks) {
        final text = block.text.trim();
        if (text.isEmpty) continue;
        final bounds = block.boundingBox;
        blocks.add(
          DocumentTextBlock(
            text: text,
            bounds: normalizeMlKitRect(
              left: bounds.left,
              top: bounds.top,
              right: bounds.right,
              bottom: bounds.bottom,
              imageWidth: dimensions.width,
              imageHeight: dimensions.height,
            ),
            language: _firstLanguage(block.recognizedLanguages),
          ),
        );
      }

      return ExtractedDocument(
        assetId: request.assetId,
        mimeType: request.mimeType,
        providerId: id,
        extractedAt: DateTime.now().toUtc(),
        pages: [
          ExtractedPage(
            pageNumber: 1,
            text: recognized.text,
            blocks: blocks,
          ),
        ],
        metadata: {
          'script': 'latin',
          'imageWidth': dimensions.width,
          'imageHeight': dimensions.height,
          'blockCount': blocks.length,
          'emptyText': recognized.text.trim().isEmpty,
        },
      );
    } on DocumentExtractionException {
      rethrow;
    } on MissingPluginException catch (error) {
      throw DocumentExtractionException(
        code: 'ocr_runtime_unavailable',
        message: '$error',
        retryable: false,
      );
    } on PlatformException catch (error) {
      throw DocumentExtractionException(
        code: 'ocr_platform_failure',
        message: error.message ?? error.code,
        retryable: true,
      );
    } on FormatException catch (error) {
      throw DocumentExtractionException(
        code: 'ocr_invalid_image',
        message: error.message,
        retryable: false,
      );
    } on Object catch (error) {
      throw DocumentExtractionException(
        code: 'ocr_runtime_failure',
        message: '$error',
        retryable: true,
      );
    } finally {
      if (recognizer != null) {
        try {
          await recognizer.close();
        } on Object {
          // Cleanup failures must not replace the extraction outcome.
        }
      }
      if (await file.exists()) {
        try {
          await file.delete();
        } on Object {
          // Temporary cleanup is best-effort; source assets live elsewhere.
        }
      }
    }
  }

  Future<({int width, int height})> _decodeImageDimensions(
    List<int> bytes,
  ) async {
    ui.Codec? codec;
    ui.Image? image;
    try {
      codec = await ui.instantiateImageCodec(Uint8List.fromList(bytes));
      final frame = await codec.getNextFrame();
      image = frame.image;
      return (width: image.width, height: image.height);
    } on Object catch (error) {
      throw FormatException('无法解码图片尺寸：$error');
    } finally {
      image?.dispose();
      codec?.dispose();
    }
  }
}

bool _supportsImageMimeType(String mimeType) => switch (
      mimeType.split(';').first.trim().toLowerCase()
    ) {
      'image/jpeg' || 'image/png' || 'image/webp' => true,
      _ => false,
    };

String _extensionForMimeType(String mimeType) => switch (
      mimeType.split(';').first.trim().toLowerCase()
    ) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      _ => 'jpg',
    };

String? _firstLanguage(List<String> languages) {
  for (final language in languages) {
    final normalized = language.trim();
    if (normalized.isNotEmpty) return normalized;
  }
  return null;
}
