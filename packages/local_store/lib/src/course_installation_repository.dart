import 'package:drift/drift.dart';

import 'database.dart';

final class CourseInstallationResult {
  const CourseInstallationResult({
    required this.courseId,
    required this.version,
    required this.versionId,
    required this.assetId,
    required this.reused,
  });

  final String courseId;
  final int version;
  final String versionId;
  final String assetId;
  final bool reused;
}

final class CourseInstallationRepository {
  CourseInstallationRepository(
    this._db, {
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final VerbaSeedDatabase _db;
  final DateTime Function() _clock;

  Stream<List<InstalledCourse>> watchInstalledCourses() {
    final query = _db.select(_db.installedCourses)
      ..orderBy([(table) => OrderingTerm.desc(table.updatedAt)]);
    return query.watch();
  }

  Stream<List<LearnerCourseEnrollment>> watchEnrollments(String learnerId) {
    final query = _db.select(_db.learnerCourseEnrollments)
      ..where((table) => table.learnerId.equals(learnerId))
      ..orderBy([(table) => OrderingTerm.desc(table.updatedAt)]);
    return query.watch();
  }

  Stream<List<InstalledCourseVersion>> watchVersions(String courseId) {
    final query = _db.select(_db.installedCourseVersions)
      ..where((table) => table.courseId.equals(courseId))
      ..orderBy([(table) => OrderingTerm.desc(table.version)]);
    return query.watch();
  }

  Future<CourseInstallationResult> installCourse({
    required String courseId,
    required String title,
    required String assetId,
    required int itemCount,
    required int lessonCount,
    String? sourceJobId,
  }) async {
    final normalizedCourseId = courseId.trim();
    final normalizedTitle = title.trim();
    final normalizedAssetId = assetId.trim();
    if (normalizedCourseId.isEmpty) {
      throw const FormatException('courseId cannot be empty');
    }
    if (normalizedTitle.isEmpty) {
      throw const FormatException('课程名称不能为空');
    }
    if (normalizedAssetId.isEmpty) {
      throw const FormatException('课程资产标识不能为空');
    }
    if (itemCount < 1 || lessonCount < 1) {
      throw const FormatException('安装课程必须至少包含一个课节和一个学习项');
    }

    return _db.transaction(() async {
      final current = await (_db.select(_db.installedCourses)
            ..where((table) => table.id.equals(normalizedCourseId)))
          .getSingleOrNull();

      if (current != null) {
        final matchingVersion = await (_db.select(_db.installedCourseVersions)
              ..where(
                (table) =>
                    table.courseId.equals(normalizedCourseId) &
                    table.assetId.equals(normalizedAssetId),
              )
              ..limit(1))
            .getSingleOrNull();
        if (matchingVersion != null) {
          if (current.currentVersion != matchingVersion.version ||
              current.title != normalizedTitle ||
              current.sourceJobId != sourceJobId) {
            await (_db.update(_db.installedCourses)
                  ..where((table) => table.id.equals(normalizedCourseId)))
                .write(
              InstalledCoursesCompanion(
                title: Value(normalizedTitle),
                currentVersion: Value(matchingVersion.version),
                sourceJobId: Value(sourceJobId),
                updatedAt: Value(_now()),
              ),
            );
          }
          return CourseInstallationResult(
            courseId: normalizedCourseId,
            version: matchingVersion.version,
            versionId: matchingVersion.id,
            assetId: matchingVersion.assetId,
            reused: true,
          );
        }
      }

      final now = _now();
      final latestInstalledVersion = await (_db.select(_db.installedCourseVersions)
            ..where((table) => table.courseId.equals(normalizedCourseId))
            ..orderBy([(table) => OrderingTerm.desc(table.version)])
            ..limit(1))
          .getSingleOrNull();
      final nextVersion = (latestInstalledVersion?.version ?? 0) + 1;
      if (current == null) {
        await _db.into(_db.installedCourses).insert(
              InstalledCoursesCompanion.insert(
                id: normalizedCourseId,
                title: normalizedTitle,
                currentVersion: nextVersion,
                sourceJobId: Value(sourceJobId),
                installedAt: now,
                updatedAt: now,
              ),
            );
      } else {
        await (_db.update(_db.installedCourses)
              ..where((table) => table.id.equals(normalizedCourseId)))
            .write(
          InstalledCoursesCompanion(
            title: Value(normalizedTitle),
            currentVersion: Value(nextVersion),
            sourceJobId: Value(sourceJobId),
            updatedAt: Value(now),
          ),
        );
      }

      final versionId = '$normalizedCourseId@$nextVersion';
      await _db.into(_db.installedCourseVersions).insert(
            InstalledCourseVersionsCompanion.insert(
              id: versionId,
              courseId: normalizedCourseId,
              version: nextVersion,
              assetId: normalizedAssetId,
              sourceJobId: Value(sourceJobId),
              itemCount: itemCount,
              lessonCount: lessonCount,
              createdAt: now,
            ),
          );

      return CourseInstallationResult(
        courseId: normalizedCourseId,
        version: nextVersion,
        versionId: versionId,
        assetId: normalizedAssetId,
        reused: false,
      );
    });
  }

  Future<InstalledCourseVersion> setCurrentVersion({
    required String courseId,
    required int version,
  }) async {
    if (version < 1) {
      throw RangeError.range(version, 1, null, 'version');
    }

    return _db.transaction(() async {
      final course = await (_db.select(_db.installedCourses)
            ..where((table) => table.id.equals(courseId)))
          .getSingleOrNull();
      if (course == null) {
        throw StateError('本地课程不存在: $courseId');
      }

      final target = await (_db.select(_db.installedCourseVersions)
            ..where(
              (table) =>
                  table.courseId.equals(courseId) & table.version.equals(version),
            ))
          .getSingleOrNull();
      if (target == null) {
        throw StateError('课程版本不存在: $courseId@$version');
      }

      if (course.currentVersion != version ||
          course.sourceJobId != target.sourceJobId) {
        await (_db.update(_db.installedCourses)
              ..where((table) => table.id.equals(courseId)))
            .write(
          InstalledCoursesCompanion(
            currentVersion: Value(version),
            sourceJobId: Value(target.sourceJobId),
            updatedAt: Value(_now()),
          ),
        );
      }
      return target;
    });
  }

  Future<void> enrollLearner({
    required String learnerId,
    required String courseId,
    required int version,
  }) async {
    final learner = await (_db.select(_db.learnerProfiles)
          ..where((table) => table.id.equals(learnerId)))
        .getSingleOrNull();
    if (learner == null) {
      throw StateError('学习者档案不存在: $learnerId');
    }

    final installedVersion = await (_db.select(_db.installedCourseVersions)
          ..where(
            (table) =>
                table.courseId.equals(courseId) & table.version.equals(version),
          ))
        .getSingleOrNull();
    if (installedVersion == null) {
      throw StateError('课程版本不存在: $courseId@$version');
    }

    final now = _now();
    final id = '$learnerId:$courseId';
    final existing = await (_db.select(_db.learnerCourseEnrollments)
          ..where((table) => table.id.equals(id)))
        .getSingleOrNull();
    if (existing == null) {
      await _db.into(_db.learnerCourseEnrollments).insert(
            LearnerCourseEnrollmentsCompanion.insert(
              id: id,
              learnerId: learnerId,
              courseId: courseId,
              version: version,
              enrolledAt: now,
              updatedAt: now,
            ),
          );
      return;
    }

    if (existing.version != version) {
      await (_db.update(_db.learnerCourseEnrollments)
            ..where((table) => table.id.equals(id)))
          .write(
        LearnerCourseEnrollmentsCompanion(
          version: Value(version),
          updatedAt: Value(now),
        ),
      );
    }
  }

  Future<InstalledCourseVersion?> currentVersion(String courseId) async {
    final course = await (_db.select(_db.installedCourses)
          ..where((table) => table.id.equals(courseId)))
        .getSingleOrNull();
    if (course == null) return null;
    return (_db.select(_db.installedCourseVersions)
          ..where(
            (table) =>
                table.courseId.equals(courseId) &
                table.version.equals(course.currentVersion),
          ))
        .getSingleOrNull();
  }

  DateTime _now() => _clock().toUtc();
}
