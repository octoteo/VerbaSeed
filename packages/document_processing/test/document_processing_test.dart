import 'dart:typed_data';

import 'package:document_processing/document_processing.dart';
import 'package:test/test.dart';

void main() {
  group('document models', () {
    test('page ranges and extracted layout round-trip', () {
      final range = PageRange(startPage: 2, endPage: 4);
      expect(range.length, 3);
      expect(range.contains(3), isTrue);
      expect(range.contains(5), isFalse);

      final document = ExtractedDocument(
        assetId: 'sha256:abc',
        mimeType: 'image/png',
        providerId: 'fake-ocr',
        extractedAt: DateTime.utc(2026, 9, 16, 4),
        pages: [
          ExtractedPage(
            pageNumber: 1,
            text: 'Hello world',
            blocks: [
              DocumentTextBlock(
                text: 'Hello world',
                confidence: 0.98,
                bounds: DocumentRect(
                  left: 0.1,
                  top: 0.2,
                  width: 0.5,
                  height: 0.1,
                ),
              ),
            ],
          ),
        ],
      );

      final restored = ExtractedDocument.fromJson(document.toJson());
      expect(restored.assetId, document.assetId);
      expect(restored.plainText, 'Hello world');
      expect(restored.pages.single.blocks.single.confidence, 0.98);
    });
  });

  group('deterministic retry state machine', () {
    test('transient failures use bounded deterministic backoff', () {
      final machine = DocumentRetryStateMachine(
        policy: const DocumentRetryPolicy(
          maxAttempts: 3,
          baseDelay: Duration(seconds: 5),
          maxDelay: Duration(seconds: 20),
        ),
      );
      final start = DateTime.utc(2026, 9, 16, 4);
      var state = machine.initial(at: start);

      state = machine.begin(state, at: start, providerId: 'fake');
      state = machine.fail(
        state,
        at: start.add(const Duration(seconds: 1)),
        retryable: true,
        code: 'busy',
        message: 'provider busy',
      );
      expect(state.phase, DocumentProcessingPhase.retryScheduled);
      expect(state.attempt, 1);
      expect(
        state.nextAttemptAt,
        start.add(const Duration(seconds: 6)),
      );
      expect(
        machine.canStart(
          state,
          at: start.add(const Duration(seconds: 5)),
        ),
        isFalse,
      );

      state = machine.begin(
        state,
        at: state.nextAttemptAt!,
        providerId: 'fake',
      );
      final secondFailureAt = state.startedAt!;
      state = machine.fail(
        state,
        at: secondFailureAt,
        retryable: true,
        code: 'busy',
        message: 'provider busy',
      );
      expect(
        state.nextAttemptAt,
        secondFailureAt.add(const Duration(seconds: 10)),
      );

      state = machine.begin(
        state,
        at: state.nextAttemptAt!,
        providerId: 'fake',
      );
      state = machine.fail(
        state,
        at: state.startedAt!,
        retryable: true,
        code: 'busy',
        message: 'provider busy',
      );
      expect(state.phase, DocumentProcessingPhase.failed);
      expect(state.attempt, 3);
      expect(state.nextAttemptAt, isNull);
      expect(state.isTerminal, isTrue);
    });

    test('stalled extraction is converted into a controlled retry', () {
      final machine = DocumentRetryStateMachine(
        policy: const DocumentRetryPolicy(
          processingTimeout: Duration(seconds: 30),
          baseDelay: Duration(seconds: 3),
        ),
      );
      final start = DateTime.utc(2026, 9, 16, 4);
      final running = machine.begin(
        machine.initial(at: start),
        at: start,
        providerId: 'fake',
      );

      final unchanged = machine.recoverInterrupted(
        running,
        at: start.add(const Duration(seconds: 29)),
      );
      expect(unchanged.phase, DocumentProcessingPhase.extracting);

      final recovered = machine.recoverInterrupted(
        running,
        at: start.add(const Duration(seconds: 30)),
      );
      expect(recovered.phase, DocumentProcessingPhase.retryScheduled);
      expect(recovered.lastErrorCode, 'processing_interrupted');
      expect(
        recovered.nextAttemptAt,
        start.add(const Duration(seconds: 33)),
      );
    });

    test('processing state metadata survives serialization', () {
      final machine = DocumentRetryStateMachine();
      final state = machine.initial(at: DateTime.utc(2026, 9, 16, 4));
      final metadata = withDocumentProcessingState(
        const {'asset': 'abc'},
        state,
      );
      final restored = documentProcessingStateFromMetadata(metadata)!;
      expect(restored.phase, DocumentProcessingPhase.queued);
      expect(restored.maxAttempts, 4);
      expect(metadata['asset'], 'abc');
    });
  });

  group('processor', () {
    test('successful provider completes the state and returns document', () async {
      final now = DateTime.utc(2026, 9, 16, 4);
      final extractor = _SuccessExtractor(now);
      final processor = DocumentProcessor(
        extractor: extractor,
        clock: () => now,
      );
      final state = processor.stateMachine.initial(at: now);
      final outcome = await processor.process(
        request: DocumentExtractionRequest(
          assetId: 'asset-1',
          mimeType: 'image/png',
          bytes: Uint8List.fromList([1, 2, 3]),
        ),
        state: state,
      );

      expect(outcome.didRun, isTrue);
      expect(outcome.state.phase, DocumentProcessingPhase.succeeded);
      expect(outcome.document?.plainText, 'hello');
      expect(extractor.calls, 1);
    });

    test('retryable provider failures become scheduled retries', () async {
      final now = DateTime.utc(2026, 9, 16, 4);
      final processor = DocumentProcessor(
        extractor: _RetryableExtractor(),
        stateMachine: DocumentRetryStateMachine(
          policy: const DocumentRetryPolicy(
            baseDelay: Duration(seconds: 7),
          ),
        ),
        clock: () => now,
      );
      final state = processor.stateMachine.initial(at: now);
      final outcome = await processor.process(
        request: DocumentExtractionRequest(
          assetId: 'asset-1',
          mimeType: 'application/pdf',
          bytes: Uint8List.fromList([37, 80, 68, 70]),
        ),
        state: state,
      );

      expect(outcome.state.phase, DocumentProcessingPhase.retryScheduled);
      expect(outcome.state.lastErrorCode, 'temporarily_unavailable');
      expect(
        outcome.state.nextAttemptAt,
        now.add(const Duration(seconds: 7)),
      );
    });
  });
}

final class _SuccessExtractor implements DocumentExtractor {
  _SuccessExtractor(this.now);

  final DateTime now;
  int calls = 0;

  @override
  String get id => 'success';

  @override
  bool supportsMimeType(String mimeType) => mimeType == 'image/png';

  @override
  Future<ExtractedDocument> extract(DocumentExtractionRequest request) async {
    calls += 1;
    return ExtractedDocument(
      assetId: request.assetId,
      mimeType: request.mimeType,
      providerId: id,
      extractedAt: now,
      pages: [ExtractedPage(pageNumber: 1, text: 'hello')],
    );
  }
}

final class _RetryableExtractor implements DocumentExtractor {
  @override
  String get id => 'retryable';

  @override
  bool supportsMimeType(String mimeType) => mimeType == 'application/pdf';

  @override
  Future<ExtractedDocument> extract(DocumentExtractionRequest request) async {
    throw const DocumentExtractionException(
      code: 'temporarily_unavailable',
      message: 'try again later',
      retryable: true,
    );
  }
}
