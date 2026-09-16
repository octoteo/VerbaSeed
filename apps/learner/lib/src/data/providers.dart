import 'package:content_source/content_source.dart';
import 'package:content_store/content_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_store/local_store.dart';
import 'package:ocr_google_mlkit/ocr_google_mlkit.dart';
import 'package:pdf_extractor_pdfrx/pdf_extractor_pdfrx.dart';

import 'course_draft_review_service.dart';
import 'course_installation_service.dart';
import 'document_import_coordinator.dart';

final databaseProvider = Provider<VerbaSeedDatabase>((ref) {
  final database = openVerbaSeedDatabase();
  ref.onDispose(() {
    database.close();
  });
  return database;
});

final contentAssetStoreProvider = Provider<ContentAssetStore>((ref) {
  final store = openContentAssetStore();
  ref.onDispose(() {
    store.close();
  });
  return store;
});

final githubCourseClientProvider = Provider<GitHubCourseClient>((ref) {
  final client = GitHubCourseClient();
  ref.onDispose(client.close);
  return client;
});

final pdfExtractorProvider = Provider<PdfrxPdfExtractor>(
  (ref) => const PdfrxPdfExtractor(),
);

final pdfPageRasterizerProvider = Provider<PdfrxPdfPageRasterizer>(
  (ref) => const PdfrxPdfPageRasterizer(),
);

final imageOcrExtractorProvider = Provider<GoogleMlKitTextExtractor>(
  (ref) => const GoogleMlKitTextExtractor(),
);

final learnerRepositoryProvider = Provider<LearnerRepository>(
  (ref) => LearnerRepository(ref.watch(databaseProvider)),
);

final reviewRepositoryProvider = Provider<ReviewRepository>(
  (ref) => ReviewRepository(ref.watch(databaseProvider)),
);

final importRepositoryProvider = Provider<ImportRepository>(
  (ref) => ImportRepository(ref.watch(databaseProvider)),
);

final courseInstallationRepositoryProvider = Provider<CourseInstallationRepository>(
  (ref) => CourseInstallationRepository(ref.watch(databaseProvider)),
);

final documentImportCoordinatorProvider = Provider<DocumentImportCoordinator>(
  (ref) => DocumentImportCoordinator(
    repository: ref.watch(importRepositoryProvider),
    assetStore: ref.watch(contentAssetStoreProvider),
    pdfExtractor: ref.watch(pdfExtractorProvider),
    pdfPageRasterizer: ref.watch(pdfPageRasterizerProvider),
    imageExtractor: ref.watch(imageOcrExtractorProvider),
    imageExtractionAvailable: GoogleMlKitTextExtractor.isSupportedPlatform,
  ),
);

final courseDraftReviewServiceProvider = Provider<CourseDraftReviewService>(
  (ref) => CourseDraftReviewService(
    database: ref.watch(databaseProvider),
    repository: ref.watch(importRepositoryProvider),
    assetStore: ref.watch(contentAssetStoreProvider),
  ),
);

final courseInstallationServiceProvider = Provider<CourseInstallationService>(
  (ref) => CourseInstallationService(
    reviewService: ref.watch(courseDraftReviewServiceProvider),
    installationRepository: ref.watch(courseInstallationRepositoryProvider),
    reviewRepository: ref.watch(reviewRepositoryProvider),
    assetStore: ref.watch(contentAssetStoreProvider),
  ),
);

final learnerProfilesProvider = StreamProvider<List<LearnerProfile>>(
  (ref) => ref.watch(learnerRepositoryProvider).watchProfiles(),
);

final activeLearnerProvider = StreamProvider<LearnerProfile?>(
  (ref) => ref.watch(learnerRepositoryProvider).watchActiveProfile(),
);

final importJobsProvider = StreamProvider<List<ImportJob>>(
  (ref) => ref.watch(importRepositoryProvider).watchJobs(),
);

final installedCoursesProvider = StreamProvider<List<InstalledCourse>>(
  (ref) => ref.watch(courseInstallationRepositoryProvider).watchInstalledCourses(),
);

final learnerCourseEnrollmentsProvider =
    StreamProvider.family<List<LearnerCourseEnrollment>, String>(
  (ref, learnerId) => ref
      .watch(courseInstallationRepositoryProvider)
      .watchEnrollments(learnerId),
);
