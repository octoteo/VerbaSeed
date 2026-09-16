import 'dart:convert';

import 'package:content_source/content_source.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learning_engine/learning_engine.dart';
import 'package:local_store/local_store.dart';

void main() {
  late VerbaSeedDatabase database;
  late LearnerRepository learners;
  late ReviewRepository reviews;
  late ImportRepository imports;
  late CourseInstallationRepository installs;
  late BackupRepository backups;

  setUp(() {
    database = VerbaSeedDatabase(NativeDatabase.memory());
    learners = LearnerRepository(database);
    reviews = ReviewRepository(database);
    imports = ImportRepository(database);
    installs = CourseInstallationRepository(database);
    backups = BackupRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  test('round trips learner state, course history and referenced provenance only', () async {
    final mia = await learners.createProfile(displayName: 'Mia');
    final leo = await learners.createProfile(displayName: 'Leo');
    await learners.setActive(leo);

    final sourceId = await imports.enqueue(
      GitHubCourseSource.parse('https://github.com/octoteo/course')
          .toContentSource(),
    );
    await imports.updateStatus(sourceId, ImportJobState.ready);
    final transientId = await imports.enqueue(
      const ContentSource(
        type: ContentSourceType.plainText,
        displayName: 'unfinished',
        metadata: {'text': 'temporary'},
      ),
    );

    await installs.installCourse(
      courseId: 'course-1',
      title: 'Starter v1',
      assetId: _assetId('a'),
      sourceJobId: sourceId,
      itemCount: 1,
      lessonCount: 1,
    );
    await installs.installCourse(
      courseId: 'course-1',
      title: 'Starter v2',
      assetId: _assetId('b'),
      sourceJobId: sourceId,
      itemCount: 1,
      lessonCount: 1,
    );
    await installs.enrollLearner(
      learnerId: mia,
      courseId: 'course-1',
      version: 1,
    );
    await installs.enrollLearner(
      learnerId: leo,
      courseId: 'course-1',
      version: 2,
    );
    await reviews.loadOrCreate(learnerId: mia, itemId: 'item-v1');
    await reviews.reviewItem(
      learnerId: mia,
      itemId: 'item-v1',
      rating: RecallRating.good,
    );

    final snapshot = await backups.exportSnapshot();
    expect(snapshot.learnerProfiles, hasLength(2));
    expect(snapshot.installedCourseVersions, hasLength(2));
    expect(snapshot.courseSources.map((row) => row['id']).toList(), [sourceId]);
    expect(snapshot.courseSources.any((row) => row['id'] == transientId), isFalse);

    await learners.createProfile(displayName: 'Temporary');
    await imports.enqueue(
      const ContentSource(
        type: ContentSourceType.plainText,
        displayName: 'after-export',
        metadata: {'text': 'discard me'},
      ),
    );

    await backups.replaceWithSnapshot(snapshot);

    final restoredProfiles = await database.select(database.learnerProfiles).get();
    expect(restoredProfiles, hasLength(2));
    expect(restoredProfiles.where((profile) => profile.isActive).single.id, leo);
    final restoredSources = await database.select(database.importJobs).get();
    expect(restoredSources.map((job) => job.id).toList(), [sourceId]);
    final restoredCourse = await installs.installedCourse('course-1');
    expect(restoredCourse?.currentVersion, 2);
    final restoredVersions = await database.select(database.installedCourseVersions).get();
    expect(restoredVersions.map((row) => row.version).toSet(), {1, 2});
    final restoredEnrollments = await database.select(database.learnerCourseEnrollments).get();
    expect(
      {
        for (final row in restoredEnrollments) row.learnerId: row.version,
      },
      {mia: 1, leo: 2},
    );
    final restoredCards = await database.select(database.reviewCards).get();
    final restoredEvents = await database.select(database.reviewEvents).get();
    expect(restoredCards.single.itemId, 'item-v1');
    expect(restoredEvents.single.rating, RecallRating.good.name);
  });

  test('stale installed source references are normalized instead of blocking backup', () async {
    final learnerId = await learners.createProfile(displayName: 'Mia');
    final sourceId = await imports.enqueue(
      const ContentSource(
        type: ContentSourceType.plainText,
        displayName: 'source owned by learner',
        metadata: {'kind': 'installed'},
      ),
      learnerId: learnerId,
    );
    await imports.updateStatus(sourceId, ImportJobState.ready);
    await installs.installCourse(
      courseId: 'course-1',
      title: 'Starter',
      assetId: _assetId('c'),
      sourceJobId: sourceId,
      itemCount: 1,
      lessonCount: 1,
    );

    await (database.delete(database.importJobs)
          ..where((table) => table.id.equals(sourceId)))
        .go();

    final snapshot = await backups.exportSnapshot();
    expect(snapshot.courseSources, isEmpty);
    expect(snapshot.installedCourses.single['sourceJobId'], isNull);
    expect(snapshot.installedCourseVersions.single['sourceJobId'], isNull);
  });

  test('referenced provenance may retain a learner id that no longer exists', () async {
    final sourceOwner = await learners.createProfile(displayName: 'Source owner');
    final sourceId = await imports.enqueue(
      const ContentSource(
        type: ContentSourceType.plainText,
        displayName: 'installed source',
        metadata: {'kind': 'installed'},
      ),
      learnerId: sourceOwner,
    );
    await imports.updateStatus(sourceId, ImportJobState.ready);
    await installs.installCourse(
      courseId: 'course-1',
      title: 'Starter',
      assetId: _assetId('d'),
      sourceJobId: sourceId,
      itemCount: 1,
      lessonCount: 1,
    );
    await learners.createProfile(displayName: 'Remaining learner', makeActive: true);
    await learners.deleteProfile(sourceOwner);

    final snapshot = await backups.exportSnapshot();
    expect(snapshot.courseSources.single['id'], sourceId);
    expect(snapshot.courseSources.single['learnerId'], sourceOwner);
    backups.validateSnapshot(snapshot);
  });

  test('invalid restore is rejected before replacing current local state', () async {
    final originalId = await learners.createProfile(displayName: 'Original');
    final snapshot = await backups.exportSnapshot();
    final decoded = Map<String, Object?>.from(
      jsonDecode(jsonEncode(snapshot.toJson())) as Map,
    );
    final profiles = List<Object?>.from(decoded['learnerProfiles']! as List);
    final first = Map<String, Object?>.from(profiles.single! as Map);
    first['isActive'] = false;
    profiles[0] = first;
    decoded['learnerProfiles'] = profiles;
    final invalid = LocalBackupSnapshot.fromJson(decoded);

    await expectLater(
      backups.replaceWithSnapshot(invalid),
      throwsA(isA<FormatException>()),
    );

    final rows = await database.select(database.learnerProfiles).get();
    expect(rows.single.id, originalId);
    expect(rows.single.displayName, 'Original');
    expect(rows.single.isActive, isTrue);
  });

  test('rejects a review card whose dueAt diverges from serialized FSRS state', () async {
    final learnerId = await learners.createProfile(displayName: 'Mia');
    await reviews.loadOrCreate(learnerId: learnerId, itemId: 'item-1');
    final snapshot = await backups.exportSnapshot();
    final decoded = Map<String, Object?>.from(
      jsonDecode(jsonEncode(snapshot.toJson())) as Map,
    );
    final cards = List<Object?>.from(decoded['reviewCards']! as List);
    final card = Map<String, Object?>.from(cards.single! as Map);
    card['dueAt'] = DateTime.utc(2099).toIso8601String();
    cards[0] = card;
    decoded['reviewCards'] = cards;

    expect(
      () => backups.validateSnapshot(LocalBackupSnapshot.fromJson(decoded)),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects unsupported backup data versions', () async {
    final snapshot = await backups.exportSnapshot();
    final decoded = Map<String, Object?>.from(
      jsonDecode(jsonEncode(snapshot.toJson())) as Map,
    );
    decoded['dataVersion'] = localBackupDataVersion + 1;

    expect(
      () => backups.validateSnapshot(LocalBackupSnapshot.fromJson(decoded)),
      throwsA(isA<FormatException>()),
    );
  });
}

String _assetId(String character) => List.filled(64, character).join();
