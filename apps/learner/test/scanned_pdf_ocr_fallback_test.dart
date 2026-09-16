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
  test('empty PDF text-layer pages are rasterized and OCRed locally', () async {
    final database = VerbaSeedDatabase(NativeDatabase.memory());
    final repository = ImportRepository(database);
    final assets = MemoryContentAssetStore();
    addTearDown(() async {
      await assets.close();
      await database.close();
    });

    final sourceAsset = await assets.put(
      bytes: Uint8List.fromList([0x25, 0x50, 0x44, 0x46]),
      fileName: 'mixed.pdf',
      mimeType: 'application/pdf',
    );
    final jobId = await repository.enqueue(
      ContentSource(
        type: ContentSourceType.pdf,
        displayName: sourceAsset.fileName,
        metadata: {'asset': sourceAsset.toJson()},
      ),
    );
    final job = await (database.select(database.importJobs)
          ..where((table) => table.id.equals(jobId)))
        .getSingle();

    final coordinator = DocumentImportCoordinator(
      repository: repository,
      assetStore: assets,
      pdfExtractor: const _MixedPdfExtractor(),
      imageExtractor: const _PageOcrExtractor(),
      pdfPageRasterizer: const _TwoPageRasterizer(),
      imageExtractionAvailable: true,
      clock: () => DateTime.utc(2026, 9, 16, 14),
    );

    final state = await coordinator.processPdf(job);
    expect(state.phase, DocumentProcessingPhase.succeeded);
    expect(coordinator.pdfOcrFallbackAvailable, isTrue);

    final persisted = await (database.select(database.importJobs)
          ..where((table) => table.id.equals(jobId)))
        .getSingle();
    final source = repository.decodeSource(persisted);
    expect(source.metadata['textLayerEmptyPages'], [2]);
    expect(source.metadata['requiresOcr'], isFalse);
    expect(source.metadata['pdfOcrFallbackUsed'], isTrue);
    expect(source.metadata['pdfOcrFallbackPages'], [2]);
    expect(source.metadata['ocrEmptyPageCount'], 0);
    expect(source.metadata['requiresReview'], isFalse);
    expect(source.metadata['compiledItemCount'], 2);

    final extractionAsset = ContentAsset.fromJson(
      Map<String, Object?>.from(
        source.metadata[DocumentImportCoordinator.extractionAssetMetadataKey]!
            as Map,
      ),
    );
    final extractionBytes = await assets.read(extractionAsset.id);
    final extraction = ExtractedDocument.fromJson(
      Map<String, Object?>.from(
        jsonDecode(utf8.decode(extractionBytes!)) as Map,
      ),
    );
    expect(extraction.pages.map((page) => page.pageNumber), [1, 2]);
    expect(extraction.pages[0].text, 'Hello');
    expect(extraction.pages[1].text, '再见\nGoodbye');
    expect(extraction.metadata['ocrFallback'], isTrue);

    final courseAsset = ContentAsset.fromJson(
      Map<String, Object?>.from(
        source.metadata[DocumentImportCoordinator.courseDraftAssetMetadataKey]!
            as Map,
      ),
    );
    final courseBytes = await assets.read(courseAsset.id);
    final course = Course.fromJson(
      Map<String, Object?>.from(jsonDecode(utf8.decode(courseBytes!)) as Map),
    );
    final items = course.units.single.lessons
        .expand((lesson) => lesson.items)
        .toList(growable: false);
    expect(items.map((item) => item.text), ['Hello', 'Goodbye']);
    expect(items.last.translation, '再见');
  });

  test('PDF remains explicitly marked for OCR when local fallback is unavailable',
      () async {
    final database = VerbaSeedDatabase(NativeDatabase.memory());
    final repository = ImportRepository(database);
    final assets = MemoryContentAssetStore();
    addTearDown(() async {
      await assets.close();
      await database.close();
    });

    final sourceAsset = await assets.put(
      bytes: Uint8List.fromList([0x25, 0x50, 0x44, 0x46]),
      fileName: 'scan.pdf',
      mimeType: 'application/pdf',
    );
    final jobId = await repository.enqueue(
      ContentSource(
        type: ContentSourceType.pdf,
        displayName: sourceAsset.fileName,
        metadata: {'asset': sourceAsset.toJson()},
      ),
    );
    final job = await (database.select(database.importJobs)
          ..where((table) => table.id.equals(jobId)))
        .getSingle();

    final coordinator = DocumentImportCoordinator(
      repository: repository,
      assetStore: assets,
      pdfExtractor: const _EmptyPdfExtractor(),
      imageExtractionAvailable: false,
      clock: () => DateTime.utc(2026, 9, 16, 14),
    );

    final state = await coordinator.processPdf(job);
    expect(state.phase, DocumentProcessingPhase.succeeded);
    expect(coordinator.pdfOcrFallbackAvailable, isFalse);

    final persisted = await (database.select(database.importJobs)
          ..where((table) => table.id.equals(jobId)))
        .getSingle();
    final source = repository.decodeSource(persisted);
    expect(source.metadata['requiresOcr'], isTrue);
    expect(source.metadata['pdfOcrFallbackUsed'], isFalse);
    expect(source.metadata['requiresReview'], isTrue);
    expect(source.metadata['courseDraftStatus'], 'skipped');
  });
}

final class _MixedPdfExtractor implements DocumentExtractor {
  const _MixedPdfExtractor();

  @override
  String get id => 'test-pdf-text';

  @override
  bool supportsMimeType(String mimeType) => mimeType == 'application/pdf';

  @override
  Future<ExtractedDocument> extract(DocumentExtractionRequest request) async {
    return ExtractedDocument(
      assetId: request.assetId,
      mimeType: 'application/pdf',
      providerId: id,
      extractedAt: DateTime.utc(2026, 9, 16, 14),
      pages: [
        ExtractedPage(pageNumber: 1, text: 'Hello'),
        ExtractedPage(pageNumber: 2, text: ''),
      ],
    );
  }
}

final class _EmptyPdfExtractor implements DocumentExtractor {
  const _EmptyPdfExtractor();

  @override
  String get id => 'test-empty-pdf';

  @override
  bool supportsMimeType(String mimeType) => mimeType == 'application/pdf';

  @override
  Future<ExtractedDocument> extract(DocumentExtractionRequest request) async {
    return ExtractedDocument(
      assetId: request.assetId,
      mimeType: 'application/pdf',
      providerId: id,
      extractedAt: DateTime.utc(2026, 9, 16, 14),
      pages: [ExtractedPage(pageNumber: 1, text: '')],
    );
  }
}

final class _TwoPageRasterizer implements PdfPageRasterizer {
  const _TwoPageRasterizer();

  @override
  String get id => 'test-raster';

  @override
  Stream<RasterizedPdfPage> rasterize(PdfRasterizationRequest request) async* {
    for (var pageNumber = 1; pageNumber <= 2; pageNumber++) {
      yield RasterizedPdfPage(
        sourceAssetId: request.assetId,
        pageNumber: pageNumber,
        mimeType: 'image/png',
        bytes: Uint8List.fromList([pageNumber, 2, 3]),
        width: 100,
        height: 120,
      );
    }
  }
}

final class _PageOcrExtractor implements DocumentExtractor {
  const _PageOcrExtractor();

  @override
  String get id => 'test-local-ocr';

  @override
  bool supportsMimeType(String mimeType) => mimeType == 'image/png';

  @override
  Future<ExtractedDocument> extract(DocumentExtractionRequest request) async {
    expect(request.assetId, contains('-page-2'));
    return ExtractedDocument(
      assetId: request.assetId,
      mimeType: request.mimeType,
      providerId: id,
      extractedAt: DateTime.utc(2026, 9, 16, 14),
      pages: [
        ExtractedPage(
          pageNumber: 1,
          text: '再见\nGoodbye',
          blocks: [
            DocumentTextBlock(text: '再见'),
            DocumentTextBlock(text: 'Goodbye'),
          ],
        ),
      ],
    );
  }
}
