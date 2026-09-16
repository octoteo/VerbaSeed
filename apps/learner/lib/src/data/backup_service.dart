import 'dart:convert';
import 'dart:typed_data';

import 'package:content_store/content_store.dart';
import 'package:course_schema/course_schema.dart';
import 'package:local_store/local_store.dart';

const String verbaSeedBackupFormat = 'verbaseed-portable-backup';
const int verbaSeedBackupFormatVersion = 1;

final class VerbaSeedBackupPreview {
  const VerbaSeedBackupPreview({
    required this.exportedAt,
    required this.learnerCount,
    required this.reviewCardCount,
    required this.reviewEventCount,
    required this.courseCount,
    required this.courseVersionCount,
    required this.enrollmentCount,
    required this.courseSourceCount,
  });

  final DateTime exportedAt;
  final int learnerCount;
  final int reviewCardCount;
  final int reviewEventCount;
  final int courseCount;
  final int courseVersionCount;
  final int enrollmentCount;
  final int courseSourceCount;
}

final class VerbaSeedBackupRestoreResult {
  const VerbaSeedBackupRestoreResult({
    required this.preview,
    required this.restoredCourseAssetCount,
  });

  final VerbaSeedBackupPreview preview;
  final int restoredCourseAssetCount;
}

final class VerbaSeedBackupService {
  const VerbaSeedBackupService({
    required BackupRepository backupRepository,
    required ContentAssetStore assetStore,
  }) : this._(backupRepository, assetStore);

  const VerbaSeedBackupService._(
    this._backupRepository,
    this._assetStore,
  );

  final BackupRepository _backupRepository;
  final ContentAssetStore _assetStore;

  Future<Uint8List> exportBackup() async {
    final snapshot = await _backupRepository.exportSnapshot();
    final manifests = <Map<String, Object?>>[];

    for (final version in snapshot.installedCourseVersions) {
      final courseId = _string(version, 'courseId');
      final versionNumber = _int(version, 'version');
      final assetId = _string(version, 'assetId');
      final bytes = await _assetStore.read(assetId);
      if (bytes == null) {
        throw StateError(
          '课程历史资产缺失，无法生成完整备份: $courseId@$versionNumber',
        );
      }
      final metadata = await _assetStore.metadata(assetId);
      final manifestJson = utf8.decode(bytes);
      final course = _parseCourse(manifestJson);
      _validateCourseVersion(
        course: course,
        courseId: courseId,
        versionNumber: versionNumber,
        expectedItemCount: _int(version, 'itemCount'),
        expectedLessonCount: _int(version, 'lessonCount'),
      );
      final computed = ContentAsset.fromBytes(
        bytes: bytes,
        fileName: metadata?.fileName ?? '$courseId-v$versionNumber.course.json',
        mimeType:
            metadata?.mimeType ?? 'application/vnd.verbaseed.course+json',
      );
      if (computed.id != assetId) {
        throw StateError(
          '课程历史资产完整性校验失败: $courseId@$versionNumber',
        );
      }
      manifests.add({
        'courseId': courseId,
        'version': versionNumber,
        'assetId': assetId,
        'fileName': metadata?.fileName ?? '$courseId-v$versionNumber.course.json',
        'mimeType':
            metadata?.mimeType ?? 'application/vnd.verbaseed.course+json',
        'manifestJson': manifestJson,
      });
    }

    final bundle = <String, Object?>{
      'format': verbaSeedBackupFormat,
      'formatVersion': verbaSeedBackupFormatVersion,
      'exportedAt': snapshot.exportedAt.toUtc().toIso8601String(),
      'localState': snapshot.toJson(),
      'courseManifests': manifests,
    };
    return Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(bundle)),
    );
  }

  VerbaSeedBackupPreview inspectBackup(Uint8List bytes) => _parse(bytes).preview;

  Future<VerbaSeedBackupRestoreResult> restoreBackup(Uint8List bytes) async {
    final parsed = _parse(bytes);

    for (final manifest in parsed.manifests) {
      final asset = await _assetStore.put(
        bytes: manifest.bytes,
        fileName: manifest.fileName,
        mimeType: manifest.mimeType,
      );
      if (asset.id != manifest.assetId) {
        throw StateError(
          '恢复后的课程资产标识不一致: ${manifest.courseId}@${manifest.version}',
        );
      }
    }

    await _backupRepository.replaceWithSnapshot(parsed.snapshot);
    return VerbaSeedBackupRestoreResult(
      preview: parsed.preview,
      restoredCourseAssetCount: parsed.manifests.length,
    );
  }

  _ParsedBackup _parse(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw const FormatException('备份文件为空');
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) {
      throw const FormatException('备份文件必须是 JSON 对象');
    }
    final root = Map<String, Object?>.from(decoded);
    if (root['format'] != verbaSeedBackupFormat) {
      throw const FormatException('不是 VerbaSeed 便携备份文件');
    }
    final formatVersion = root['formatVersion'];
    if (formatVersion is! num ||
        formatVersion.toInt() != formatVersion ||
        formatVersion.toInt() != verbaSeedBackupFormatVersion) {
      throw FormatException('不支持的备份格式版本: $formatVersion');
    }
    final localStateRaw = root['localState'];
    if (localStateRaw is! Map) {
      throw const FormatException('备份缺少 localState');
    }
    final snapshot = LocalBackupSnapshot.fromJson(
      Map<String, Object?>.from(localStateRaw),
    );
    _backupRepository.validateSnapshot(snapshot);

    final exportedAtRaw = root['exportedAt'];
    if (exportedAtRaw is! String) {
      throw const FormatException('备份缺少 exportedAt');
    }
    final exportedAt = DateTime.parse(exportedAtRaw).toUtc();
    if (exportedAt != snapshot.exportedAt) {
      throw const FormatException('备份时间与 localState 不一致');
    }

    final versionsByKey = <String, Map<String, Object?>>{
      for (final row in snapshot.installedCourseVersions)
        '${_string(row, 'courseId')}@${_int(row, 'version')}': row,
    };
    final manifestsRaw = root['courseManifests'];
    if (manifestsRaw is! List) {
      throw const FormatException('备份缺少 courseManifests');
    }
    final manifests = <_CourseManifestBackup>[];
    final seenKeys = <String>{};
    for (final raw in manifestsRaw) {
      if (raw is! Map) {
        throw const FormatException('courseManifests 条目必须是对象');
      }
      final entry = Map<String, Object?>.from(raw);
      final courseId = _string(entry, 'courseId');
      final version = _int(entry, 'version');
      final assetId = _string(entry, 'assetId');
      final fileName = _string(entry, 'fileName');
      final mimeType = _string(entry, 'mimeType');
      final manifestJson = _string(entry, 'manifestJson');
      final key = '$courseId@$version';
      if (!seenKeys.add(key)) {
        throw FormatException('备份存在重复课程 manifest: $key');
      }
      final installedVersion = versionsByKey[key];
      if (installedVersion == null) {
        throw FormatException('课程 manifest 没有对应的安装历史: $key');
      }
      if (_string(installedVersion, 'assetId') != assetId) {
        throw FormatException('课程 manifest 与安装历史 assetId 不一致: $key');
      }
      final manifestBytes = Uint8List.fromList(utf8.encode(manifestJson));
      final computed = ContentAsset.fromBytes(
        bytes: manifestBytes,
        fileName: fileName,
        mimeType: mimeType,
      );
      if (computed.id != assetId) {
        throw FormatException('课程 manifest SHA-256 校验失败: $key');
      }
      final course = _parseCourse(manifestJson);
      _validateCourseVersion(
        course: course,
        courseId: courseId,
        versionNumber: version,
        expectedItemCount: _int(installedVersion, 'itemCount'),
        expectedLessonCount: _int(installedVersion, 'lessonCount'),
      );
      manifests.add(
        _CourseManifestBackup(
          courseId: courseId,
          version: version,
          assetId: assetId,
          fileName: fileName,
          mimeType: mimeType,
          bytes: manifestBytes,
        ),
      );
    }
    final missingManifestKeys = versionsByKey.keys.toSet().difference(seenKeys);
    if (missingManifestKeys.isNotEmpty) {
      throw FormatException(
        '备份缺少课程历史 manifest: ${missingManifestKeys.join(', ')}',
      );
    }

    final preview = VerbaSeedBackupPreview(
      exportedAt: exportedAt,
      learnerCount: snapshot.learnerProfiles.length,
      reviewCardCount: snapshot.reviewCards.length,
      reviewEventCount: snapshot.reviewEvents.length,
      courseCount: snapshot.installedCourses.length,
      courseVersionCount: snapshot.installedCourseVersions.length,
      enrollmentCount: snapshot.learnerCourseEnrollments.length,
      courseSourceCount: snapshot.courseSources.length,
    );
    return _ParsedBackup(
      snapshot: snapshot,
      manifests: manifests,
      preview: preview,
    );
  }
}

final class _ParsedBackup {
  const _ParsedBackup({
    required this.snapshot,
    required this.manifests,
    required this.preview,
  });

  final LocalBackupSnapshot snapshot;
  final List<_CourseManifestBackup> manifests;
  final VerbaSeedBackupPreview preview;
}

final class _CourseManifestBackup {
  const _CourseManifestBackup({
    required this.courseId,
    required this.version,
    required this.assetId,
    required this.fileName,
    required this.mimeType,
    required this.bytes,
  });

  final String courseId;
  final int version;
  final String assetId;
  final String fileName;
  final String mimeType;
  final Uint8List bytes;
}

Course _parseCourse(String manifestJson) {
  final decoded = jsonDecode(manifestJson);
  if (decoded is! Map) {
    throw const FormatException('课程 manifest 必须是 JSON 对象');
  }
  return Course.fromJson(Map<String, Object?>.from(decoded));
}

void _validateCourseVersion({
  required Course course,
  required String courseId,
  required int versionNumber,
  required int expectedItemCount,
  required int expectedLessonCount,
}) {
  if (course.id != courseId) {
    throw FormatException(
      '课程 manifest 标识不一致: ${course.id} != $courseId@$versionNumber',
    );
  }
  if (course.title.trim().isEmpty) {
    throw FormatException('课程 manifest 名称为空: $courseId@$versionNumber');
  }
  final lessons = course.units.expand((unit) => unit.lessons).toList(growable: false);
  final items = lessons.expand((lesson) => lesson.items).toList(growable: false);
  if (lessons.length != expectedLessonCount || items.length != expectedItemCount) {
    throw FormatException(
      '课程 manifest 计数与安装历史不一致: $courseId@$versionNumber',
    );
  }
  if (items.isEmpty || lessons.isEmpty) {
    throw FormatException('课程 manifest 为空: $courseId@$versionNumber');
  }
  final itemIds = <String>{};
  for (final item in items) {
    if (item.id.trim().isEmpty || item.text.trim().isEmpty) {
      throw FormatException('课程 manifest 包含空学习项: $courseId@$versionNumber');
    }
    if (!itemIds.add(item.id)) {
      throw FormatException(
        '课程 manifest 包含重复学习项 ID: ${item.id}',
      );
    }
  }
}

String _string(Map<String, Object?> row, String key) {
  final value = row[key];
  if (value is! String) throw FormatException('$key must be a string');
  return value;
}

int _int(Map<String, Object?> row, String key) {
  final value = row[key];
  if (value is int) return value;
  if (value is num && value == value.toInt()) return value.toInt();
  throw FormatException('$key must be an integer');
}
