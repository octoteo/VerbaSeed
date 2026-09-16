import 'document_extractor.dart';
import 'models.dart';
import 'processing_state.dart';

typedef DocumentProcessingClock = DateTime Function();

final class DocumentProcessingOutcome {
  const DocumentProcessingOutcome({
    required this.state,
    required this.didRun,
    this.document,
  });

  final DocumentProcessingState state;
  final bool didRun;
  final ExtractedDocument? document;

  bool get shouldRetry =>
      state.phase == DocumentProcessingPhase.retryScheduled;
}

final class DocumentProcessor {
  DocumentProcessor({
    required this.extractor,
    DocumentRetryStateMachine? stateMachine,
    DocumentProcessingClock? clock,
  })  : stateMachine = stateMachine ?? DocumentRetryStateMachine(),
        _clock = clock ?? DateTime.now;

  final DocumentExtractor extractor;
  final DocumentRetryStateMachine stateMachine;
  final DocumentProcessingClock _clock;

  Future<DocumentProcessingOutcome> process({
    required DocumentExtractionRequest request,
    required DocumentProcessingState state,
  }) async {
    var current = stateMachine.recoverInterrupted(state, at: _now());
    final startAt = _now();
    if (!stateMachine.canStart(current, at: startAt)) {
      return DocumentProcessingOutcome(state: current, didRun: false);
    }

    final running = stateMachine.begin(
      current,
      at: startAt,
      providerId: extractor.id,
    );

    if (!extractor.supportsMimeType(request.mimeType)) {
      return DocumentProcessingOutcome(
        state: stateMachine.fail(
          running,
          at: _now(),
          retryable: false,
          code: 'unsupported_mime_type',
          message: '解析器 ${extractor.id} 不支持 ${request.mimeType}',
        ),
        didRun: true,
      );
    }

    try {
      final document = await extractor.extract(request);
      if (document.assetId != request.assetId) {
        throw const DocumentExtractionException(
          code: 'asset_identity_mismatch',
          message: '解析器返回的资产标识与请求不一致',
          retryable: false,
        );
      }
      return DocumentProcessingOutcome(
        state: stateMachine.succeed(running, at: _now()),
        didRun: true,
        document: document,
      );
    } on DocumentExtractionException catch (error) {
      return DocumentProcessingOutcome(
        state: stateMachine.fail(
          running,
          at: _now(),
          retryable: error.retryable,
          code: error.code,
          message: error.message,
        ),
        didRun: true,
      );
    } on Object catch (error) {
      return DocumentProcessingOutcome(
        state: stateMachine.fail(
          running,
          at: _now(),
          retryable: false,
          code: 'unexpected_provider_error',
          message: '$error',
        ),
        didRun: true,
      );
    }
  }

  DateTime _now() => _clock().toUtc();
}
