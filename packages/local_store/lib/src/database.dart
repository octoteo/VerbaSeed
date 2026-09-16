import 'package:drift/drift.dart';

part 'database.g.dart';

class LearnerProfiles extends Table {
  TextColumn get id => text()();
  TextColumn get displayName => text().withLength(min: 1, max: 80)();
  IntColumn get birthYear => integer().nullable()();
  TextColumn get nativeLanguage => text().withDefault(const Constant('zh-CN'))();
  TextColumn get targetLanguage => text().withDefault(const Constant('en'))();
  TextColumn get preferredAccent => text().withDefault(const Constant('curriculum'))();
  BoolColumn get isActive => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class ReviewCards extends Table {
  TextColumn get id => text()();
  TextColumn get learnerId => text().references(
        LearnerProfiles,
        #id,
        onDelete: KeyAction.cascade,
      )();
  TextColumn get itemId => text()();
  TextColumn get cardJson => text()();
  DateTimeColumn get dueAt => dateTime()();
  DateTimeColumn get lastReviewedAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  Set<Set<Column<Object>>> get uniqueKeys => {
        {learnerId, itemId},
      };
}

class ReviewEvents extends Table {
  TextColumn get id => text()();
  TextColumn get learnerId => text().references(
        LearnerProfiles,
        #id,
        onDelete: KeyAction.cascade,
      )();
  TextColumn get itemId => text()();
  TextColumn get rating => text()();
  DateTimeColumn get reviewedAt => dateTime()();
  TextColumn get cardJson => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class ImportJobs extends Table {
  TextColumn get id => text()();
  TextColumn get learnerId => text().nullable()();
  TextColumn get sourceType => text()();
  TextColumn get displayName => text()();
  TextColumn get sourceJson => text()();
  TextColumn get status => text()();
  TextColumn get errorMessage => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(
  tables: [LearnerProfiles, ReviewCards, ReviewEvents, ImportJobs],
)
class VerbaSeedDatabase extends _$VerbaSeedDatabase {
  VerbaSeedDatabase(QueryExecutor executor) : super(executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (migrator) async {
          await migrator.createAll();
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_review_cards_due '
            'ON review_cards (learner_id, due_at)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_import_jobs_created '
            'ON import_jobs (created_at)',
          );
        },
        beforeOpen: (_) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}
