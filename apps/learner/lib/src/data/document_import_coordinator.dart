import 'dart:convert';
import 'dart:typed_data';

import 'package:content_source/content_source.dart';
import 'package:content_store/content_store.dart';
import 'package:document_processing/document_processing.dart';
import 'package:local_store/local_store.dart';

final class DocumentImportCoordinator {
  factory DocumentImportCoordinator({
    required ImportRepository repository,
    required ContentAssetStore assetStore,
    required DocumentExtractor pdfExtractor,
    DocumentExtractor? imageExtractor,
    PdfPageRasterizer? pdfPageRasterizer,
    bool imageExtractionAvailable = false,
    DocumentRetryStateMachine? stateMachine,
    DateTime Function()? clock,
  }) =>
      DocumentImportCoordinator._(
        repository,
        assetStore,
        pdfExtractor,
        imageExtractor: imageExtractor,
        pdfPageRasterizer: pdfPageRasterizer,
        imageExtractionAvailable: imageExtractionAvailable,
        stateMachine: stateMachine,
        clock: clock,
      );

  DocumentImportCoordinator._(
    this._repository,
    this._assetStore,
    this._pdfExtractor, {
    DocumentExtractor? imageExtractor,
    this._pdfPageRasterizer,
    required bool imageExtractionAvailable,
    DocumentRetryStateMachine? stateMachine,
    DateTime Function()? clock,
  })  : _imageExtractor = imageExtractor,
        imageExtractionAvailable =
            imageExtractionAvailable && imageExtractor != null,
        _stateMachine = stateMachine ?? DocumentRetryStateMachine(),
        _clock = clock ?? DateTime.now;

  static const extractionAssetMetadataKey = 'extractionAsset';
  static const courseDraftAssetMetadataKey = 'courseDraftAsset';

  final ImportRepository _repository;
  final ContentAssetStore _assetStore;
  final DocumentExtractor _pdfExtractor;
  final DocumentExtractor? _imageExtractor;
  final PdfPageRasterizer? _pdfPageRasterizer;
  final bool imageExtractionAvailable;
  final DocumentRetryStateMachine _stateMachine;
  final DateTime Function() _clock;
  final Set<String> _inFlight = <String>{};

  bool get pdfOcrFallbackAvailable =>
      imageExtractionAvailable && _pdfPageRasterizer != null;

  Future<DocumentProcessingState> processPdf(
    ImportJob job, {
    PageRange? pageRange,
    bool replacePageRange = false,
  }) async {
    var source = _repository.decodeSource(job);
    if (source.type != ContentSourceType.pdf) {
      throw StateError('仅 PDF 导入任务可以使用 PDF 解析器');
    }

    if (replacePageRange) {
      final metadata = <String, Object?>{...source.metadata};
      if (pageRange == null) {
        metadata.remove('pageRange');
      } else {
        metadata['pageRange'] = pageRange.toJson();
      }
      source = source.copyWith(metadata: metadata);
    }

    return _processDocument(
      job: job,
      source: source,
      extractor: _pdfExtractor,
      pageRange: _pageRangeFromMetadata(source.metadata),
    );
  }

  Future<DocumentProcessingState> processImage(ImportJob job) {
    final source = _repository.decodeSource(job);
    if (source.type != ContentSourceType.image &&
        source.type != ContentSourceType.cameraImage) {
      throw StateError('仅图片或拍照导入任务可以使用 OCR 解析器');
    }
    final extractor = _imageExtractor;
    if (!imageExtractionAvailable || extractor == null) {
      throw UnsupportedError('当前平台没有可用的本地图片 OCR 运行时');
    }
    return _processDocument(
      job: job,
      source: source,
      extractor: extractor,
    );
  }

  Future<DocumentProcessingState> _processDocument({
    required ImportJob job,
    required ContentSource source,
    required DocumentExtractor extractor,
    PageRange? pageRange,
  }) async {
    if (!_inFlight.add(job.id)) {
      throw StateError('文档解析任务正在执行: ${job.id}');
    }
    try {
      var resolvedSource = source;
      var state = documentProcessingStateFromMetadata(resolvedSource.metadata) ??
          _stateMachine.initial(at: _now());
      final recovered = _stateMachine.recoverInterrupted(state, at: _now());
      if (!_sameState(recovered, state)) {
        state = recovered;
        resolvedSource = resolvedSource.copyWith(
          metadata: withDocumentProcessingState(
            resolvedSource.metadata,
            state,
          ),
        );
        await _persistState(job.id, resolvedSource, state);
      }

      final startAt = _now();
      if (!_stateMachine.canStart(state, at: startAt)) {
        return state;
      }

      state = _stateMachine.begin(
        state,
        at: startAt,
        providerId: extractor.id,
      );
      resolvedSource = resolvedSource.copyWith(
        metadata: withDocumentProcessingState(
          resolvedSource.metadata,
          state,
        ),
      );
      await _persistState(job.id, resolvedSource, state);

      try {
        final asset = _decodeSourceAsset(resolvedSource.metadata);
        final bytes = await _assetStore.read(asset.id);
        if (bytes == null) {
          throw const DocumentExtractionException(
            code: 'content_asset_missing',
            message: '原始文件已不存在，无法继续解析',
            retryable: false,
          );
        }
        if (!extractor.supportsMimeType(asset.mimeType)) {
          throw DocumentExtractionException(
            code: 'unsupported_mime_type',
            message: '解析器 ${extractor.id} 不支持 ${asset.mimeType}',
            retryable: false,
          );
        }

        var document = await extractor.extract(
          DocumentExtractionRequest(
            assetId: asset.id,
            mimeType: asset.mimeType,
            bytes: bytes,
            sourceName: asset.fileName,
            pageRange: pageRange,
          ),
        );
        if (document.assetId != asset.id) {
          throw const DocumentExtractionException(
            code: 'asset_identity_mismatch',
            message: '解析结果与原始资产标识不一致',
            retryable: false,
          );
        }

        final textLayerEmptyPages = source.type == ContentSourceType.pdf
            ? _emptyPageNumbers(document)
            : const <int>[];
        var pdfOcrFallbackUsed = false;
        if (source.type == ContentSourceType.pdf &&
            textLayerEmptyPages.isNotEmpty &&
            pdfOcrFallbackAvailable) {
          document = await _ocrEmptyPdfPages(
            asset: asset,
            pdfBytes: bytes,
            textDocument: document,
            pageRange: pageRange,
            emptyPageNumbers: textLayerEmptyPages.toSet(),
          );
          pdfOcrFallbackUsed = true;
        }

        final resultBytes = Uint8List.fromList(
          utf8.encode(jsonEncode(document.toJson())),
        );
        final resultAsset = await _assetStore.put(
          bytes: resultBytes,
          fileName: '${asset.fileName}.extracted.json',
          mimeType: 'application/vnd.verbaseed.document-extraction+json',
        );

        final emptyText = document.plainText.trim().isEmpty;
        final unresolvedEmptyPages = _emptyPageNumbers(document);
        CourseDraftCompilation? compilation;
        ContentAsset? courseDraftAsset;
        String? compilationError;
        if (!emptyText) {
          try {
            compilation = const CourseDraftCompiler().compileExtractedDocument(
              document: document,
              courseId: _courseIdForAsset(asset),
              title: _courseTitleForAsset(asset),
            );
            final courseBytes = Uint8List.fromList(
              utf8.encode(jsonEncode(compilation.course.toJson())),
            );
            courseDraftAsset = await _assetStore.put(
              bytes: courseBytes,
              fileName: '${asset.fileName}.course-draft.json',
              mimeType: 'application/vnd.verbaseed.course+json',
            );
          } on Object catch (error) {
            compilationError = '$error';
          }
        }

        final completed = _stateMachine.succeed(state, at: _now());
        final courseNeedsReview =
            compilation?.requiresReview ?? (compilationError != null);
        final requiresReview =
            unresolvedEmptyPages.isNotEmpty || courseNeedsReview;
        final metadata = <String, Object?>{
          ...resolvedSource.metadata,
          extractionAssetMetadataKey: resultAsset.toJson(),
          'extractionProvider': document.providerId,
          'extractedPageCount': document.pages.length,
          'extractedTextLength': document.plainText.length,
          if (source.type == ContentSourceType.pdf) ...{
            'textLayerEmptyPages': textLayerEmptyPages,
            'requiresOcr':
                textLayerEmptyPages.isNotEmpty && !pdfOcrFallbackUsed,
            'pdfOcrFallbackUsed': pdfOcrFallbackUsed,
            if (pdfOcrFallbackUsed)
              'pdfOcrFallbackPages': textLayerEmptyPages,
            if (pdfOcrFallbackUsed)
              'ocrEmptyPageCount': unresolvedEmptyPages.length,
          } else
            'ocrEmpty': emptyText,
          'courseDraftStatus': emptyText
              ? 'skipped'
              : compilation != null
                  ? 'ready'
                  : 'needsReview',
          if (courseDraftAsset != null)
            courseDraftAssetMetadataKey: courseDraftAsset.toJson(),
          if (compilation != null) ...compilation.toMetadata(),
          if (unresolvedEmptyPages.isNotEmpty && compilation != null)
            'courseDraftWarnings': [
              ...compilation.warnings,
              '仍有 ${unresolvedEmptyPages.length} 页未识别到文字，建议人工复核。',
            ],
          'courseDraftError': ?compilationError,
          'requiresReview': requiresReview,
        };
        resolvedSource = resolvedSource.copyWith(
          metadata: withDocumentProcessingState(metadata, completed),
        );
        await _repository.replaceSource(
          job.id,
          resolvedSource,
          state: ImportJobState.ready,
        );
        return completed;
      } on DocumentExtractionException catch (error) {
        return await _persistFailure(
          jobId: job.id,
          source: resolvedSource,
          running: state,
          code: error.code,
          message: error.message,
          retryable: error.retryable,
        );
      } on FormatException catch (error) {
        return await _persistFailure(
          jobId: job.id,
          source: resolvedSource,
          running: state,
          code: 'invalid_import_metadata',
          message: error.message,
          retryable: false,
        );
      } on StateError catch (error) {
        return await _persistFailure(
          jobId: job.id,
          source: resolvedSource,
          running: state,
          code: 'content_asset_invalid',
          message: '$error',
          retryable: false,
        );
      } on Object catch (error) {
        return await _persistFailure(
          jobId: job.id,
          source: resolvedSource,
          running: state,
          code: 'document_pipeline_failure',
          message: '$error',
          retryable: true,
        );
      }
    } finally {
      _inFlight.remove(job.id);
    }
  }

  Future<ExtractedDocument> _ocrEmptyPdfPages({
    required ContentAsset asset,
    required Uint8List pdfBytes,
    required ExtractedDocument textDocument,
    required PageRange? pageRange,
    required Set<int> emptyPageNumbers,
  }) async {
    final rasterizer = _pdfPageRasterizer;
    final imageExtractor = _imageExtractor;
    if (rasterizer == null || imageExtractor == null || !imageExtractionAvailable) {
      return textDocument;
    }

    final pagesByNumber = <int, ExtractedPage>{
      for (final page in textDocument.pages) page.pageNumber: page,
    };
    final resolvedEmptyPages = <int>{};

    await for (final rasterized in rasterizer.rasterize(
      PdfRasterizationRequest(
        assetId: asset.id,
        mimeType: asset.mimeType,
        bytes: pdfBytes,
        sourceName: asset.fileName,
        pageRange: pageRange,
      ),
    )) {
      if (rasterized.sourceAssetId != asset.id) {
        throw const DocumentExtractionException(
          code: 'pdf_raster_asset_identity_mismatch',
          message: 'PDF 页面渲染结果与原始资产标识不一致',
          retryable: false,
        );
      }
      if (!emptyPageNumbers.contains(rasterized.pageNumber)) continue;
      if (!imageExtractor.supportsMimeType(rasterized.mimeType)) {
        throw DocumentExtractionException(
          code: 'ocr_raster_mime_unsupported',
          message: '本地 OCR 不支持渲染格式 ${rasterized.mimeType}',
          retryable: false,
        );
      }

      final pageAssetId = '${asset.id}-page-${rasterized.pageNumber}';
      final recognized = await imageExtractor.extract(
        DocumentExtractionRequest(
          assetId: pageAssetId,
          mimeType: rasterized.mimeType,
          bytes: rasterized.bytes,
          sourceName: '${asset.fileName}.page-${rasterized.pageNumber}.png',
        ),
      );
      if (recognized.assetId != pageAssetId) {
        throw const DocumentExtractionException(
          code: 'ocr_page_asset_identity_mismatch',
          message: 'OCR 页面结果与渲染页面标识不一致',
          retryable: false,
        );
      }

      pagesByNumber[rasterized.pageNumber] = ExtractedPage(
        pageNumber: rasterized.pageNumber,
        text: recognized.plainText,
        blocks: recognized.pages.expand((page) => page.blocks),
      );
      resolvedEmptyPages.add(rasterized.pageNumber);
    }

    final missingPages = emptyPageNumbers.difference(resolvedEmptyPages);
    if (missingPages.isNotEmpty) {
      throw DocumentExtractionException(
        code: 'pdf_raster_pages_missing',
        message: 'PDF OCR 缺少渲染页：${missingPages.toList()..sort()}',
        retryable: true,
      );
    }

    final pages = pagesByNumber.values.toList(growable: false)
      ..sort((left, right) => left.pageNumber.compareTo(right.pageNumber));
    return ExtractedDocument(
      assetId: asset.id,
      mimeType: 'application/pdf',
      providerId:
          '${textDocument.providerId}+${rasterizer.id}+${imageExtractor.id}',
      extractedAt: _now(),
      pages: pages,
      metadata: {
        ...textDocument.metadata,
        'textLayerProvider': textDocument.providerId,
        'pdfRasterizer': rasterizer.id,
        'ocrProvider': imageExtractor.id,
        'ocrFallback': true,
        'ocrFallbackPages': emptyPageNumbers.toList()..sort(),
      },
    );
  }

  Future<DocumentProcessingState> _persistFailure({
    required String jobId,
    required ContentSource source,
    required DocumentProcessingState running,
    required String code,
    required String message,
    required bool retryable,
  }) async {
    final failed = _stateMachine.fail(
      running,
      at: _now(),
      retryable: retryable,
      code: code,
      message: message,
    );
    final resolved = source.copyWith(
      metadata: withDocumentProcessingState(source.metadata, failed),
    );
    await _persistState(jobId, resolved, failed);
    return failed;
  }

  Future<void> _persistState(
    String jobId,
    ContentSource source,
    DocumentProcessingState state,
  ) =>
      _repository.replaceSource(
        jobId,
        source,
        state: _importStateFor(state),
        errorMessage: state.phase == DocumentProcessingPhase.failed
            ? state.lastErrorMessage
            : null,
      );

  ContentAsset _decodeSourceAsset(Map<String, Object?> metadata) {
    final raw = metadata['asset'];
    if (raw is! Map) {
      throw const FormatException('导入任务缺少原始文件资产元数据');
    }
    return ContentAsset.fromJson(Map<String, Object?>.from(raw));
  }

  PageRange? _pageRangeFromMetadata(Map<String, Object?> metadata) {
    final raw = metadata['pageRange'];
    if (raw == null) return null;
    if (raw is! Map) {
      throw const FormatException('pageRange 元数据格式无效');
    }
    return PageRange.fromJson(Map<String, Object?>.from(raw));
  }

  ImportJobState _importStateFor(DocumentProcessingState state) =>
      switch (state.phase) {
        DocumentProcessingPhase.queued ||
        DocumentProcessingPhase.retryScheduled => ImportJobState.queued,
        DocumentProcessingPhase.extracting => ImportJobState.processing,
        DocumentProcessingPhase.succeeded => ImportJobState.ready,
        DocumentProcessingPhase.failed => ImportJobState.failed,
        DocumentProcessingPhase.cancelled => ImportJobState.cancelled,
      };

  static List<int> _emptyPageNumbers(ExtractedDocument document) => [
        for (final page in document.pages)
          if (page.text.trim().isEmpty) page.pageNumber,
      ];

  static String _courseIdForAsset(ContentAsset asset) {
    final normalized = asset.id
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9._-]'), '-');
    final prefixLength = normalized.length < 16 ? normalized.length : 16;
    return 'import-${normalized.substring(0, prefixLength)}';
  }

  static String _courseTitleForAsset(ContentAsset asset) {
    final name = asset.fileName.trim();
    if (name.isEmpty) return 'Imported course';
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  bool _sameState(
    DocumentProcessingState left,
    DocumentProcessingState right,
  ) =>
      jsonEncode(left.toJson()) == jsonEncode(right.toJson());

  DateTime _now() => _clock().toUtc();
}
