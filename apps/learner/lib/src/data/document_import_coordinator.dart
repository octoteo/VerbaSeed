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
    DocumentRetryStateMachine? stateMachine,
    DateTime Function()? clock,
  }) =>
      DocumentImportCoordinator._(
        repository,
        assetStore,
        pdfExtractor,
        stateMachine: stateMachine,
        clock: clock,
      );

  DocumentImportCoordinator._(
    this._repository,
    this._assetStore,
    this._pdfExtractor, {
    DocumentRetryStateMachine? stateMachine,
    DateTime Function()? clock,
  })  : _stateMachine = stateMachine ?? DocumentRetryStateMachine(),
        _clock = clock ?? DateTime.now;

  static const extractionAssetMetadataKey = 'extractionAsset';

  final ImportRepository _repository;
  final ContentAssetStore _assetStore;
  final DocumentExtractor _pdfExtractor;
  final DocumentRetryStateMachine _stateMachine;
  final DateTime Function() _clock;
  final Set<String> _inFlight = <String>{};

  Future<DocumentProcessingState> processPdf(
    ImportJob job, {
    PageRange? pageRange,
    bool replacePageRange = false,
  }) async {
    if (!_inFlight.add(job.id)) {
      throw StateError('文档解析任务正在执行: ${job.id}');
    }
    try {
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

      var state = documentProcessingStateFromMetadata(source.metadata) ??
          _stateMachine.initial(at: _now());
      final recovered = _stateMachine.recoverInterrupted(state, at: _now());
      if (!_sameState(recovered, state)) {
        state = recovered;
        source = source.copyWith(
          metadata: withDocumentProcessingState(source.metadata, state),
        );
        await _persistState(job.id, source, state);
      }

      final startAt = _now();
      if (!_stateMachine.canStart(state, at: startAt)) {
        return state;
      }

      state = _stateMachine.begin(
        state,
        at: startAt,
        providerId: _pdfExtractor.id,
      );
      source = source.copyWith(
        metadata: withDocumentProcessingState(source.metadata, state),
      );
      await _persistState(job.id, source, state);

      try {
        final asset = _decodeSourceAsset(source.metadata);
        final bytes = await _assetStore.read(asset.id);
        if (bytes == null) {
          throw const DocumentExtractionException(
            code: 'content_asset_missing',
            message: '原始 PDF 文件已不存在，无法继续解析',
            retryable: false,
          );
        }

        final document = await _pdfExtractor.extract(
          DocumentExtractionRequest(
            assetId: asset.id,
            mimeType: asset.mimeType,
            bytes: bytes,
            sourceName: asset.fileName,
            pageRange: _pageRangeFromMetadata(source.metadata),
          ),
        );

        final resultBytes = Uint8List.fromList(
          utf8.encode(jsonEncode(document.toJson())),
        );
        final resultAsset = await _assetStore.put(
          bytes: resultBytes,
          fileName: '${asset.fileName}.extracted.json',
          mimeType: 'application/vnd.verbaseed.document-extraction+json',
        );

        final completed = _stateMachine.succeed(state, at: _now());
        final resolvedMetadata = <String, Object?>{
          ...source.metadata,
          extractionAssetMetadataKey: resultAsset.toJson(),
          'extractedPageCount': document.pages.length,
          'extractedTextLength': document.plainText.length,
          'requiresOcr': document.plainText.trim().isEmpty,
        };
        source = source.copyWith(
          metadata: withDocumentProcessingState(
            resolvedMetadata,
            completed,
          ),
        );
        await _repository.replaceSource(
          job.id,
          source,
          state: ImportJobState.ready,
        );
        return completed;
      } on DocumentExtractionException catch (error) {
        return await _persistFailure(
          jobId: job.id,
          source: source,
          running: state,
          code: error.code,
          message: error.message,
          retryable: error.retryable,
        );
      } on FormatException catch (error) {
        return await _persistFailure(
          jobId: job.id,
          source: source,
          running: state,
          code: 'invalid_import_metadata',
          message: error.message,
          retryable: false,
        );
      } on StateError catch (error) {
        return await _persistFailure(
          jobId: job.id,
          source: source,
          running: state,
          code: 'content_asset_invalid',
          message: '$error',
          retryable: false,
        );
      } on Object catch (error) {
        return await _persistFailure(
          jobId: job.id,
          source: source,
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

  bool _sameState(
    DocumentProcessingState left,
    DocumentProcessingState right,
  ) =>
      jsonEncode(left.toJson()) == jsonEncode(right.toJson());

  DateTime _now() => _clock().toUtc();
}
