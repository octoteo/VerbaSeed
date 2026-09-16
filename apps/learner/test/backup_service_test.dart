import 'dart:convert';
import 'dart:typed_data';

import 'package:content_source/content_source.dart';
import 'package:content_store/content_store.dart';
import 'package:course_schema/course_schema.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learning_engine/learning_engine.dart';
import 'package:local_store/local_store.dart';
import 'package:verbaseed_learner/src/data/backup_service.dart';
import 'package:verbaseed_learner/src/data/course_draft_review_service.dart';
import 'package:verbaseed_learner/src/data/course_installation_service.dart';

void main() {
  test('portable backup restores historical courses, learner pins and review state', () async {
    final source = _Harness();
    final destination = _Harness();
    addTearDown(source.close);
    addTearDown(destination.close);

    final mia = await source.learners.createProfile(displayName: 'Mia');
    final leo = await source.learners.createProfile(displayName: 'Leo');
    await source.learners.setActive(leo);
    final sourceJobId = await source.imports.enqueue(
      const ContentSource(
        type: ContentSourceType.plainText,
        displayName: 'installed-course-source',
        metadata: {'kind': 'installed-course-provenance'},
      ),
    );
    await source.imports.updateStatus(sourceJobId, ImportJobState.ready);
    final transientJobId = await source.imports.enqueue(
      const ContentSource(
        type: ContentSourceType.plainText,
        displayName: 'unfinished-import',
        metadata: {'text': 'do not back up'},
      ),
    );

    final v1 = _course(title: 'Starter v1', itemId: 'item-v1', text: 'Hello');
    final v2 = _course(title: 'Starter v2', itemId: 'item-v2', text: 'Goodbye');
    final v1Asset = await _putCourse(source.assets, v1, 'course-v1.json');
    final v2Asset = await _putCourse(source.assets, v2, 'course-v2.json');
    await source.installs.installCourse(
      courseId: v1.id,
      title: v1.title,
      assetId: v1Asset.id,
      sourceJobId: sourceJobId,
      itemCount: 1,
      lessonCount: 1,
    );
    await source.installs.installCourse(
      courseId: v2.id,
      title: v2.title,
      assetId: v2Asset.id,
      sourceJobId: sourceJobId,
      itemCount: 1,
      lessonCount: 1,
    );
    await source.installs.enrollLearner(
      learnerId: mia,
      courseId: v1.id,
      version: 1,
    );
    await source.installs.enrollLearner(
      learnerId: leo,
      courseId: v2.id,
      version: 2,
    );
    await source.reviews.loadOrCreate(learnerId: mia, itemId: 'item-v1');
    await source.reviews.reviewItem(
      learnerId: mia,
      itemId: 'item-v1',
      rating: RecallRating.good,
    );

    final bytes = await source.backupService.exportBackup();
    final preview = source.backupService.inspectBackup(bytes);
    expect(preview.learnerCount, 2);
    expect(preview.courseCount, 1);
    expect(preview.courseVersionCount, 2);
    expect(preview.enrollmentCount, 2);
    expect(preview.reviewEventCount, 1);
    expect(preview.courseSourceCount, 1);

    final oldDestinationLearner =
        await destination.learners.createProfile(displayName: 'Replace me');
    expect(oldDestinationLearner, isNotEmpty);

    final restored = await destination.backupService.restoreBackup(bytes);
    expect(restored.restoredCourseAssetCount, 2);

    final restoredProfiles =
        await destination.database.select(destination.database.learnerProfiles).get();
    expect(restoredProfiles, hasLength(2));
    expect(restoredProfiles.where((row) => row.isActive).single.id, leo);
    expect(restoredProfiles.any((row) => row.id == oldDestinationLearner), isFalse);

    final restoredCourse = await destination.installs.installedCourse('course-1');
    expect(restoredCourse?.currentVersion, 2);
    expect(restoredCourse?.title, 'Starter v2');
    final restoredVersions = await destination.database
        .select(destination.database.installedCourseVersions)
        .get();
    expect(restoredVersions.map((row) => row.version).toSet(), {1, 2});
    for (final version in restoredVersions) {
      expect(await destination.assets.contains(version.assetId), isTrue);
    }

    final enrollments = await destination.database
        .select(destination.database.learnerCourseEnrollments)
        .get();
    expect(
      {for (final row in enrollments) row.learnerId: row.version},
      {mia: 1, leo: 2},
    );
    final cards =
        await destination.database.select(destination.database.reviewCards).get();
    final events =
        await destination.database.select(destination.database.reviewEvents).get();
    expect(cards.single.itemId, 'item-v1');
    expect(events.single.rating, RecallRating.good.name);

    final restoredJobs =
        await destination.database.select(destination.database.importJobs).get();
    expect(restoredJobs.map((job) => job.id), [sourceJobId]);
    expect(restoredJobs.any((job) => job.id == transientJobId), isFalse);

    await destination.installationService.setCurrentVersion(
      courseId: 'course-1',
      version: 1,
    );
    final rolledBack = await destination.installs.installedCourse('course-1');
    expect(rolledBack?.currentVersion, 1);
    expect(rolledBack?.title, 'Starter v1');
    final pinnedAfterRollback = await destination.database
        .select(destination.database.learnerCourseEnrollments)
        .get();
    expect(
      {for (final row in pinnedAfterRollback) row.learnerId: row.version},
      {mia: 1, leo: 2},
    );
  });

  test('tampered course manifest is rejected before current learner data changes', () async {
    final source = _Harness();
    final destination = _Harness();
    addTearDown(source.close);
    addTearDown(destination.close);

    await source.learners.createProfile(displayName: 'Source learner');
    final course = _course(title: 'Starter', itemId: 'item-1', text: 'Hello');
    final asset = await _putCourse(source.assets, course, 'course.json');
    await source.installs.installCourse(
      courseId: course.id,
      title: course.title,
      assetId: asset.id,
      itemCount: 1,
      lessonCount: 1,
    );
    final backup = await source.backupService.exportBackup();

    final decoded = Map<String, Object?>.from(
      jsonDecode(utf8.decode(backup)) as Map,
    );
    final manifests = List<Object?>.from(decoded['courseManifests']! as List);
    final entry = Map<String, Object?>.from(manifests.single! as Map);
    entry['manifestJson'] = (entry['manifestJson']! as String).replaceFirst(
      'Hello',
      'Tampered',
    );
    manifests[0] = entry;
    decoded['courseManifests'] = manifests;
    final tampered = Uint8List.fromList(utf8.encode(jsonEncode(decoded)));

    final destinationLearner =
        await destination.learners.createProfile(displayName: 'Keep me');
    await expectLater(
      destination.backupService.restoreBackup(tampered),
      throwsA(isA<FormatException>()),
    );

    final profiles =
        await destination.database.select(destination.database.learnerProfiles).get();
    expect(profiles.single.id, destinationLearner);
    expect(profiles.single.displayName, 'Keep me');
    expect(
      await destination.database.select(destination.database.installedCourses).get(),
      isEmpty,
    );
  });

  test('export refuses an installed historical version whose asset is missing', () async {
    final harness = _Harness();
    addTearDown(harness.close);

    await harness.learners.createProfile(displayName: 'Mia');
    await harness.installs.installCourse(
      courseId: 'course-1',
      title: 'Missing course',
      assetId: _fakeAssetId('c'),
      itemCount: 1,
      lessonCount: 1,
    );

    await expectLater(
      harness.backupService.exportBackup(),
      throwsA(isA<StateError>()),
    );
  });
}

final class _Harness {
  _Harness()
      : database = VerbaSeedDatabase(NativeDatabase.memory()),
        assets = MemoryContentAssetStore() {
    learners = LearnerRepository(database);
    reviews = ReviewRepository(database);
    imports = ImportRepository(database);
    installs = CourseInstallationRepository(database);
    backupRepository = BackupRepository(database);
    backupService = VerbaSeedBackupService(
      backupRepository: backupRepository,
      assetStore: assets,
    );
    installationService = CourseInstallationService(
      reviewService: CourseDraftReviewService(
        database: database,
        repository: imports,
        assetStore: assets,
      ),
      installationRepository: installs,
      reviewRepository: reviews,
      assetStore: assets,
    );
  }

  final VerbaSeedDatabase database;
  final MemoryContentAssetStore assets;
  late final LearnerRepository learners;
  late final ReviewRepository reviews;
  late final ImportRepository imports;
  late final CourseInstallationRepository installs;
  late final BackupRepository backupRepository;
  late final VerbaSeedBackupService backupService;
  late final CourseInstallationService installationService;

  Future<void> close() async {
    await assets.close();
    await database.close();
  }
}

Course _course({
  required String title,
  required String itemId,
  required String text,
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
              items: [
                LearningItem(
                  id: itemId,
                  text: text,
                  translation: '你好',
                ),
              ],
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

String _fakeAssetId(String character) => List.filled(64, character).join();
