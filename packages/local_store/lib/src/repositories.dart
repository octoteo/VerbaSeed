import 'dart:convert';

import 'package:content_source/content_source.dart';
import 'package:drift/drift.dart';
import 'package:learning_engine/learning_engine.dart';
import 'package:uuid/uuid.dart';

import 'database.dart';

final class LearnerRepository {
  LearnerRepository(this._db, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final VerbaSeedDatabase _db;
  final Uuid _uuid;

  Stream<List<LearnerProfile>> watchProfiles() {
    final query = _db.select(_db.learnerProfiles)
      ..orderBy([(table) => OrderingTerm.asc(table.createdAt)]);
    return query.watch();
  }

  Stream<LearnerProfile?> watchActiveProfile() {
    final query = _db.select(_db.learnerProfiles)
      ..where((table) => table.isActive.equals(true))
      ..limit(1);
    return query.watchSingleOrNull();
  }

  Future<String> createProfile({
    required String displayName,
    int? birthYear,
    String nativeLanguage = 'zh-CN',
    String targetLanguage = 'en',
    String preferredAccent = 'curriculum',
    bool makeActive = false,
  }) async {
    final trimmedName = displayName.trim();
    if (trimmedName.isEmpty) {
      throw const FormatException('学习者名称不能为空');
    }

    final existing = await (_db.select(_db.learnerProfiles)..limit(1)).getSingleOrNull();
    final shouldActivate = makeActive || existing == null;
    final id = _uuid.v4();
    final now = DateTime.now().toUtc();

    await _db.transaction(() async {
      if (shouldActivate) {
        await _db.update(_db.learnerProfiles).write(
              const LearnerProfilesCompanion(isActive: Value(false)),
            );
      }
      await _db.into(_db.learnerProfiles).insert(
            LearnerProfilesCompanion.insert(
              id: id,
              displayName: trimmedName,
              birthYear: Value(birthYear),
              nativeLanguage: Value(nativeLanguage),
              targetLanguage: Value(targetLanguage),
              preferredAccent: Value(preferredAccent),
              isActive: Value(shouldActivate),
              createdAt: now,
              updatedAt: now,
            ),
          );
    });

    return id;
  }

  Future<void> setActive(String learnerId) async {
    final now = DateTime.now().toUtc();
    await _db.transaction(() async {
      await _db.update(_db.learnerProfiles).write(
            const LearnerProfilesCompanion(isActive: Value(false)),
          );
      final affected = await (_db.update(_db.learnerProfiles)
            ..where((table) => table.id.equals(learnerId)))
          .write(
        LearnerProfilesCompanion(
          isActive: const Value(true),
          updatedAt: Value(now),
        ),
      );
      if (affected != 1) {
        throw StateError('学习者档案不存在: $learnerId');
      }
    });
  }

  Future<void> deleteProfile(String learnerId) async {
    final target = await (_db.select(_db.learnerProfiles)
          ..where((table) => table.id.equals(learnerId)))
        .getSingleOrNull();
    if (target == null) return;

    await _db.transaction(() async {
      await (_db.delete(_db.learnerProfiles)
            ..where((table) => table.id.equals(learnerId)))
          .go();
      if (target.isActive) {
        final next = await (_db.select(_db.learnerProfiles)
              ..orderBy([(table) => OrderingTerm.asc(table.createdAt)])
              ..limit(1))
            .getSingleOrNull();
        if (next != null) {
          await (_db.update(_db.learnerProfiles)
                ..where((table) => table.id.equals(next.id)))
              .write(
            LearnerProfilesCompanion(
              isActive: const Value(true),
              updatedAt: Value(DateTime.now().toUtc()),
            ),
          );
        }
      }
    });
  }
}

final class ReviewRepository {
  ReviewRepository(
    this._db, {
    ReviewScheduler? scheduler,
    Uuid? uuid,
  })  : _scheduler = scheduler ?? FsrsReviewScheduler(),
        _uuid = uuid ?? const Uuid();

  final VerbaSeedDatabase _db;
  final ReviewScheduler _scheduler;
  final Uuid _uuid;

  Stream<int> watchDueCount(String learnerId) {
    final now = DateTime.now().toUtc();
    final query = _db.select(_db.reviewCards)
      ..where(
        (table) => table.learnerId.equals(learnerId) & table.dueAt.isSmallerOrEqualValue(now),
      );
    return query.watch().map((rows) => rows.length);
  }

  Future<ReviewState> loadOrCreate({
    required String learnerId,
    required String itemId,
  }) async {
    final row = await (_db.select(_db.reviewCards)
          ..where(
            (table) => table.learnerId.equals(learnerId) & table.itemId.equals(itemId),
          ))
        .getSingleOrNull();
    if (row != null) {
      return ReviewState.fromMap(
        Map<String, dynamic>.from(jsonDecode(row.cardJson) as Map),
      );
    }

    final state = _scheduler.createCard(id: _stableCardId('$learnerId:$itemId'));
    await _persistCard(learnerId: learnerId, itemId: itemId, state: state);
    return state;
  }

  Future<ReviewResult> reviewItem({
    required String learnerId,
    required String itemId,
    required RecallRating rating,
  }) async {
    final current = await loadOrCreate(learnerId: learnerId, itemId: itemId);
    final result = _scheduler.review(current, rating);
    final encoded = jsonEncode(result.state.toMap());

    await _db.transaction(() async {
      await _persistCard(
        learnerId: learnerId,
        itemId: itemId,
        state: result.state,
        lastReviewedAt: result.reviewedAt,
      );
      await _db.into(_db.reviewEvents).insert(
            ReviewEventsCompanion.insert(
              id: _uuid.v4(),
              learnerId: learnerId,
              itemId: itemId,
              rating: rating.name,
              reviewedAt: result.reviewedAt,
              cardJson: encoded,
            ),
          );
    });

    return result;
  }

  Future<void> _persistCard({
    required String learnerId,
    required String itemId,
    required ReviewState state,
    DateTime? lastReviewedAt,
  }) async {
    final now = DateTime.now().toUtc();
    await _db.into(_db.reviewCards).insertOnConflictUpdate(
          ReviewCardsCompanion.insert(
            id: '$learnerId:$itemId',
            learnerId: learnerId,
            itemId: itemId,
            cardJson: jsonEncode(state.toMap()),
            dueAt: state.due.toUtc(),
            lastReviewedAt: Value(lastReviewedAt?.toUtc()),
            updatedAt: now,
          ),
        );
  }
}

final class ImportRepository {
  ImportRepository(this._db, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final VerbaSeedDatabase _db;
  final Uuid _uuid;

  Stream<List<ImportJob>> watchJobs() {
    final query = _db.select(_db.importJobs)
      ..orderBy([(table) => OrderingTerm.desc(table.createdAt)]);
    return query.watch();
  }

  Future<ImportJob?> getJob(String id) =>
      (_db.select(_db.importJobs)..where((table) => table.id.equals(id)))
          .getSingleOrNull();

  Future<String> enqueue(
    ContentSource source, {
    String? learnerId,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now().toUtc();
    await _db.into(_db.importJobs).insert(
          ImportJobsCompanion.insert(
            id: id,
            learnerId: Value(learnerId),
            sourceType: source.type.name,
            displayName: source.displayName,
            sourceJson: jsonEncode(source.toJson()),
            status: ImportJobState.queued.name,
            createdAt: now,
            updatedAt: now,
          ),
        );
    return id;
  }

  Future<void> replaceSource(
    String id,
    ContentSource source, {
    ImportJobState? state,
    String? errorMessage,
  }) async {
    final affected = await (_db.update(_db.importJobs)
          ..where((table) => table.id.equals(id)))
        .write(
      ImportJobsCompanion(
        sourceType: Value(source.type.name),
        displayName: Value(source.displayName),
        sourceJson: Value(jsonEncode(source.toJson())),
        status: state == null ? const Value.absent() : Value(state.name),
        errorMessage: Value(errorMessage),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
    if (affected != 1) {
      throw StateError('导入任务不存在: $id');
    }
  }

  Future<void> updateStatus(
    String id,
    ImportJobState state, {
    String? errorMessage,
  }) async {
    await (_db.update(_db.importJobs)..where((table) => table.id.equals(id))).write(
      ImportJobsCompanion(
        status: Value(state.name),
        errorMessage: Value(errorMessage),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  ContentSource decodeSource(ImportJob job) => ContentSource.fromJson(
        Map<String, Object?>.from(jsonDecode(job.sourceJson) as Map),
      );
}

int _stableCardId(String input) {
  var hash = 0x811c9dc5;
  for (final codeUnit in input.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash == 0 ? 1 : hash;
}
