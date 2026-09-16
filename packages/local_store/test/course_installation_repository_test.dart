import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_store/local_store.dart';

void main() {
  late VerbaSeedDatabase database;
  late CourseInstallationRepository courses;
  late LearnerRepository learners;

  setUp(() {
    database = VerbaSeedDatabase(NativeDatabase.memory());
    courses = CourseInstallationRepository(
      database,
      clock: () => DateTime.utc(2026, 9, 16, 12),
    );
    learners = LearnerRepository(database);
  });

  tearDown(() => database.close());

  test('installs immutable versions and reuses identical assets', () async {
    final first = await courses.installCourse(
      courseId: 'course-1',
      title: 'My course',
      assetId: 'sha256:first',
      itemCount: 3,
      lessonCount: 1,
      sourceJobId: 'job-1',
    );
    expect(first.version, 1);
    expect(first.reused, isFalse);

    final repeated = await courses.installCourse(
      courseId: 'course-1',
      title: 'My course',
      assetId: 'sha256:first',
      itemCount: 3,
      lessonCount: 1,
      sourceJobId: 'job-1',
    );
    expect(repeated.version, 1);
    expect(repeated.reused, isTrue);

    final second = await courses.installCourse(
      courseId: 'course-1',
      title: 'My revised course',
      assetId: 'sha256:second',
      itemCount: 4,
      lessonCount: 1,
      sourceJobId: 'job-1',
    );
    expect(second.version, 2);
    expect(second.reused, isFalse);

    final versions = await database.select(database.installedCourseVersions).get();
    expect(versions, hasLength(2));
    expect(versions.map((row) => row.assetId), ['sha256:first', 'sha256:second']);

    final course = await database.select(database.installedCourses).getSingle();
    expect(course.currentVersion, 2);
    expect(course.title, 'My revised course');
  });

  test('historical content asset is reused instead of creating a duplicate version', () async {
    await courses.installCourse(
      courseId: 'course-1',
      title: 'Course v1',
      assetId: 'sha256:v1',
      itemCount: 2,
      lessonCount: 1,
      sourceJobId: 'job-v1',
    );
    await courses.installCourse(
      courseId: 'course-1',
      title: 'Course v2',
      assetId: 'sha256:v2',
      itemCount: 3,
      lessonCount: 1,
      sourceJobId: 'job-v2',
    );
    await courses.setCurrentVersion(courseId: 'course-1', version: 1);

    final reused = await courses.installCourse(
      courseId: 'course-1',
      title: 'Course v2',
      assetId: 'sha256:v2',
      itemCount: 3,
      lessonCount: 1,
      sourceJobId: 'job-v2-new-check',
    );

    expect(reused.reused, isTrue);
    expect(reused.version, 2);
    expect(await database.select(database.installedCourseVersions).get(), hasLength(2));
    expect(
      await courses.watchInstalledAssetIds().first,
      {'sha256:v1', 'sha256:v2'},
    );
    final course = await database.select(database.installedCourses).getSingle();
    expect(course.currentVersion, 2);
    expect(course.sourceJobId, 'job-v2-new-check');
  });

  test('new versions stay monotonic after rolling the default backward', () async {
    await courses.installCourse(
      courseId: 'course-1',
      title: 'Course',
      assetId: 'sha256:v1',
      itemCount: 2,
      lessonCount: 1,
    );
    await courses.installCourse(
      courseId: 'course-1',
      title: 'Course',
      assetId: 'sha256:v2',
      itemCount: 3,
      lessonCount: 1,
    );
    await courses.setCurrentVersion(courseId: 'course-1', version: 1);

    final third = await courses.installCourse(
      courseId: 'course-1',
      title: 'Course',
      assetId: 'sha256:v3',
      itemCount: 4,
      lessonCount: 1,
    );

    expect(third.version, 3);
    expect(
      (await courses.currentVersion('course-1'))?.assetId,
      'sha256:v3',
    );
  });

  test('monotonic numbering survives rollback and historical asset reuse', () async {
    await courses.installCourse(
      courseId: 'course-1',
      title: 'Course',
      assetId: 'sha256:v1',
      itemCount: 1,
      lessonCount: 1,
    );
    await courses.installCourse(
      courseId: 'course-1',
      title: 'Course',
      assetId: 'sha256:v2',
      itemCount: 2,
      lessonCount: 1,
    );
    await courses.installCourse(
      courseId: 'course-1',
      title: 'Course',
      assetId: 'sha256:v3',
      itemCount: 3,
      lessonCount: 1,
    );
    await courses.setCurrentVersion(courseId: 'course-1', version: 1);

    final reused = await courses.installCourse(
      courseId: 'course-1',
      title: 'Course',
      assetId: 'sha256:v2',
      itemCount: 2,
      lessonCount: 1,
    );
    expect(reused.version, 2);
    expect(reused.reused, isTrue);

    final fourth = await courses.installCourse(
      courseId: 'course-1',
      title: 'Course',
      assetId: 'sha256:v4',
      itemCount: 4,
      lessonCount: 1,
    );
    expect(fourth.version, 4);
  });

  test('switching device default preserves learner pinned version', () async {
    final learnerId = await learners.createProfile(displayName: 'Mia');
    final v1 = await courses.installCourse(
      courseId: 'course-1',
      title: 'Course',
      assetId: 'sha256:v1',
      itemCount: 2,
      lessonCount: 1,
      sourceJobId: 'job-v1',
    );
    final v2 = await courses.installCourse(
      courseId: 'course-1',
      title: 'Course',
      assetId: 'sha256:v2',
      itemCount: 3,
      lessonCount: 1,
      sourceJobId: 'job-v2',
    );
    await courses.enrollLearner(
      learnerId: learnerId,
      courseId: 'course-1',
      version: v2.version,
    );

    final selected = await courses.setCurrentVersion(
      courseId: 'course-1',
      version: v1.version,
    );

    expect(selected.version, 1);
    final course = await database.select(database.installedCourses).getSingle();
    expect(course.currentVersion, 1);
    expect(course.sourceJobId, 'job-v1');
    final enrollment =
        await database.select(database.learnerCourseEnrollments).getSingle();
    expect(enrollment.version, 2);

    final watched = await courses.watchVersions('course-1').first;
    expect(watched.map((version) => version.version), [2, 1]);
  });

  test('device default switching does not move pins for multiple learners', () async {
    final mia = await learners.createProfile(displayName: 'Mia');
    final leo = await learners.createProfile(displayName: 'Leo');
    final v1 = await courses.installCourse(
      courseId: 'course-1',
      title: 'Course',
      assetId: 'sha256:v1',
      itemCount: 1,
      lessonCount: 1,
    );
    final v2 = await courses.installCourse(
      courseId: 'course-1',
      title: 'Course',
      assetId: 'sha256:v2',
      itemCount: 2,
      lessonCount: 1,
    );
    await courses.enrollLearner(
      learnerId: mia,
      courseId: 'course-1',
      version: v1.version,
    );
    await courses.enrollLearner(
      learnerId: leo,
      courseId: 'course-1',
      version: v2.version,
    );

    await courses.setCurrentVersion(courseId: 'course-1', version: 1);
    await courses.setCurrentVersion(courseId: 'course-1', version: 2);

    final enrollments =
        await database.select(database.learnerCourseEnrollments).get();
    final versionsByLearner = {
      for (final enrollment in enrollments)
        enrollment.learnerId: enrollment.version,
    };
    expect(versionsByLearner[mia], 1);
    expect(versionsByLearner[leo], 2);
  });

  test('switching to invalid or unknown versions is rejected', () async {
    await courses.installCourse(
      courseId: 'course-1',
      title: 'Course',
      assetId: 'sha256:v1',
      itemCount: 2,
      lessonCount: 1,
    );

    await expectLater(
      courses.setCurrentVersion(courseId: 'course-1', version: 0),
      throwsA(isA<RangeError>()),
    );
    await expectLater(
      courses.setCurrentVersion(courseId: 'course-1', version: 99),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      courses.setCurrentVersion(courseId: 'missing-course', version: 1),
      throwsA(isA<StateError>()),
    );
  });

  test('enrollment is learner-specific and follows selected course version', () async {
    final learnerId = await learners.createProfile(displayName: 'Mia');
    final installed = await courses.installCourse(
      courseId: 'course-1',
      title: 'My course',
      assetId: 'sha256:first',
      itemCount: 3,
      lessonCount: 1,
    );

    await courses.enrollLearner(
      learnerId: learnerId,
      courseId: installed.courseId,
      version: installed.version,
    );
    await courses.enrollLearner(
      learnerId: learnerId,
      courseId: installed.courseId,
      version: installed.version,
    );

    final enrollments =
        await database.select(database.learnerCourseEnrollments).get();
    expect(enrollments, hasLength(1));
    expect(enrollments.single.learnerId, learnerId);
    expect(enrollments.single.version, 1);
  });
}
