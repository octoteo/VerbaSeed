import 'dart:convert';
import 'dart:typed_data';

import 'package:content_source/content_source.dart';
import 'package:content_store/content_store.dart';
import 'package:course_schema/course_schema.dart';
import 'package:local_store/local_store.dart';

final class GitHubCourseTracking {
  const GitHubCourseTracking({
    required this.courseId,
    required this.installedVersion,
    required this.sourceJobId,
    required this.source,
    required this.commitSha,
  });

  final String courseId;
  final int installedVersion;
  final String sourceJobId;
  final GitHubCourseSource source;
  final String commitSha;

  String get key => '$courseId@$installedVersion:$sourceJobId:$commitSha';
}

final class GitHubCourseUpdatePreview {
  const GitHubCourseUpdatePreview({
    required this.tracking,
    required this.snapshot,
  });

  final GitHubCourseTracking tracking;
  final GitHubCourseSnapshot snapshot;

  int get itemCount => _itemCount(snapshot.course);
  int get lessonCount => _lessonCount(snapshot.course);
}

final class GitHubCourseSyncResult {
  const GitHubCourseSyncResult({
    required this.courseId,
    required this.version,
    required this.commitSha,
    required this.assetId,
    required this.reusedVersion,
  });

  final String courseId;
  final int version;
  final String commitSha;
  final String assetId;
  final bool reusedVersion;
}

final class GitHubCourseSyncService {
  const GitHubCourseSyncService({
    required GitHubCourseRemote remote,
    required ImportRepository importRepository,
    required CourseInstallationRepository installationRepository,
    required ContentAssetStore assetStore,
  }) : this._(
          remote,
          importRepository,
          installationRepository,
          assetStore,
        );

  const GitHubCourseSyncService._(
    this._remote,
    this._importRepository,
    this._installationRepository,
    this._assetStore,
  );

  final GitHubCourseRemote _remote;
  final ImportRepository _importRepository;
  final CourseInstallationRepository _installationRepository;
  final ContentAssetStore _assetStore;

  GitHubCourseSnapshot? importSnapshot(ImportJob job) {
    if (job.status != ImportJobState.ready.name ||
        job.sourceType != ContentSourceType.github.name) {
      return null;
    }
    try {
      final source = _importRepository.decodeSource(job);
      if (source.type != ContentSourceType.github ||
          source.metadata['githubSyncKind'] != null) {
        return null;
      }
      return GitHubCourseSnapshot.fromMetadata(source.metadata);
    } on Object {
      return null;
    }
  }

  GitHubCourseTracking? trackingForLocal({
    required InstalledCourse course,
    required ImportJob? sourceJob,
  }) {
    if (sourceJob == null ||
        sourceJob.sourceType != ContentSourceType.github.name) {
      return null;
    }
    final source = _importRepository.decodeSource(sourceJob);
    if (source.type != ContentSourceType.github) return null;
    final snapshot = GitHubCourseSnapshot.fromMetadata(source.metadata);
    if (snapshot.course.id != course.id) {
      throw StateError(
        'GitHub 来源课程与安装记录不一致: ${snapshot.course.id} != ${course.id}',
      );
    }
    return GitHubCourseTracking(
      courseId: course.id,
      installedVersion: course.currentVersion,
      sourceJobId: sourceJob.id,
      source: snapshot.source,
      commitSha: snapshot.commitSha,
    );
  }

  Future<GitHubCourseSyncResult> installImportedCourse(String jobId) async {
    final job = await _importRepository.getJob(jobId);
    if (job == null) {
      throw StateError('导入任务不存在: $jobId');
    }
    final snapshot = importSnapshot(job);
    if (snapshot == null) {
      throw StateError('该任务不是可安装的 GitHub 课程快照');
    }

    final originalSource = _importRepository.decodeSource(job);
    final asset = await _persistSnapshot(snapshot);
    final preparedSource = originalSource.copyWith(
      metadata: {
        ...originalSource.metadata,
        'githubSyncKind': 'installed',
        'githubCourseAsset': asset.toJson(),
      },
    );
    await _importRepository.replaceSource(
      job.id,
      preparedSource,
      state: ImportJobState.ready,
    );

    try {
      final result = await _installationRepository.installCourse(
        courseId: snapshot.course.id,
        title: snapshot.course.title,
        assetId: asset.id,
        sourceJobId: job.id,
        itemCount: _itemCount(snapshot.course),
        lessonCount: _lessonCount(snapshot.course),
      );
      return GitHubCourseSyncResult(
        courseId: result.courseId,
        version: result.version,
        commitSha: snapshot.commitSha,
        assetId: result.assetId,
        reusedVersion: result.reused,
      );
    } on Object catch (error) {
      try {
        await _importRepository.replaceSource(
          job.id,
          originalSource,
          state: ImportJobState.ready,
          errorMessage: '$error',
        );
      } on Object {
        // Preserve the installation failure as the primary error.
      }
      rethrow;
    }
  }

  Future<GitHubCourseUpdatePreview?> checkForUpdate(
    GitHubCourseTracking tracking,
  ) async {
    final snapshot = await _remote.fetchUpdate(
      tracking.source,
      currentCommitSha: tracking.commitSha,
    );
    if (snapshot == null) return null;
    if (snapshot.course.id != tracking.courseId) {
      throw StateError(
        '远端课程标识已改变: ${snapshot.course.id} != ${tracking.courseId}',
      );
    }
    if (_itemCount(snapshot.course) < 1 || _lessonCount(snapshot.course) < 1) {
      throw StateError('远端课程没有可安装的课节或学习项');
    }
    return GitHubCourseUpdatePreview(
      tracking: tracking,
      snapshot: snapshot,
    );
  }

  Future<GitHubCourseSyncResult> applyUpdate(
    GitHubCourseUpdatePreview preview,
  ) async {
    final current =
        await _installationRepository.installedCourse(preview.tracking.courseId);
    if (current == null ||
        current.currentVersion != preview.tracking.installedVersion ||
        current.sourceJobId != preview.tracking.sourceJobId) {
      throw StateError('课程默认版本或来源已发生变化，请重新检查 GitHub 更新');
    }

    final asset = await _persistSnapshot(preview.snapshot);
    final updateSource = preview.snapshot.source.toContentSource().copyWith(
      metadata: {
        ...preview.snapshot.toMetadata(),
        'githubSyncKind': 'update',
        'githubUpdateFromCommit': preview.tracking.commitSha,
        'githubCourseAsset': asset.toJson(),
      },
    );
    final jobId = await _importRepository.enqueue(updateSource);
    await _importRepository.updateStatus(jobId, ImportJobState.ready);

    try {
      final result = await _installationRepository.installCourse(
        courseId: preview.snapshot.course.id,
        title: preview.snapshot.course.title,
        assetId: asset.id,
        sourceJobId: jobId,
        itemCount: preview.itemCount,
        lessonCount: preview.lessonCount,
      );
      return GitHubCourseSyncResult(
        courseId: result.courseId,
        version: result.version,
        commitSha: preview.snapshot.commitSha,
        assetId: result.assetId,
        reusedVersion: result.reused,
      );
    } on Object catch (error) {
      await _importRepository.updateStatus(
        jobId,
        ImportJobState.failed,
        errorMessage: '$error',
      );
      rethrow;
    }
  }

  Future<ContentAsset> _persistSnapshot(GitHubCourseSnapshot snapshot) {
    final bytes = Uint8List.fromList(
      utf8.encode(jsonEncode(snapshot.course.toJson())),
    );
    final safeCourseId = snapshot.course.id.replaceAll(
      RegExp(r'[^A-Za-z0-9._-]+'),
      '-',
    );
    return _assetStore.put(
      bytes: bytes,
      fileName:
          '$safeCourseId-${snapshot.commitSha.substring(0, 12)}.course.json',
      mimeType: 'application/vnd.verbaseed.course+json',
    );
  }
}

int _itemCount(Course course) => course.units
    .expand((unit) => unit.lessons)
    .expand((lesson) => lesson.items)
    .length;

int _lessonCount(Course course) =>
    course.units.expand((unit) => unit.lessons).length;
