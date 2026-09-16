import 'package:content_source/content_source.dart';
import 'package:content_store/content_store.dart';
import 'package:document_processing/document_processing.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_store/local_store.dart';
import 'package:verbaseed_learner/src/data/providers.dart';
import 'package:verbaseed_learner/src/features/import/ocr_import_page.dart';

void main() {
  testWidgets('image queue exposes explicit OCR platform availability', (tester) async {
    final database = VerbaSeedDatabase(NativeDatabase.memory());
    final assetStore = MemoryContentAssetStore();
    addTearDown(database.close);
    addTearDown(assetStore.close);

    final repository = ImportRepository(database);
    final processingState = DocumentRetryStateMachine().initial(
      at: DateTime.utc(2026, 9, 16),
    );
    final jobId = await repository.enqueue(
      ContentSource(
        type: ContentSourceType.image,
        displayName: 'lesson-page.png',
        metadata: withDocumentProcessingState(
          const <String, Object?>{
            'pipeline': 'document-extraction-v1',
          },
          processingState,
        ),
      ),
    );
    final job = await (database.select(database.importJobs)
          ..where((table) => table.id.equals(jobId)))
        .getSingle();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          importRepositoryProvider.overrideWith((ref) => repository),
          importJobsProvider.overrideWith((ref) => Stream.value([job])),
          contentAssetStoreProvider.overrideWith((ref) => assetStore),
        ],
        child: const MaterialApp(
          home: Scaffold(body: OcrImportPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('创建与导入'), findsOneWidget);
    final capability = find.text('当前平台不提供本地图片 OCR');
    expect(capability, findsOneWidget);

    await tester.tap(capability);
    await tester.pumpAndSettle();

    expect(find.text('lesson-page.png'), findsWidgets);
    expect(find.text('等待 OCR'), findsOneWidget);
  });
}
