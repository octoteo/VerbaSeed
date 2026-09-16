import 'package:content_source/content_source.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learning_engine/learning_engine.dart';
import 'package:local_store/local_store.dart';

void main() {
  late VerbaSeedDatabase database;

  setUp(() {
    database = VerbaSeedDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  test('first learner becomes active and switching is atomic', () async {
    final learners = LearnerRepository(database);
    final first = await learners.createProfile(displayName: 'Mia');
    final second = await learners.createProfile(displayName: 'Leo');

    await learners.setActive(second);
    final rows = await database.select(database.learnerProfiles).get();
    expect(rows.where((row) => row.isActive).single.id, second);
    expect(rows.any((row) => row.id == first), isTrue);
  });

  test('review state survives database serialization', () async {
    final learners = LearnerRepository(database);
    final learnerId = await learners.createProfile(displayName: 'Mia');
    final reviews = ReviewRepository(database);

    final initial = await reviews.loadOrCreate(
      learnerId: learnerId,
      itemId: 'hello',
    );
    await reviews.reviewItem(
      learnerId: learnerId,
      itemId: 'hello',
      rating: RecallRating.good,
    );
    final restored = await reviews.loadOrCreate(
      learnerId: learnerId,
      itemId: 'hello',
    );

    expect(restored.card.cardId, initial.card.cardId);
    expect(restored.card.lastReview, isNotNull);
  });

  test('import queue persists typed content sources', () async {
    final imports = ImportRepository(database);
    await imports.enqueue(
      GitHubCourseSource.parse('https://github.com/octoteo/VerbaSeed')
          .toContentSource(),
    );

    final jobs = await database.select(database.importJobs).get();
    expect(jobs, hasLength(1));
    expect(imports.decodeSource(jobs.single).type, ContentSourceType.github);
  });
}
