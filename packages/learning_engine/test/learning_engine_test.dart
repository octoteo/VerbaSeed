import 'package:learning_engine/learning_engine.dart';
import 'package:test/test.dart';

void main() {
  test('FSRS schedules a reviewed card in UTC', () {
    final scheduler = FsrsReviewScheduler();
    final initial = scheduler.createCard(id: 1);
    final result = scheduler.review(initial, RecallRating.good);

    expect(result.state.due.isUtc, isTrue);
    expect(result.reviewedAt.isUtc, isTrue);
    expect(result.state.due.isAfter(result.reviewedAt), isTrue);
  });
}
