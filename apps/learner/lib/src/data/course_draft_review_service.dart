import 'dart:convert';
import 'dart:typed_data';

import 'package:content_source/content_source.dart';
import 'package:content_store/content_store.dart';
import 'package:course_schema/course_schema.dart';
import 'package:local_store/local_store.dart';

import 'document_import_coordinator.dart';

final class CourseDraftReview {
  const CourseDraftReview({
    required this.job,
    required this.source,
    required this.asset,
    required this.course,
    required this.status,
    required this.requiresReview,
    this.warnings = const [],
  });

  final ImportJob job;
  final ContentSource source;
  final ContentAsset asset;
  final Course course;
  final String status;
  final bool requiresReview;
  final List<String> warnings;

  int get itemCount => course.units
      .expand((unit) => unit.lessons)
      .expand((lesson) => lesson.items)
      .length;
}

final class CourseDraftReviewService {
  factory CourseDraftReviewService({
    required VerbaSeedDatabase database,
    required ImportRepository repository,
    required ContentAssetStore assetStore,
    DateTime Function()? clock,
  }) =>
      CourseDraftReviewService._(
        database,
        repository,
        assetStore,
        clock,
      );

  const CourseDraftReviewService._(
    this._database,
    this._repository,
    this._assetStore,
    this._clock,
  );

  final VerbaSeedDatabase _database;
  final ImportRepository _repository;
  final ContentAssetStore _assetStore;
  final DateTime Function()? _clock;

  Future<CourseDraftReview> load(String jobId) async {
    final job = await (_database.select(_database.importJobs)
          ..where((table) => table.id.equals(jobId)))
        .getSingleOrNull();
    if (job == null) {
      throw StateError('导入任务不存在: $jobId');
    }

    final source = _repository.decodeSource(job);
    final rawAsset =
        source.metadata[DocumentImportCoordinator.courseDraftAssetMetadataKey];
    if (rawAsset is! Map) {
      throw StateError('该导入任务尚未生成课程草稿');
    }
    final asset = ContentAsset.fromJson(
      Map<String, Object?>.from(rawAsset),
    );
    final bytes = await _assetStore.read(asset.id);
    if (bytes == null) {
      throw StateError('课程草稿文件已不存在，请重新解析原始资料');
    }

    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) {
      throw const FormatException('课程草稿不是有效的 JSON 对象');
    }
    final course = Course.fromJson(Map<String, Object?>.from(decoded));
    final warnings = switch (source.metadata['courseDraftWarnings']) {
      final List values => values.map((value) => '$value').toList(growable: false),
      _ => const <String>[],
    };

    return CourseDraftReview(
      job: job,
      source: source,
      asset: asset,
      course: course,
      status: (source.metadata['courseDraftStatus'] as String?) ?? 'ready',
      requiresReview:
          source.metadata['courseDraftNeedsReview'] == true ||
          source.metadata['requiresReview'] == true,
      warnings: warnings,
    );
  }

  Future<CourseDraftReview> save({
    required String jobId,
    required Course course,
    bool accept = false,
  }) async {
    _validateCourse(course);
    final current = await load(jobId);
    final bytes = Uint8List.fromList(
      utf8.encode(jsonEncode(course.toJson())),
    );
    final revision = _revision(current.source.metadata) + 1;
    final asset = await _assetStore.put(
      bytes: bytes,
      fileName: '${current.asset.fileName}.review-$revision.json',
      mimeType: 'application/vnd.verbaseed.course+json',
    );
    final itemCount = course.units
        .expand((unit) => unit.lessons)
        .expand((lesson) => lesson.items)
        .length;
    final lessonCount =
        course.units.expand((unit) => unit.lessons).length;
    final reviewedAt = _now();
    final metadata = <String, Object?>{
      ...current.source.metadata,
      DocumentImportCoordinator.courseDraftAssetMetadataKey: asset.toJson(),
      'courseDraftStatus': accept ? 'accepted' : 'ready',
      'courseDraftRevision': revision,
      'courseDraftReviewedAt': reviewedAt.toIso8601String(),
      'courseDraftNeedsReview': false,
      'requiresReview': false,
      'compiledItemCount': itemCount,
      'compiledLessonCount': lessonCount,
    };
    final source = current.source.copyWith(metadata: metadata);
    await _repository.replaceSource(
      jobId,
      source,
      state: ImportJobState.ready,
    );
    return load(jobId);
  }

  static int _revision(Map<String, Object?> metadata) =>
      switch (metadata['courseDraftRevision']) {
        final int value => value,
        final num value => value.toInt(),
        _ => 0,
      };

  static void _validateCourse(Course course) {
    if (course.title.trim().isEmpty) {
      throw const FormatException('课程名称不能为空');
    }
    final items = course.units
        .expand((unit) => unit.lessons)
        .expand((lesson) => lesson.items)
        .toList(growable: false);
    if (items.isEmpty) {
      throw const FormatException('课程至少需要保留一个学习项');
    }
    final ids = <String>{};
    for (final item in items) {
      if (item.text.trim().isEmpty) {
        throw const FormatException('英语学习内容不能为空');
      }
      if (!ids.add(item.id)) {
        throw FormatException('课程中存在重复学习项 ID：${item.id}');
      }
    }
  }

  DateTime _now() => (_clock?.call() ?? DateTime.now()).toUtc();
}
