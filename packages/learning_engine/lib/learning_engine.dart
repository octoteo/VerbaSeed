library learning_engine;

import 'package:fsrs/fsrs.dart' as fsrs;

enum RecallRating { again, hard, good, easy }

final class ReviewState {
  const ReviewState({required this.card, required this.due});

  final fsrs.Card card;
  final DateTime due;
}

final class ReviewResult {
  const ReviewResult({required this.state, required this.reviewedAt});

  final ReviewState state;
  final DateTime reviewedAt;
}

abstract interface class ReviewScheduler {
  ReviewState createCard({required int id});
  ReviewResult review(ReviewState state, RecallRating rating);
  double retrievability(ReviewState state);
}

final class FsrsReviewScheduler implements ReviewScheduler {
  FsrsReviewScheduler({fsrs.Scheduler? scheduler})
      : _scheduler = scheduler ?? fsrs.Scheduler();

  final fsrs.Scheduler _scheduler;

  @override
  ReviewState createCard({required int id}) {
    final card = fsrs.Card(cardId: id);
    return ReviewState(card: card, due: card.due);
  }

  @override
  ReviewResult review(ReviewState state, RecallRating rating) {
    final reviewedAt = DateTime.now().toUtc();
    final result = _scheduler.reviewCard(state.card, _toFsrsRating(rating));
    return ReviewResult(
      state: ReviewState(card: result.card, due: result.card.due),
      reviewedAt: reviewedAt,
    );
  }

  @override
  double retrievability(ReviewState state) =>
      _scheduler.getCardRetrievability(state.card);

  fsrs.Rating _toFsrsRating(RecallRating rating) => switch (rating) {
        RecallRating.again => fsrs.Rating.again,
        RecallRating.hard => fsrs.Rating.hard,
        RecallRating.good => fsrs.Rating.good,
        RecallRating.easy => fsrs.Rating.easy,
      };
}
