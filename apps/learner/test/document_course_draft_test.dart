import 'dart:convert';
import 'dart:typed_data';

import 'package:content_source/content_source.dart';
import 'package:content_store/content_store.dart';
import 'package:course_schema/course_schema.dart';
import 'package:document_processing/document_processing.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_store/local_store.dart';
import 'package:verbaseed_learner/src/data/document_import_coordinator.dart';

void main() {
  test('successful OCR persists a deterministic learnable course draft', () async {
    final database = VerbaSeedDatabase(NativeDatabase.memory());
    final repository = ImportRepository(database);
    final assetStore = MemoryContentAssetStore();
    addTearDown(() async {
      await assetStore.close();
      await database.close();
    });

    final rawAsset = await assetStore.put(
      bytes: Uint8List.fromList([1, 2, 3, 4]),
      fileName: 'lesson.png',
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

    final coordinator = DocumentImportCoordinator(
      repository: repository,
      assetStore: assetStore,
      pdfExtractor: const _NeverPdfExtractor(),
      imageExtractor: const _BilingualImageExtractor(),
      imageExtractionAvailable: true,
      clock: () => DateTime.utc(2026, 9, 16, 10),
    );

    final state = await coordinator.processImage(job);
    expect(state.phase, DocumentProcessingPhase.succeeded);

    final persisted = await (database.select(database.importJobs)
          ..where((table) => table.id.equals(jobId)))
        .getSingle();
    final source = repository.decodeSource(persisted);
    expect(source.metadata['courseDraftStatus'], 'ready');
    expect(source.metadata['compiledItemCount'], 3);
    expect(source.metadata['compiledLessonCount'], 1);
    expect(source.metadata['requiresReview'], isFalse);

    final rawCourseAsset =
        source.metadata[DocumentImportCoordinator.courseDraftAssetMetadataKey];
    expect(rawCourseAsset, isA<Map>());
    final courseAsset = ContentAsset.fromJson(
      Map<String, Object?>.from(rawCourseAsset! as Map),
    );
    final courseBytes = await assetStore.read(courseAsset.id);
    expect(courseBytes, isNotNull);

    final course = Course.fromJson(
      Map<String, Object?>.from(
        jsonDecode(utf8.decode(courseBytes!)) as Map,
      ),
    );
    expect(course.title, 'lesson');
    final items = course.units.single.lessons.single.items;
    expect(items.map((item) => item.text), [
      'Hello',
      'Goodbye',
      'Open your book.',
    ]);
    expect(items[0].translation, '你好');
    expect(items[1].translation, '再见');
  });
}

final class _BilingualImageExtractor implements DocumentExtractor {
  const _BilingualImageExtractor();

  @override
  String get id => 'test-bilingual-ocr';

  @override
  bool supportsMimeType(String mimeType) => mimeType.startsWith('image/');

  @override
  Future<ExtractedDocument> extract(DocumentExtractionRequest request) async {
    return ExtractedDocument(
      assetId: request.assetId,
      mimeType: request.mimeType,
      providerId: id,
      extractedAt: DateTime.utc(2026, 9, 16, 10),
      pages: [
        ExtractedPage(
          pageNumber: 1,
          text: '你好\nHello\n再见 — Goodbye\nOpen your book.',
        ),
      ],
    );
  }
}

final class _NeverPdfExtractor implements DocumentExtractor {
  const _NeverPdfExtractor();

  @override
  String get id => 'never-pdf';

  @override
  bool supportsMimeType(String mimeType) => mimeType == 'application/pdf';

  @override
  Future<ExtractedDocument> extract(DocumentExtractionRequest request) {
    throw StateError('PDF extractor should not be called in this test');
  }
}
