import 'dart:convert';

import 'package:content_store/content_store.dart';
import 'package:course_schema/course_schema.dart';
import 'package:local_store/local_store.dart';

import 'course_draft_review_service.dart';

final class CourseInstallationSummary {
  const CourseInstallationSummary({
    required this.courseId,
    required this.version,
    required this.itemCount,
    required this.seededReviewCardCount,
    required this.reusedVersion,
  });

  final String courseId;
  final int version;
  final int itemCount;
  final int seededReviewCardCount;
  final bool reusedVersion;
}

final class CourseEnrollmentSummary {
  const CourseEnrollmentSummary({
    required this.courseId,
    required this.version,
    required this.itemCount,
    required this.seededReviewCardCount,
  });

  final String courseId;
  final int version;
  final int itemCount;
  final int seededReviewCardCount;
}

final class CourseInstallationService {
  factory CourseInstallationService({
    required CourseDraftReviewService reviewService,
    required CourseInstallationRepository installationRepository,
    required ReviewRepository reviewRepository,
    required ContentAssetStore assetStore,
  }) =>
      CourseInstallationService._(
        reviewService,
        installationRepository,
        reviewRepository,
        assetStore,
      );

  const CourseInstallationService._(
    this._reviewService,
    this._installationRepository,
    this._reviewRepository,
    this._assetStore,
  );

  final CourseDraftReviewService _reviewService;
  final CourseInstallationRepository _installationRepository;
  final ReviewRepository _reviewRepository;
  final ContentAssetStore _assetStore;

  Future<CourseInstallationSummary> installAcceptedDraft({
    required String jobId,
    required String learnerId,
  }) async {
    final review = await _reviewService.load(jobId);
    if (review.status != 'accepted') {
      throw StateError('课程草稿需要先人工接受，再安装到课程库');
    }

    final course = review.course;
    final lessons = course.units.expand((unit) => unit.lessons).toList(growable: false);
    final items = lessons.expand((lesson) => lesson.items).toList(growable: false);
    if (items.isEmpty) {
      throw StateError('课程没有可安装的学习项');
    }

    final installation = await _installationRepository.installCourse(
      courseId: course.id,
      title: course.title,
      assetId: review.asset.id,
      sourceJobId: jobId,
      itemCount: items.length,
      lessonCount: lessons.length,
    );
    await _enrollCourse(
      learnerId: learnerId,
      course: course,
      version: installation.version,
    );

    return CourseInstallationSummary(
      courseId: installation.courseId,
      version: installation.version,
      itemCount: items.length,
      seededReviewCardCount: items.length,
      reusedVersion: installation.reused,
    );
  }

  Future<CourseEnrollmentSummary> enrollInstalledCourse({
    required String courseId,
    required String learnerId,
  }) async {
    final installedVersion =
        await _installationRepository.currentVersion(courseId);
    if (installedVersion == null) {
      throw StateError('本地课程不存在: $courseId');
    }

    final bytes = await _assetStore.read(installedVersion.assetId);
    if (bytes == null) {
      throw StateError('课程内容资产已不存在，请重新导入课程');
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) {
      throw const FormatException('已安装课程不是有效的 JSON 对象');
    }
    final course = Course.fromJson(Map<String, Object?>.from(decoded));
    if (course.id != courseId) {
      throw StateError('课程内容资产与安装记录不一致: ${course.id} != $courseId');
    }
    final itemCount = await _enrollCourse(
      learnerId: learnerId,
      course: course,
      version: installedVersion.version,
    );

    return CourseEnrollmentSummary(
      courseId: courseId,
      version: installedVersion.version,
      itemCount: itemCount,
      seededReviewCardCount: itemCount,
    );
  }

  Future<int> _enrollCourse({
    required String learnerId,
    required Course course,
    required int version,
  }) async {
    final items = course.units
        .expand((unit) => unit.lessons)
        .expand((lesson) => lesson.items)
        .toList(growable: false);
    if (items.isEmpty) {
      throw StateError('课程没有可加入学习计划的学习项');
    }

    await _installationRepository.enrollLearner(
      learnerId: learnerId,
      courseId: course.id,
      version: version,
    );
    for (final item in items) {
      await _reviewRepository.loadOrCreate(
        learnerId: learnerId,
        itemId: item.id,
      );
    }
    return items.length;
  }
}
