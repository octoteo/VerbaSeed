import 'dart:convert';

import 'package:content_source/content_source.dart';
import 'package:drift/drift.dart';
import 'package:learning_engine/learning_engine.dart';

import 'database.dart';

const int localBackupDataVersion = 1;

final class LocalBackupSnapshot {
  const LocalBackupSnapshot({
    required this.dataVersion,
    required this.exportedAt,
    required this.learnerProfiles,
    required this.reviewCards,
    required this.reviewEvents,
    required this.courseSources,
    required this.installedCourses,
    required this.installedCourseVersions,
    required this.learnerCourseEnrollments,
  });

  final int dataVersion;
  final DateTime exportedAt;
  final List<Map<String, Object?>> learnerProfiles;
  final List<Map<String, Object?>> reviewCards;
  final List<Map<String, Object?>> reviewEvents;
  final List<Map<String, Object?>> courseSources;
  final List<Map<String, Object?>> installedCourses;
  final List<Map<String, Object?>> installedCourseVersions;
  final List<Map<String, Object?>> learnerCourseEnrollments;

  Map<String, Object?> toJson() => {
        'dataVersion': dataVersion,
        'exportedAt': exportedAt.toUtc().toIso8601String(),
        'learnerProfiles': learnerProfiles,
        'reviewCards': reviewCards,
        'reviewEvents': reviewEvents,
        'courseSources': courseSources,
        'installedCourses': installedCourses,
        'installedCourseVersions': installedCourseVersions,
        'learnerCourseEnrollments': learnerCourseEnrollments,
      };

  factory LocalBackupSnapshot.fromJson(Map<String, Object?> json) =>
      LocalBackupSnapshot(
        dataVersion: _int(json, 'dataVersion'),
        exportedAt: _date(json, 'exportedAt'),
        learnerProfiles: _mapList(json, 'learnerProfiles'),
        reviewCards: _mapList(json, 'reviewCards'),
        reviewEvents: _mapList(json, 'reviewEvents'),
        courseSources: _mapList(json, 'courseSources'),
        installedCourses: _mapList(json, 'installedCourses'),
        installedCourseVersions: _mapList(json, 'installedCourseVersions'),
        learnerCourseEnrollments:
            _mapList(json, 'learnerCourseEnrollments'),
      );
}

final class BackupRepository {
  BackupRepository(this._db, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final VerbaSeedDatabase _db;
  final DateTime Function() _clock;

  Future<LocalBackupSnapshot> exportSnapshot() async {
    final profiles = await _db.select(_db.learnerProfiles).get();
    final cards = await _db.select(_db.reviewCards).get();
    final events = await _db.select(_db.reviewEvents).get();
    final courses = await _db.select(_db.installedCourses).get();
    final versions = await _db.select(_db.installedCourseVersions).get();
    final enrollments = await _db.select(_db.learnerCourseEnrollments).get();

    profiles.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    cards.sort((a, b) => a.id.compareTo(b.id));
    events.sort((a, b) {
      final byTime = a.reviewedAt.compareTo(b.reviewedAt);
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    });
    courses.sort((a, b) => a.id.compareTo(b.id));
    versions.sort((a, b) {
      final byCourse = a.courseId.compareTo(b.courseId);
      return byCourse != 0 ? byCourse : a.version.compareTo(b.version);
    });
    enrollments.sort((a, b) {
      final byLearner = a.learnerId.compareTo(b.learnerId);
      return byLearner != 0
          ? byLearner
          : a.courseId.compareTo(b.courseId);
    });

    final sourceIds = <String>{
      for (final course in courses)
        if (course.sourceJobId != null) course.sourceJobId!,
      for (final version in versions)
        if (version.sourceJobId != null) version.sourceJobId!,
    };
    final sourceRows = sourceIds.isEmpty
        ? <ImportJob>[]
        : await (_db.select(_db.importJobs)
              ..where((table) => table.id.isIn(sourceIds.toList())))
            .get();
    sourceRows.sort((a, b) => a.id.compareTo(b.id));
    final foundSourceIds = sourceRows.map((row) => row.id).toSet();

    final snapshot = LocalBackupSnapshot(
      dataVersion: localBackupDataVersion,
      exportedAt: _clock().toUtc(),
      learnerProfiles: profiles.map(_profileToJson).toList(growable: false),
      reviewCards: cards.map(_reviewCardToJson).toList(growable: false),
      reviewEvents: events.map(_reviewEventToJson).toList(growable: false),
      courseSources: sourceRows.map(_sourceToJson).toList(growable: false),
      installedCourses: courses
          .map((row) => _courseToJson(row, foundSourceIds))
          .toList(growable: false),
      installedCourseVersions: versions
          .map((row) => _courseVersionToJson(row, foundSourceIds))
          .toList(growable: false),
      learnerCourseEnrollments:
          enrollments.map(_enrollmentToJson).toList(growable: false),
    );
    validateSnapshot(snapshot);
    return snapshot;
  }

  void validateSnapshot(LocalBackupSnapshot snapshot) {
    if (snapshot.dataVersion != localBackupDataVersion) {
      throw FormatException(
        'Unsupported local backup data version: ${snapshot.dataVersion}',
      );
    }

    final profileIds = _uniqueIds(snapshot.learnerProfiles, 'learner profile');
    final activeProfiles = snapshot.learnerProfiles
        .where((row) => _bool(row, 'isActive'))
        .length;
    if (snapshot.learnerProfiles.isNotEmpty && activeProfiles != 1) {
      throw const FormatException(
        'A non-empty backup must contain exactly one active learner profile',
      );
    }
    for (final row in snapshot.learnerProfiles) {
      if (_string(row, 'displayName').trim().isEmpty) {
        throw const FormatException('Learner display name cannot be empty');
      }
      _nullableInt(row, 'birthYear');
      _string(row, 'nativeLanguage');
      _string(row, 'targetLanguage');
      _string(row, 'preferredAccent');
      _date(row, 'createdAt');
      _date(row, 'updatedAt');
    }

    final sourceIds = _uniqueIds(snapshot.courseSources, 'course source');
    for (final row in snapshot.courseSources) {
      _nullableString(row, 'learnerId');
      final statusName = _string(row, 'status');
      try {
        ImportJobState.values.byName(statusName);
      } on ArgumentError {
        throw FormatException('Unknown import status: $statusName');
      }
      final sourceJson = _string(row, 'sourceJson');
      final decoded = jsonDecode(sourceJson);
      if (decoded is! Map) {
        throw const FormatException('Course source JSON must be an object');
      }
      final source = ContentSource.fromJson(
        Map<String, Object?>.from(decoded),
      );
      if (source.type.name != _string(row, 'sourceType')) {
        throw const FormatException(
          'Course source type does not match source JSON',
        );
      }
      _date(row, 'createdAt');
      _date(row, 'updatedAt');
    }

    final courseIds = _uniqueIds(snapshot.installedCourses, 'installed course');
    for (final row in snapshot.installedCourses) {
      if (_string(row, 'title').trim().isEmpty) {
        throw const FormatException('Installed course title cannot be empty');
      }
      final currentVersion = _int(row, 'currentVersion');
      if (currentVersion < 1) {
        throw const FormatException('Installed course version must be positive');
      }
      _requireKnownSource(row, sourceIds);
      _date(row, 'installedAt');
      _date(row, 'updatedAt');
    }

    final versionIds = <String>{};
    final versionKeys = <String>{};
    for (final row in snapshot.installedCourseVersions) {
      final id = _string(row, 'id');
      if (!versionIds.add(id)) {
        throw FormatException('Duplicate installed course version id: $id');
      }
      final courseId = _string(row, 'courseId');
      if (!courseIds.contains(courseId)) {
        throw FormatException('Course version references unknown course: $courseId');
      }
      final version = _int(row, 'version');
      if (version < 1) {
        throw const FormatException('Course version must be positive');
      }
      final key = '$courseId@$version';
      if (id != key) {
        throw FormatException('Course version id is not canonical: $id != $key');
      }
      if (!versionKeys.add(key)) {
        throw FormatException('Duplicate installed course version: $key');
      }
      final assetId = _string(row, 'assetId');
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(assetId)) {
        throw FormatException('Invalid content-addressed course asset id: $assetId');
      }
      if (_int(row, 'itemCount') < 1 || _int(row, 'lessonCount') < 1) {
        throw FormatException('Course version must contain lessons and items: $key');
      }
      _requireKnownSource(row, sourceIds);
      _date(row, 'createdAt');
    }
    for (final row in snapshot.installedCourses) {
      final key = '${_string(row, 'id')}@${_int(row, 'currentVersion')}';
      if (!versionKeys.contains(key)) {
        throw FormatException('Installed course points at missing version: $key');
      }
    }

    final enrollmentIds = <String>{};
    final enrollmentKeys = <String>{};
    for (final row in snapshot.learnerCourseEnrollments) {
      final id = _string(row, 'id');
      if (!enrollmentIds.add(id)) {
        throw FormatException('Duplicate enrollment id: $id');
      }
      final learnerId = _string(row, 'learnerId');
      final courseId = _string(row, 'courseId');
      final version = _int(row, 'version');
      if (!profileIds.contains(learnerId)) {
        throw FormatException('Enrollment references unknown learner: $learnerId');
      }
      if (!courseIds.contains(courseId) ||
          !versionKeys.contains('$courseId@$version')) {
        throw FormatException(
          'Enrollment references unknown course version: $courseId@$version',
        );
      }
      final key = '$learnerId:$courseId';
      if (id != key) {
        throw FormatException('Enrollment id is not canonical: $id != $key');
      }
      if (!enrollmentKeys.add(key)) {
        throw FormatException('Duplicate learner/course enrollment: $key');
      }
      _date(row, 'enrolledAt');
      _date(row, 'updatedAt');
    }

    final reviewCardIds = <String>{};
    final learnerItemKeys = <String>{};
    for (final row in snapshot.reviewCards) {
      final id = _string(row, 'id');
      if (!reviewCardIds.add(id)) {
        throw FormatException('Duplicate review card id: $id');
      }
      final learnerId = _string(row, 'learnerId');
      if (!profileIds.contains(learnerId)) {
        throw FormatException('Review card references unknown learner: $learnerId');
      }
      final itemId = _string(row, 'itemId');
      final key = '$learnerId:$itemId';
      if (!learnerItemKeys.add(key)) {
        throw FormatException('Duplicate learner/item review card: $key');
      }
      final state = _reviewState(_string(row, 'cardJson'));
      final dueAt = _date(row, 'dueAt');
      // Drift stores dateTime() as Unix seconds by default, so the dedicated
      // scheduling column intentionally has lower precision than cardJson.
      if (state.due.toUtc().millisecondsSinceEpoch ~/
              Duration.millisecondsPerSecond !=
          dueAt.toUtc().millisecondsSinceEpoch ~/
              Duration.millisecondsPerSecond) {
        throw FormatException('Review card dueAt does not match cardJson: $id');
      }
      _nullableDate(row, 'lastReviewedAt');
      _date(row, 'updatedAt');
    }

    final eventIds = <String>{};
    for (final row in snapshot.reviewEvents) {
      final id = _string(row, 'id');
      if (!eventIds.add(id)) {
        throw FormatException('Duplicate review event id: $id');
      }
      final learnerId = _string(row, 'learnerId');
      if (!profileIds.contains(learnerId)) {
        throw FormatException('Review event references unknown learner: $learnerId');
      }
      final ratingName = _string(row, 'rating');
      try {
        RecallRating.values.byName(ratingName);
      } on ArgumentError {
        throw FormatException('Unknown recall rating: $ratingName');
      }
      _reviewState(_string(row, 'cardJson'));
      _date(row, 'reviewedAt');
    }
  }

  Future<void> replaceWithSnapshot(LocalBackupSnapshot snapshot) async {
    validateSnapshot(snapshot);
    await _db.transaction(() async {
      await _db.delete(_db.reviewEvents).go();
      await _db.delete(_db.reviewCards).go();
      await _db.delete(_db.learnerCourseEnrollments).go();
      await _db.delete(_db.installedCourseVersions).go();
      await _db.delete(_db.installedCourses).go();
      await _db.delete(_db.importJobs).go();
      await _db.delete(_db.learnerProfiles).go();

      for (final row in snapshot.learnerProfiles) {
        await _db.into(_db.learnerProfiles).insert(
              LearnerProfilesCompanion.insert(
                id: _string(row, 'id'),
                displayName: _string(row, 'displayName'),
                birthYear: Value(_nullableInt(row, 'birthYear')),
                nativeLanguage: Value(_string(row, 'nativeLanguage')),
                targetLanguage: Value(_string(row, 'targetLanguage')),
                preferredAccent: Value(_string(row, 'preferredAccent')),
                isActive: Value(_bool(row, 'isActive')),
                createdAt: _date(row, 'createdAt'),
                updatedAt: _date(row, 'updatedAt'),
              ),
            );
      }

      for (final row in snapshot.courseSources) {
        await _db.into(_db.importJobs).insert(
              ImportJobsCompanion.insert(
                id: _string(row, 'id'),
                learnerId: Value(_nullableString(row, 'learnerId')),
                sourceType: _string(row, 'sourceType'),
                displayName: _string(row, 'displayName'),
                sourceJson: _string(row, 'sourceJson'),
                status: _string(row, 'status'),
                errorMessage: Value(_nullableString(row, 'errorMessage')),
                createdAt: _date(row, 'createdAt'),
                updatedAt: _date(row, 'updatedAt'),
              ),
            );
      }

      for (final row in snapshot.installedCourses) {
        await _db.into(_db.installedCourses).insert(
              InstalledCoursesCompanion.insert(
                id: _string(row, 'id'),
                title: _string(row, 'title'),
                currentVersion: _int(row, 'currentVersion'),
                sourceJobId: Value(_nullableString(row, 'sourceJobId')),
                installedAt: _date(row, 'installedAt'),
                updatedAt: _date(row, 'updatedAt'),
              ),
            );
      }

      for (final row in snapshot.installedCourseVersions) {
        await _db.into(_db.installedCourseVersions).insert(
              InstalledCourseVersionsCompanion.insert(
                id: _string(row, 'id'),
                courseId: _string(row, 'courseId'),
                version: _int(row, 'version'),
                assetId: _string(row, 'assetId'),
                sourceJobId: Value(_nullableString(row, 'sourceJobId')),
                itemCount: _int(row, 'itemCount'),
                lessonCount: _int(row, 'lessonCount'),
                createdAt: _date(row, 'createdAt'),
              ),
            );
      }

      for (final row in snapshot.learnerCourseEnrollments) {
        await _db.into(_db.learnerCourseEnrollments).insert(
              LearnerCourseEnrollmentsCompanion.insert(
                id: _string(row, 'id'),
                learnerId: _string(row, 'learnerId'),
                courseId: _string(row, 'courseId'),
                version: _int(row, 'version'),
                enrolledAt: _date(row, 'enrolledAt'),
                updatedAt: _date(row, 'updatedAt'),
              ),
            );
      }

      for (final row in snapshot.reviewCards) {
        await _db.into(_db.reviewCards).insert(
              ReviewCardsCompanion.insert(
                id: _string(row, 'id'),
                learnerId: _string(row, 'learnerId'),
                itemId: _string(row, 'itemId'),
                cardJson: _string(row, 'cardJson'),
                dueAt: _date(row, 'dueAt'),
                lastReviewedAt: Value(_nullableDate(row, 'lastReviewedAt')),
                updatedAt: _date(row, 'updatedAt'),
              ),
            );
      }

      for (final row in snapshot.reviewEvents) {
        await _db.into(_db.reviewEvents).insert(
              ReviewEventsCompanion.insert(
                id: _string(row, 'id'),
                learnerId: _string(row, 'learnerId'),
                itemId: _string(row, 'itemId'),
                rating: _string(row, 'rating'),
                reviewedAt: _date(row, 'reviewedAt'),
                cardJson: _string(row, 'cardJson'),
              ),
            );
      }
    });
  }
}

Map<String, Object?> _profileToJson(LearnerProfile row) => {
      'id': row.id,
      'displayName': row.displayName,
      'birthYear': row.birthYear,
      'nativeLanguage': row.nativeLanguage,
      'targetLanguage': row.targetLanguage,
      'preferredAccent': row.preferredAccent,
      'isActive': row.isActive,
      'createdAt': row.createdAt.toUtc().toIso8601String(),
      'updatedAt': row.updatedAt.toUtc().toIso8601String(),
    };

Map<String, Object?> _reviewCardToJson(ReviewCard row) => {
      'id': row.id,
      'learnerId': row.learnerId,
      'itemId': row.itemId,
      'cardJson': row.cardJson,
      'dueAt': row.dueAt.toUtc().toIso8601String(),
      'lastReviewedAt': row.lastReviewedAt?.toUtc().toIso8601String(),
      'updatedAt': row.updatedAt.toUtc().toIso8601String(),
    };

Map<String, Object?> _reviewEventToJson(ReviewEvent row) => {
      'id': row.id,
      'learnerId': row.learnerId,
      'itemId': row.itemId,
      'rating': row.rating,
      'reviewedAt': row.reviewedAt.toUtc().toIso8601String(),
      'cardJson': row.cardJson,
    };

Map<String, Object?> _sourceToJson(ImportJob row) => {
      'id': row.id,
      'learnerId': row.learnerId,
      'sourceType': row.sourceType,
      'displayName': row.displayName,
      'sourceJson': row.sourceJson,
      'status': row.status,
      'errorMessage': row.errorMessage,
      'createdAt': row.createdAt.toUtc().toIso8601String(),
      'updatedAt': row.updatedAt.toUtc().toIso8601String(),
    };

Map<String, Object?> _courseToJson(
  InstalledCourse row,
  Set<String> knownSourceIds,
) =>
    {
      'id': row.id,
      'title': row.title,
      'currentVersion': row.currentVersion,
      'sourceJobId': _knownSourceId(row.sourceJobId, knownSourceIds),
      'installedAt': row.installedAt.toUtc().toIso8601String(),
      'updatedAt': row.updatedAt.toUtc().toIso8601String(),
    };

Map<String, Object?> _courseVersionToJson(
  InstalledCourseVersion row,
  Set<String> knownSourceIds,
) =>
    {
      'id': row.id,
      'courseId': row.courseId,
      'version': row.version,
      'assetId': row.assetId,
      'sourceJobId': _knownSourceId(row.sourceJobId, knownSourceIds),
      'itemCount': row.itemCount,
      'lessonCount': row.lessonCount,
      'createdAt': row.createdAt.toUtc().toIso8601String(),
    };

Map<String, Object?> _enrollmentToJson(LearnerCourseEnrollment row) => {
      'id': row.id,
      'learnerId': row.learnerId,
      'courseId': row.courseId,
      'version': row.version,
      'enrolledAt': row.enrolledAt.toUtc().toIso8601String(),
      'updatedAt': row.updatedAt.toUtc().toIso8601String(),
    };

String? _knownSourceId(String? sourceJobId, Set<String> knownSourceIds) =>
    sourceJobId != null && knownSourceIds.contains(sourceJobId)
        ? sourceJobId
        : null;

List<Map<String, Object?>> _mapList(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! List) {
    throw FormatException('$key must be a list');
  }
  return value.map((entry) {
    if (entry is! Map) {
      throw FormatException('$key entries must be objects');
    }
    return Map<String, Object?>.from(entry);
  }).toList(growable: false);
}

Set<String> _uniqueIds(List<Map<String, Object?>> rows, String label) {
  final ids = <String>{};
  for (final row in rows) {
    final id = _string(row, 'id');
    if (id.trim().isEmpty) {
      throw FormatException('$label id cannot be empty');
    }
    if (!ids.add(id)) {
      throw FormatException('Duplicate $label id: $id');
    }
  }
  return ids;
}

void _requireKnownSource(Map<String, Object?> row, Set<String> sourceIds) {
  final sourceJobId = _nullableString(row, 'sourceJobId');
  if (sourceJobId != null && !sourceIds.contains(sourceJobId)) {
    throw FormatException('Installed course references unknown source: $sourceJobId');
  }
}

ReviewState _reviewState(String encoded) {
  final decoded = jsonDecode(encoded);
  if (decoded is! Map) {
    throw const FormatException('Review state must be a JSON object');
  }
  return ReviewState.fromMap(Map<String, dynamic>.from(decoded));
}

String _string(Map<String, Object?> row, String key) {
  final value = row[key];
  if (value is! String) throw FormatException('$key must be a string');
  return value;
}

String? _nullableString(Map<String, Object?> row, String key) {
  final value = row[key];
  if (value == null) return null;
  if (value is! String) throw FormatException('$key must be a string or null');
  return value;
}

int _int(Map<String, Object?> row, String key) {
  final value = row[key];
  if (value is int) return value;
  if (value is num && value == value.toInt()) return value.toInt();
  throw FormatException('$key must be an integer');
}

int? _nullableInt(Map<String, Object?> row, String key) {
  final value = row[key];
  if (value == null) return null;
  if (value is int) return value;
  if (value is num && value == value.toInt()) return value.toInt();
  throw FormatException('$key must be an integer or null');
}

bool _bool(Map<String, Object?> row, String key) {
  final value = row[key];
  if (value is! bool) throw FormatException('$key must be a boolean');
  return value;
}

DateTime _date(Map<String, Object?> row, String key) {
  final value = _string(row, key);
  try {
    return DateTime.parse(value).toUtc();
  } on FormatException {
    throw FormatException('$key is not a valid timestamp');
  }
}

DateTime? _nullableDate(Map<String, Object?> row, String key) {
  final value = _nullableString(row, key);
  if (value == null) return null;
  try {
    return DateTime.parse(value).toUtc();
  } on FormatException {
    throw FormatException('$key is not a valid timestamp');
  }
}
