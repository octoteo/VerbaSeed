import 'dart:convert';
import 'dart:typed_data';

import 'package:content_store/content_store.dart';
import 'package:course_schema/course_schema.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_store/local_store.dart';
import 'package:verbaseed_learner/src/data/course_draft_review_service.dart';
import 'package:verbaseed_learner/src/data/course_installation_service.dart';

void main() {
  test('new enrollment follows rollback asset and rollback restores title', () async {
    final database = VerbaSeedDatabase(NativeDatabase.memory());
    final assets = MemoryContentAssetStore();
    addTearDown(() async {
      await assets.close();
      await database.close();
    });

    final learners = LearnerRepository(database);
    final installs = CourseInstallationRepository(database);
    final imports = ImportRepository(database);
    final reviews = ReviewRepository(database);
    final service = CourseInstallationService(
      reviewService: CourseDraftReviewService(
        database: database,
        repository: imports,
        assetStore: assets,
      ),
      installationRepository: installs,
      reviewRepository: reviews,
      assetStore: assets,
    );

    final v1Course = _course(
      title: 'Starter v1',
      items: const [
        LearningItem(id: 'v1-item', text: 'Hello', translation: '你好'),
      ],
    );
    final v2Course = _course(
      title: 'Starter v2',
      items: const [
        LearningItem(id: 'v2-item', text: 'Goodbye', translation: '再见'),
      ],
    );
    final v1Asset = await _putCourse(assets, v1Course, 'v1.json');
    final v2Asset = await _putCourse(assets, v2Course, 'v2.json');

    await installs.installCourse(
      courseId: 'course-1',
      title: v1Course.title,
      assetId: v1Asset.id,
      itemCount: 1,
      lessonCount: 1,
    );
    await installs.installCourse(
      courseId: 'course-1',
      title: v2Course.title,
      assetId: v2Asset.id,
      itemCount: 1,
      lessonCount: 1,
    );
    await service.setCurrentVersion(courseId: 'course-1', version: 1);

    final installedCourse =
        await database.select(database.installedCourses).getSingle();
    expect(installedCourse.currentVersion, 1);
    expect(installedCourse.title, 'Starter v1');

    final learnerId = await learners.createProfile(displayName: 'Mia');
    final result = await service.enrollInstalledCourse(
      courseId: 'course-1',
      learnerId: learnerId,
    );

    expect(result.version, 1);
    final enrollment =
        await database.select(database.learnerCourseEnrollments).getSingle();
    expect(enrollment.version, 1);
    final cards = await database.select(database.reviewCards).get();
    expect(cards.map((card) => card.itemId), ['v1-item']);
  });

  test('existing learner pin and review plan survive device rollback', () async {
    final database = VerbaSeedDatabase(NativeDatabase.memory());
    final assets = MemoryContentAssetStore();
    addTearDown(() async {
      await assets.close();
      await database.close();
    });

    final learners = LearnerRepository(database);
    final installs = CourseInstallationRepository(database);
    final imports = ImportRepository(database);
    final reviews = ReviewRepository(database);
    final service = CourseInstallationService(
      reviewService: CourseDraftReviewService(
        database: database,
        repository: imports,
        assetStore: assets,
      ),
      installationRepository: installs,
      reviewRepository: reviews,
      assetStore: assets,
    );

    final v1Course = _course(
      title: 'Starter v1',
      items: const [
        LearningItem(id: 'v1-item', text: 'Hello', translation: '你好'),
      ],
    );
    final v2Course = _course(
      title: 'Starter v2',
      items: const [
        LearningItem(id: 'v2-item', text: 'Goodbye', translation: '再见'),
      ],
    );
    final v1Asset = await _putCourse(assets, v1Course, 'v1.json');
    final v2Asset = await _putCourse(assets, v2Course, 'v2.json');

    await installs.installCourse(
      courseId: 'course-1',
      title: v1Course.title,
      assetId: v1Asset.id,
      itemCount: 1,
      lessonCount: 1,
    );
    await installs.installCourse(
      courseId: 'course-1',
      title: v2Course.title,
      assetId: v2Asset.id,
      itemCount: 1,
      lessonCount: 1,
    );

    final learnerId = await learners.createProfile(displayName: 'Mia');
    await service.enrollInstalledCourse(
      courseId: 'course-1',
      learnerId: learnerId,
    );
    final beforeCard = await database.select(database.reviewCards).getSingle();

    await service.setCurrentVersion(courseId: 'course-1', version: 1);

    final enrollment =
        await database.select(database.learnerCourseEnrollments).getSingle();
    expect(enrollment.version, 2);
    final afterCard = await database.select(database.reviewCards).getSingle();
    expect(afterCard.itemId, 'v2-item');
    expect(afterCard.cardJson, beforeCard.cardJson);
    expect(afterCard.dueAt, beforeCard.dueAt);
    expect(afterCard.lastReviewedAt, beforeCard.lastReviewedAt);
    expect(afterCard.updatedAt, beforeCard.updatedAt);
  });

  test('rollback rejects a missing historical asset without moving default', () async {
    final database = VerbaSeedDatabase(NativeDatabase.memory());
    final assets = MemoryContentAssetStore();
    addTearDown(() async {
      await assets.close();
      await database.close();
    });

    final installs = CourseInstallationRepository(database);
    final imports = ImportRepository(database);
    final reviews = ReviewRepository(database);
    final service = CourseInstallationService(
      reviewService: CourseDraftReviewService(
        database: database,
        repository: imports,
        assetStore: assets,
      ),
      installationRepository: installs,
      reviewRepository: reviews,
      assetStore: assets,
    );

    final v1Course = _course(
      title: 'Starter v1',
      items: const [
        LearningItem(id: 'v1-item', text: 'Hello', translation: '你好'),
      ],
    );
    final v2Course = _course(
      title: 'Starter v2',
      items: const [
        LearningItem(id: 'v2-item', text: 'Goodbye', translation: '再见'),
      ],
    );
    final v1Asset = await _putCourse(assets, v1Course, 'v1.json');
    final v2Asset = await _putCourse(assets, v2Course, 'v2.json');

    await installs.installCourse(
      courseId: 'course-1',
      title: v1Course.title,
      assetId: v1Asset.id,
      itemCount: 1,
      lessonCount: 1,
    );
    await installs.installCourse(
      courseId: 'course-1',
      title: v2Course.title,
      assetId: v2Asset.id,
      itemCount: 1,
      lessonCount: 1,
    );
    await assets.delete(v1Asset.id);

    await expectLater(
      service.setCurrentVersion(courseId: 'course-1', version: 1),
      throwsA(isA<StateError>()),
    );

    final current = await installs.currentVersion('course-1');
    expect(current?.version, 2);
    expect(current?.assetId, v2Asset.id);
    final installedCourse =
        await database.select(database.installedCourses).getSingle();
    expect(installedCourse.title, 'Starter v2');
  });
}

Course _course({
  required String title,
  required List<LearningItem> items,
}) =>
    Course(
      id: 'course-1',
      title: title,
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
              items: items,
            ),
          ],
        ),
      ],
    );

Future<ContentAsset> _putCourse(
  ContentAssetStore store,
  Course course,
  String fileName,
) =>
    store.put(
      bytes: Uint8List.fromList(utf8.encode(jsonEncode(course.toJson()))),
      fileName: fileName,
      mimeType: 'application/vnd.verbaseed.course+json',
    );
