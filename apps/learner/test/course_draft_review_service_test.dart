import 'dart:convert';
import 'dart:typed_data';

import 'package:content_source/content_source.dart';
import 'package:content_store/content_store.dart';
import 'package:course_schema/course_schema.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_store/local_store.dart';
import 'package:verbaseed_learner/src/data/course_draft_review_service.dart';
import 'package:verbaseed_learner/src/data/document_import_coordinator.dart';

void main() {
  test('review saves a new immutable draft asset and can accept it', () async {
    final database = VerbaSeedDatabase(NativeDatabase.memory());
    final repository = ImportRepository(database);
    final assetStore = MemoryContentAssetStore();
    addTearDown(() async {
      await assetStore.close();
      await database.close();
    });

    const originalCourse = Course(
      id: 'import-demo',
      title: 'Original title',
      sourceLanguage: 'zh-CN',
      targetLanguage: 'en',
      units: [
        CourseUnit(
          id: 'unit-1',
          title: 'Imported document',
          lessons: [
            Lesson(
              id: 'lesson-1',
              title: 'Page 1',
              items: [
                LearningItem(
                  id: 'item-1',
                  text: 'Helo',
                  translation: '你好',
                ),
              ],
              activities: [LearningActivityType.spelling],
            ),
          ],
        ),
      ],
    );
    final originalAsset = await assetStore.put(
      bytes: Uint8List.fromList(
        utf8.encode(jsonEncode(originalCourse.toJson())),
      ),
      fileName: 'lesson.course-draft.json',
      mimeType: 'application/vnd.verbaseed.course+json',
    );
    final jobId = await repository.enqueue(
      ContentSource(
        type: ContentSourceType.image,
        displayName: 'lesson.png',
        metadata: {
          DocumentImportCoordinator.courseDraftAssetMetadataKey:
              originalAsset.toJson(),
          'courseDraftStatus': 'ready',
          'courseDraftNeedsReview': true,
          'requiresReview': true,
          'courseDraftWarnings': ['OCR 置信度较低'],
        },
      ),
    );

    final service = CourseDraftReviewService(
      database: database,
      repository: repository,
      assetStore: assetStore,
      clock: () => DateTime.utc(2026, 9, 16, 12),
    );

    final loaded = await service.load(jobId);
    expect(loaded.course.title, 'Original title');
    expect(loaded.requiresReview, isTrue);
    expect(loaded.warnings, ['OCR 置信度较低']);

    const corrected = Course(
      id: 'import-demo',
      title: 'Unit 1 Classroom English',
      sourceLanguage: 'zh-CN',
      targetLanguage: 'en',
      units: [
        CourseUnit(
          id: 'unit-1',
          title: 'Imported document',
          lessons: [
            Lesson(
              id: 'lesson-1',
              title: 'Page 1',
              items: [
                LearningItem(
                  id: 'item-1',
                  text: 'Hello',
                  translation: '你好',
                ),
              ],
              activities: [LearningActivityType.spelling],
            ),
          ],
        ),
      ],
    );

    final accepted = await service.save(
      jobId: jobId,
      course: corrected,
      accept: true,
    );
    expect(accepted.status, 'accepted');
    expect(accepted.requiresReview, isFalse);
    expect(accepted.course.title, 'Unit 1 Classroom English');
    expect(
      accepted.course.units.single.lessons.single.items.single.text,
      'Hello',
    );
    expect(accepted.asset.id, isNot(originalAsset.id));
    expect(accepted.source.metadata['courseDraftRevision'], 1);
    expect(accepted.source.metadata['compiledItemCount'], 1);
    expect(
      accepted.source.metadata['courseDraftReviewedAt'],
      '2026-09-16T12:00:00.000Z',
    );
  });

  test('review refuses an empty learnable course', () async {
    final database = VerbaSeedDatabase(NativeDatabase.memory());
    final repository = ImportRepository(database);
    final assetStore = MemoryContentAssetStore();
    addTearDown(() async {
      await assetStore.close();
      await database.close();
    });

    const originalCourse = Course(
      id: 'import-demo',
      title: 'Original title',
      sourceLanguage: 'zh-CN',
      targetLanguage: 'en',
      units: [
        CourseUnit(
          id: 'unit-1',
          title: 'Imported document',
          lessons: [
            Lesson(
              id: 'lesson-1',
              title: 'Page 1',
              items: [
                LearningItem(id: 'item-1', text: 'Hello', translation: ''),
              ],
            ),
          ],
        ),
      ],
    );
    final asset = await assetStore.put(
      bytes: Uint8List.fromList(utf8.encode(jsonEncode(originalCourse.toJson()))),
      fileName: 'draft.json',
      mimeType: 'application/vnd.verbaseed.course+json',
    );
    final jobId = await repository.enqueue(
      ContentSource(
        type: ContentSourceType.image,
        displayName: 'lesson.png',
        metadata: {
          DocumentImportCoordinator.courseDraftAssetMetadataKey: asset.toJson(),
          'courseDraftStatus': 'ready',
        },
      ),
    );
    final service = CourseDraftReviewService(
      database: database,
      repository: repository,
      assetStore: assetStore,
    );

    const emptyCourse = Course(
      id: 'import-demo',
      title: 'Empty',
      sourceLanguage: 'zh-CN',
      targetLanguage: 'en',
      units: [
        CourseUnit(id: 'unit-1', title: 'Unit', lessons: []),
      ],
    );

    expect(
      () => service.save(jobId: jobId, course: emptyCourse),
      throwsFormatException,
    );
  });
}
