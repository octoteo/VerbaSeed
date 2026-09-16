import 'package:content_source/content_source.dart';
import 'package:content_store/content_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_store/local_store.dart';

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

final learnerRepositoryProvider = Provider<LearnerRepository>(
  (ref) => LearnerRepository(ref.watch(databaseProvider)),
);

final reviewRepositoryProvider = Provider<ReviewRepository>(
  (ref) => ReviewRepository(ref.watch(databaseProvider)),
);

final importRepositoryProvider = Provider<ImportRepository>(
  (ref) => ImportRepository(ref.watch(databaseProvider)),
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
