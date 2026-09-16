import 'dart:convert';
import 'dart:typed_data';

import 'package:content_source/content_source.dart';
import 'package:content_store/content_store.dart';
import 'package:course_schema/course_schema.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_store/local_store.dart';
import 'package:verbaseed_learner/src/data/course_draft_review_service.dart';
import 'package:verbaseed_learner/src/data/course_installation_service.dart';
import 'package:verbaseed_learner/src/data/document_import_coordinator.dart';

void main() {
  test('accepted draft installs, enrolls learner and seeds review cards', () async {
    final database = VerbaSeedDatabase(NativeDatabase.memory());
    final assets = MemoryContentAssetStore();
    addTearDown(() async {
      await assets.close();
      await database.close();
    });

    final imports = ImportRepository(database);
    final learners = LearnerRepository(database);
    final reviews = ReviewRepository(database);
    final installations = CourseInstallationRepository(
      database,
      clock: () => DateTime.utc(2026, 9, 16, 13),
    );

    final course = Course(
      id: 'import-course',
      title: 'Starter English',
      sourceLanguage: 'zh-CN',
      targetLanguage: 'en',
      units: [
        CourseUnit(
          id: 'unit-1',
          title: 'Unit 1',
          lessons: [
            Lesson(
              id: 'lesson-1',
              title: 'Lesson 1',
              items: const [
                LearningItem(id: 'item-1', text: 'Hello', translation: '你好'),
                LearningItem(id: 'item-2', text: 'Goodbye', translation: '再见'),
              ],
              activities: const [LearningActivityType.spelling],
            ),
          ],
        ),
      ],
    );
    final draftAsset = await assets.put(
      bytes: Uint8List.fromList(utf8.encode(jsonEncode(course.toJson()))),
      fileName: 'course.json',
      mimeType: 'application/vnd.verbaseed.course+json',
    );
    final jobId = await imports.enqueue(
      ContentSource(
        type: ContentSourceType.image,
        displayName: 'lesson.png',
        metadata: {
          DocumentImportCoordinator.courseDraftAssetMetadataKey: draftAsset.toJson(),
          'courseDraftStatus': 'accepted',
          'courseDraftNeedsReview': false,
        },
      ),
    );
    final learnerId = await learners.createProfile(displayName: 'Mia');

    final reviewService = CourseDraftReviewService(
      database: database,
      repository: imports,
      assetStore: assets,
    );
    final service = CourseInstallationService(
      reviewService: reviewService,
      installationRepository: installations,
      reviewRepository: reviews,
    );

    final result = await service.installAcceptedDraft(
      jobId: jobId,
      learnerId: learnerId,
    );
    expect(result.courseId, 'import-course');
    expect(result.version, 1);
    expect(result.itemCount, 2);
    expect(result.seededReviewCardCount, 2);
    expect(result.reusedVersion, isFalse);

    expect(await database.select(database.installedCourses).get(), hasLength(1));
    expect(
      await database.select(database.installedCourseVersions).get(),
      hasLength(1),
    );
    expect(
      await database.select(database.learnerCourseEnrollments).get(),
      hasLength(1),
    );
    final cards = await database.select(database.reviewCards).get();
    expect(cards.map((card) => card.itemId).toSet(), {'item-1', 'item-2'});

    final repeated = await service.installAcceptedDraft(
      jobId: jobId,
      learnerId: learnerId,
    );
    expect(repeated.version, 1);
    expect(repeated.reusedVersion, isTrue);
    expect(
      await database.select(database.installedCourseVersions).get(),
      hasLength(1),
    );
    expect(await database.select(database.reviewCards).get(), hasLength(2));
  });

  test('draft must be accepted before installation', () async {
    final database = VerbaSeedDatabase(NativeDatabase.memory());
    final assets = MemoryContentAssetStore();
    addTearDown(() async {
      await assets.close();
      await database.close();
    });

    final imports = ImportRepository(database);
    final learners = LearnerRepository(database);
    final course = Course(
      id: 'draft-course',
      title: 'Draft',
      sourceLanguage: 'zh-CN',
      targetLanguage: 'en',
      units: [
        CourseUnit(
          id: 'unit',
          title: 'Unit',
          lessons: [
            Lesson(
              id: 'lesson',
              title: 'Lesson',
              items: const [LearningItem(id: 'item', text: 'Hello')],
            ),
          ],
        ),
      ],
    );
    final asset = await assets.put(
      bytes: Uint8List.fromList(utf8.encode(jsonEncode(course.toJson()))),
      fileName: 'draft.json',
      mimeType: 'application/vnd.verbaseed.course+json',
    );
    final jobId = await imports.enqueue(
      ContentSource(
        type: ContentSourceType.image,
        displayName: 'draft.png',
        metadata: {
          DocumentImportCoordinator.courseDraftAssetMetadataKey: asset.toJson(),
          'courseDraftStatus': 'ready',
        },
      ),
    );
    final learnerId = await learners.createProfile(displayName: 'Mia');
    final service = CourseInstallationService(
      reviewService: CourseDraftReviewService(
        database: database,
        repository: imports,
        assetStore: assets,
      ),
      installationRepository: CourseInstallationRepository(database),
      reviewRepository: ReviewRepository(database),
    );

    await expectLater(
      service.installAcceptedDraft(jobId: jobId, learnerId: learnerId),
      throwsA(isA<StateError>()),
    );
  });
}
