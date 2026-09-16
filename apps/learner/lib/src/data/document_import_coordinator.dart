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
    bool imageExtractionAvailable = false,
    DocumentRetryStateMachine? stateMachine,
    DateTime Function()? clock,
  }) =>
      DocumentImportCoordinator._(
        repository,
        assetStore,
        pdfExtractor,
        imageExtractor: imageExtractor,
        imageExtractionAvailable: imageExtractionAvailable,
        stateMachine: stateMachine,
        clock: clock,
      );

  DocumentImportCoordinator._(
    this._repository,
    this._assetStore,
    this._pdfExtractor, {
    DocumentExtractor? imageExtractor,
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
  final bool imageExtractionAvailable;
  final DocumentRetryStateMachine _stateMachine;
  final DateTime Function() _clock;
  final Set<String> _inFlight = <String>{};

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
      emptyTextMetadataKey: 'requiresOcr',
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
      emptyTextMetadataKey: 'ocrEmpty',
    );
  }

  Future<DocumentProcessingState> _processDocument({
    required ImportJob job,
    required ContentSource source,
    required DocumentExtractor extractor,
    PageRange? pageRange,
    required String emptyTextMetadataKey,
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

        final document = await extractor.extract(
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

        final resultBytes = Uint8List.fromList(
          utf8.encode(jsonEncode(document.toJson())),
        );
        final resultAsset = await _assetStore.put(
          bytes: resultBytes,
          fileName: '${asset.fileName}.extracted.json',
          mimeType: 'application/vnd.verbaseed.document-extraction+json',
        );

        final emptyText = document.plainText.trim().isEmpty;
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
        final metadata = <String, Object?>{
          ...resolvedSource.metadata,
          extractionAssetMetadataKey: resultAsset.toJson(),
          'extractionProvider': extractor.id,
          'extractedPageCount': document.pages.length,
          'extractedTextLength': document.plainText.length,
          emptyTextMetadataKey: emptyText,
          'courseDraftStatus': emptyText
              ? 'skipped'
              : compilation != null
                  ? 'ready'
                  : 'needsReview',
          if (courseDraftAsset != null)
            courseDraftAssetMetadataKey: courseDraftAsset.toJson(),
          if (compilation != null) ...compilation.toMetadata(),
          if (compilationError != null) 'courseDraftError': compilationError,
          if (emptyTextMetadataKey == 'ocrEmpty')
            'requiresReview': emptyText || courseNeedsReview
          else if (courseNeedsReview)
            'requiresReview': true,
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
