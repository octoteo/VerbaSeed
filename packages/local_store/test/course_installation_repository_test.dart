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
