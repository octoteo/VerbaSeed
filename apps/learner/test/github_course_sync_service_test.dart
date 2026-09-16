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
import 'package:verbaseed_learner/src/data/github_course_sync_service.dart';

void main() {
  const sha1 = '0123456789abcdef0123456789abcdef01234567';
  const sha2 = '89abcdef0123456789abcdef0123456789abcdef';
  const sha3 = 'fedcba9876543210fedcba9876543210fedcba98';

  test('installs a validated GitHub import as an immutable local course', () async {
    final harness = _Harness();
    addTearDown(harness.close);

    final snapshot = _snapshot(
      sha: sha1,
      course: _course(title: 'Starter v1', itemId: 'item-v1', text: 'Hello'),
    );
    final jobId = await _enqueueReadyGitHubImport(harness.imports, snapshot);

    final result = await harness.sync.installImportedCourse(jobId);

    expect(result.version, 1);
    expect(result.commitSha, sha1);
    expect(result.reusedVersion, isFalse);
    final installed = await harness.installs.installedCourse('course-1');
    expect(installed, isNotNull);
    expect(installed!.sourceJobId, jobId);
    final current = await harness.installs.currentVersion('course-1');
    expect(current?.version, 1);
    expect(await harness.assets.contains(current!.assetId), isTrue);
    final storedJob = await harness.imports.getJob(jobId);
    final storedSource = harness.imports.decodeSource(storedJob!);
    expect(storedSource.metadata['githubSyncKind'], 'installed');
    expect(storedSource.metadata['resolvedCommit'], sha1);
    expect(await harness.database.select(harness.database.learnerCourseEnrollments).get(), isEmpty);
    expect(await harness.database.select(harness.database.reviewCards).get(), isEmpty);
  });

  test('applies exactly the previewed commit and preserves existing learner pin', () async {
    final harness = _Harness();
    addTearDown(harness.close);

    final v1 = _snapshot(
      sha: sha1,
      course: _course(title: 'Starter v1', itemId: 'item-v1', text: 'Hello'),
    );
    final v1JobId = await _enqueueReadyGitHubImport(harness.imports, v1);
    await harness.sync.installImportedCourse(v1JobId);

    final mia = await harness.learners.createProfile(displayName: 'Mia');
    await harness.installationService.enrollInstalledCourse(
      courseId: 'course-1',
      learnerId: mia,
    );
    final miaCardBefore = await (harness.database.select(harness.database.reviewCards)
          ..where((table) => table.learnerId.equals(mia)))
        .getSingle();

    harness.remote.update = _snapshot(
      sha: sha2,
      course: _course(
        title: 'Starter v2',
        itemId: 'item-v2',
        text: 'Goodbye',
      ),
    );
    final installedBefore = await harness.installs.installedCourse('course-1');
    final sourceJobBefore = await harness.imports.getJob(installedBefore!.sourceJobId!);
    final tracking = harness.sync.trackingForLocal(
      course: installedBefore,
      sourceJob: sourceJobBefore,
    )!;
    final preview = await harness.sync.checkForUpdate(tracking);
    expect(preview?.snapshot.commitSha, sha2);

    harness.remote.update = _snapshot(
      sha: sha3,
      course: _course(
        title: 'Starter v3',
        itemId: 'item-v3',
        text: 'See you',
      ),
    );
    final result = await harness.sync.applyUpdate(preview!);

    expect(result.commitSha, sha2);
    expect(result.version, 2);
    expect(harness.remote.fetchUpdateCalls, 1);
    final installedAfter = await harness.installs.installedCourse('course-1');
    expect(installedAfter?.currentVersion, 2);
    expect(installedAfter?.title, 'Starter v2');
    final sourceJobAfter = await harness.imports.getJob(installedAfter!.sourceJobId!);
    final sourceAfter = harness.imports.decodeSource(sourceJobAfter!);
    expect(sourceAfter.metadata['resolvedCommit'], sha2);

    final miaEnrollment = await (harness.database.select(
      harness.database.learnerCourseEnrollments,
    )..where((table) => table.learnerId.equals(mia))).getSingle();
    expect(miaEnrollment.version, 1);
    final miaCardAfter = await (harness.database.select(harness.database.reviewCards)
          ..where((table) => table.learnerId.equals(mia)))
        .getSingle();
    expect(miaCardAfter.itemId, 'item-v1');
    expect(miaCardAfter.cardJson, miaCardBefore.cardJson);
    expect(miaCardAfter.dueAt, miaCardBefore.dueAt);
    expect(miaCardAfter.updatedAt, miaCardBefore.updatedAt);

    final leo = await harness.learners.createProfile(displayName: 'Leo');
    final leoEnrollment = await harness.installationService.enrollInstalledCourse(
      courseId: 'course-1',
      learnerId: leo,
    );
    expect(leoEnrollment.version, 2);
    final leoCards = await (harness.database.select(harness.database.reviewCards)
          ..where((table) => table.learnerId.equals(leo)))
        .get();
    expect(leoCards.map((card) => card.itemId), ['item-v2']);

    await harness.installationService.setCurrentVersion(
      courseId: 'course-1',
      version: 1,
    );
    final rolledBack = await harness.installs.installedCourse('course-1');
    expect(rolledBack?.currentVersion, 1);
    final miaAfterRollback = await (harness.database.select(
      harness.database.learnerCourseEnrollments,
    )..where((table) => table.learnerId.equals(mia))).getSingle();
    final leoAfterRollback = await (harness.database.select(
      harness.database.learnerCourseEnrollments,
    )..where((table) => table.learnerId.equals(leo))).getSingle();
    expect(miaAfterRollback.version, 1);
    expect(leoAfterRollback.version, 2);
  });

  test('same course bytes at a newer commit reuse the version but advance provenance', () async {
    final harness = _Harness();
    addTearDown(harness.close);

    final course = _course(title: 'Starter', itemId: 'item-v1', text: 'Hello');
    final v1 = _snapshot(sha: sha1, course: course);
    final jobId = await _enqueueReadyGitHubImport(harness.imports, v1);
    await harness.sync.installImportedCourse(jobId);

    harness.remote.update = _snapshot(sha: sha2, course: course);
    final current = await harness.installs.installedCourse('course-1');
    final currentJob = await harness.imports.getJob(current!.sourceJobId!);
    final tracking = harness.sync.trackingForLocal(
      course: current,
      sourceJob: currentJob,
    )!;
    final preview = await harness.sync.checkForUpdate(tracking);
    final result = await harness.sync.applyUpdate(preview!);

    expect(result.reusedVersion, isTrue);
    expect(result.version, 1);
    final updatedCourse = await harness.installs.installedCourse('course-1');
    final updatedJob = await harness.imports.getJob(updatedCourse!.sourceJobId!);
    final updatedTracking = harness.sync.trackingForLocal(
      course: updatedCourse,
      sourceJob: updatedJob,
    )!;
    expect(updatedTracking.commitSha, sha2);

    harness.remote.update = _snapshot(sha: sha2, course: course);
    expect(await harness.sync.checkForUpdate(updatedTracking), isNull);
  });

  test('rejects a stale update preview after the device default changes', () async {
    final harness = _Harness();
    addTearDown(harness.close);

    final v1 = _snapshot(
      sha: sha1,
      course: _course(title: 'Starter v1', itemId: 'item-v1', text: 'Hello'),
    );
    final jobId = await _enqueueReadyGitHubImport(harness.imports, v1);
    await harness.sync.installImportedCourse(jobId);

    harness.remote.update = _snapshot(
      sha: sha2,
      course: _course(
        title: 'Remote v2',
        itemId: 'item-v2',
        text: 'Goodbye',
      ),
    );
    final current = await harness.installs.installedCourse('course-1');
    final currentJob = await harness.imports.getJob(current!.sourceJobId!);
    final tracking = harness.sync.trackingForLocal(
      course: current,
      sourceJob: currentJob,
    )!;
    final preview = await harness.sync.checkForUpdate(tracking);

    final localCourse = _course(
      title: 'Local alternate',
      itemId: 'item-local',
      text: 'Local',
    );
    final localAsset = await _putCourse(harness.assets, localCourse, 'local.json');
    await harness.installs.installCourse(
      courseId: localCourse.id,
      title: localCourse.title,
      assetId: localAsset.id,
      itemCount: 1,
      lessonCount: 1,
    );

    await expectLater(
      harness.sync.applyUpdate(preview!),
      throwsA(isA<StateError>()),
    );
    final after = await harness.installs.installedCourse('course-1');
    expect(after?.currentVersion, 2);
    expect(after?.title, 'Local alternate');
    expect(await harness.database.select(harness.database.installedCourseVersions).get(), hasLength(2));
  });
}

final class _Harness {
  _Harness()
      : database = VerbaSeedDatabase(NativeDatabase.memory()),
        assets = MemoryContentAssetStore(),
        remote = _FakeGitHubRemote() {
    imports = ImportRepository(database);
    installs = CourseInstallationRepository(database);
    reviews = ReviewRepository(database);
    learners = LearnerRepository(database);
    sync = GitHubCourseSyncService(
      remote: remote,
      importRepository: imports,
      installationRepository: installs,
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
  final _FakeGitHubRemote remote;
  late final ImportRepository imports;
  late final CourseInstallationRepository installs;
  late final ReviewRepository reviews;
  late final LearnerRepository learners;
  late final GitHubCourseSyncService sync;
  late final CourseInstallationService installationService;

  Future<void> close() async {
    await assets.close();
    await database.close();
  }
}

final class _FakeGitHubRemote implements GitHubCourseRemote {
  GitHubCourseSnapshot? update;
  int fetchUpdateCalls = 0;

  @override
  Future<GitHubCourseSnapshot> fetch(
    GitHubCourseSource source, {
    String manifestName = 'course.json',
  }) =>
      throw UnimplementedError();

  @override
  Future<GitHubCourseSnapshot> fetchAtCommit(
    GitHubCourseSource source,
    String commitSha, {
    String manifestName = 'course.json',
  }) =>
      throw UnimplementedError();

  @override
  Future<GitHubCourseSnapshot?> fetchUpdate(
    GitHubCourseSource source, {
    required String currentCommitSha,
    String manifestName = 'course.json',
  }) async {
    fetchUpdateCalls += 1;
    final candidate = update;
    if (candidate == null || candidate.commitSha == currentCommitSha) {
      return null;
    }
    return candidate;
  }
}

GitHubCourseSnapshot _snapshot({
  required String sha,
  required Course course,
}) {
  const source = GitHubCourseSource(
    owner: 'example',
    repository: 'course',
    ref: 'main',
  );
  return GitHubCourseSnapshot(
    source: source,
    commitSha: sha,
    manifestUri: source.manifestUri(resolvedRef: sha),
    course: course,
    fetchedAt: DateTime.utc(2026, 9, 16),
  );
}

Future<String> _enqueueReadyGitHubImport(
  ImportRepository imports,
  GitHubCourseSnapshot snapshot,
) async {
  final source = snapshot.source.toContentSource().copyWith(
        metadata: snapshot.toMetadata(),
      );
  final id = await imports.enqueue(source);
  await imports.updateStatus(id, ImportJobState.ready);
  return id;
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
                  translation: '翻译',
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
