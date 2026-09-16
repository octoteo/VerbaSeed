import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_store/local_store.dart';

final databaseProvider = Provider<VerbaSeedDatabase>((ref) {
  final database = openVerbaSeedDatabase();
  ref.onDispose(() {
    database.close();
  });
  return database;
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
