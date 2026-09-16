import 'dart:convert';
import 'dart:typed_data';

import 'package:content_source/content_source.dart';
import 'package:content_store/content_store.dart';
import 'package:document_processing/document_processing.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_store/local_store.dart';
import 'package:verbaseed_learner/src/data/document_import_coordinator.dart';

void main() {
  late VerbaSeedDatabase database;
  late ImportRepository repository;
  late MemoryContentAssetStore assetStore;

  setUp(() {
    database = VerbaSeedDatabase(NativeDatabase.memory());
    repository = ImportRepository(database);
    assetStore = MemoryContentAssetStore();
  });

  tearDown(() async {
    await assetStore.close();
    await database.close();
  });

  test('PDF extraction is committed only after result asset is durable', () async {
    final now = DateTime.utc(2026, 9, 16, 6);
    final rawAsset = await assetStore.put(
      bytes: Uint8List.fromList([37, 80, 68, 70]),
      fileName: 'lesson.pdf',
      mimeType: 'application/pdf',
    );
    final source = ContentSource(
      type: ContentSourceType.pdf,
      displayName: rawAsset.fileName,
      metadata: {'asset': rawAsset.toJson()},
    );
    final jobId = await repository.enqueue(source);
    final job = await (database.select(database.importJobs)
          ..where((table) => table.id.equals(jobId)))
        .getSingle();
    final extractor = _FakePdfExtractor(now: now);
    final coordinator = DocumentImportCoordinator(
      repository: repository,
      assetStore: assetStore,
      pdfExtractor: extractor,
      clock: () => now,
    );

    final state = await coordinator.processPdf(
      job,
      pageRange: PageRange(startPage: 2, endPage: 3),
      replacePageRange: true,
    );

    expect(state.phase, DocumentProcessingPhase.succeeded);
    expect(extractor.lastRequest?.pageRange?.startPage, 2);
    expect(extractor.lastRequest?.pageRange?.endPage, 3);

    final persisted = await (database.select(database.importJobs)
          ..where((table) => table.id.equals(jobId)))
        .getSingle();
    expect(persisted.status, ImportJobState.ready.name);
    final persistedSource = repository.decodeSource(persisted);
    final persistedState = documentProcessingStateFromMetadata(
      persistedSource.metadata,
    );
    expect(persistedState?.phase, DocumentProcessingPhase.succeeded);
    expect(persistedSource.metadata['requiresOcr'], isFalse);

    final extractionRaw = persistedSource.metadata[
      DocumentImportCoordinator.extractionAssetMetadataKey
    ];
    expect(extractionRaw, isA<Map>());
    final extractionAsset = ContentAsset.fromJson(
      Map<String, Object?>.from(extractionRaw! as Map),
    );
    final resultBytes = await assetStore.read(extractionAsset.id);
    expect(resultBytes, isNotNull);
    final decoded = ExtractedDocument.fromJson(
      Map<String, Object?>.from(
        jsonDecode(utf8.decode(resultBytes!)) as Map,
      ),
    );
    expect(decoded.pages.map((page) => page.pageNumber), [2, 3]);
    expect(decoded.plainText, contains('page 2'));
  });

  test('image OCR uses the same durable extraction transaction', () async {
    final now = DateTime.utc(2026, 9, 16, 7);
    final rawAsset = await assetStore.put(
      bytes: Uint8List.fromList([1, 2, 3, 4]),
      fileName: 'page.png',
      mimeType: 'image/png',
    );
    final jobId = await repository.enqueue(
      ContentSource(
        type: ContentSourceType.image,
        displayName: rawAsset.fileName,
        metadata: {'asset': rawAsset.toJson()},
      ),
    );
    final job = await (database.select(database.importJobs)
          ..where((table) => table.id.equals(jobId)))
        .getSingle();
    final imageExtractor = _FakeImageExtractor(now: now);
    final coordinator = DocumentImportCoordinator(
      repository: repository,
      assetStore: assetStore,
      pdfExtractor: _FakePdfExtractor(now: now),
      imageExtractor: imageExtractor,
      imageExtractionAvailable: true,
      clock: () => now,
    );

    final state = await coordinator.processImage(job);

    expect(state.phase, DocumentProcessingPhase.succeeded);
    expect(imageExtractor.calls, 1);
    final persisted = await (database.select(database.importJobs)
          ..where((table) => table.id.equals(jobId)))
        .getSingle();
    expect(persisted.status, ImportJobState.ready.name);
    final persistedSource = repository.decodeSource(persisted);
    expect(persistedSource.metadata['ocrEmpty'], isFalse);
    expect(persistedSource.metadata['requiresReview'], isFalse);
    expect(persistedSource.metadata['extractionProvider'], 'fake-image-ocr');

    final extractionAsset = ContentAsset.fromJson(
      Map<String, Object?>.from(
        persistedSource.metadata[
              DocumentImportCoordinator.extractionAssetMetadataKey
            ]!
            as Map,
      ),
    );
    final resultBytes = await assetStore.read(extractionAsset.id);
    expect(resultBytes, isNotNull);
    final decoded = ExtractedDocument.fromJson(
      Map<String, Object?>.from(
        jsonDecode(utf8.decode(resultBytes!)) as Map,
      ),
    );
    expect(decoded.plainText, 'Hello from OCR');
  });

  test('retryable extraction failures persist bounded retry state', () async {
    final now = DateTime.utc(2026, 9, 16, 6);
    final rawAsset = await assetStore.put(
      bytes: Uint8List.fromList([37, 80, 68, 70]),
      fileName: 'retry.pdf',
      mimeType: 'application/pdf',
    );
    final jobId = await repository.enqueue(
      ContentSource(
        type: ContentSourceType.pdf,
        displayName: rawAsset.fileName,
        metadata: {'asset': rawAsset.toJson()},
      ),
    );
    final job = await (database.select(database.importJobs)
          ..where((table) => table.id.equals(jobId)))
        .getSingle();
    final coordinator = DocumentImportCoordinator(
      repository: repository,
      assetStore: assetStore,
      pdfExtractor: const _RetryablePdfExtractor(),
      clock: () => now,
    );

    final state = await coordinator.processPdf(job);

    expect(state.phase, DocumentProcessingPhase.retryScheduled);
    expect(state.attempt, 1);
    expect(state.lastErrorCode, 'temporarily_unavailable');
    final persisted = await (database.select(database.importJobs)
          ..where((table) => table.id.equals(jobId)))
        .getSingle();
    expect(persisted.status, ImportJobState.queued.name);
    expect(persisted.errorMessage, isNull);
  });
}

final class _FakePdfExtractor implements DocumentExtractor {
  _FakePdfExtractor({required this.now});

  final DateTime now;
  DocumentExtractionRequest? lastRequest;

  @override
  String get id => 'fake-pdf';

  @override
  bool supportsMimeType(String mimeType) => mimeType == 'application/pdf';

  @override
  Future<ExtractedDocument> extract(DocumentExtractionRequest request) async {
    lastRequest = request;
    final range = request.pageRange ?? PageRange(startPage: 1);
    return ExtractedDocument(
      assetId: request.assetId,
      mimeType: request.mimeType,
      providerId: id,
      extractedAt: now,
      pages: [
        for (var page = range.startPage; page <= range.endPage; page++)
          ExtractedPage(pageNumber: page, text: 'page $page'),
      ],
    );
  }
}

final class _FakeImageExtractor implements DocumentExtractor {
  _FakeImageExtractor({required this.now});

  final DateTime now;
  int calls = 0;

  @override
  String get id => 'fake-image-ocr';

  @override
  bool supportsMimeType(String mimeType) => mimeType.startsWith('image/');

  @override
  Future<ExtractedDocument> extract(DocumentExtractionRequest request) async {
    calls += 1;
    return ExtractedDocument(
      assetId: request.assetId,
      mimeType: request.mimeType,
      providerId: id,
      extractedAt: now,
      pages: [
        ExtractedPage(
          pageNumber: 1,
          text: 'Hello from OCR',
          blocks: [DocumentTextBlock(text: 'Hello from OCR')],
        ),
      ],
    );
  }
}

final class _RetryablePdfExtractor implements DocumentExtractor {
  const _RetryablePdfExtractor();

  @override
  String get id => 'retryable-pdf';

  @override
  bool supportsMimeType(String mimeType) => mimeType == 'application/pdf';

  @override
  Future<ExtractedDocument> extract(DocumentExtractionRequest request) async {
    throw const DocumentExtractionException(
      code: 'temporarily_unavailable',
      message: 'runtime busy',
      retryable: true,
    );
  }
}
