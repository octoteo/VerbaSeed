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

final class CourseInstallationService {
  const CourseInstallationService({
    required CourseDraftReviewService reviewService,
    required CourseInstallationRepository installationRepository,
    required ReviewRepository reviewRepository,
  })  : _reviewService = reviewService,
        _installationRepository = installationRepository,
        _reviewRepository = reviewRepository;

  final CourseDraftReviewService _reviewService;
  final CourseInstallationRepository _installationRepository;
  final ReviewRepository _reviewRepository;

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
    await _installationRepository.enrollLearner(
      learnerId: learnerId,
      courseId: installation.courseId,
      version: installation.version,
    );

    for (final item in items) {
      await _reviewRepository.loadOrCreate(
        learnerId: learnerId,
        itemId: item.id,
      );
    }

    return CourseInstallationSummary(
      courseId: installation.courseId,
      version: installation.version,
      itemCount: items.length,
      seededReviewCardCount: items.length,
      reusedVersion: installation.reused,
    );
  }
}
