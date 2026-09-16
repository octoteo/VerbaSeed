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
  List<Set<Column<Object>>> get uniqueKeys => [
        {learnerId, itemId},
      ];
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

/// Stable course identity installed on this device.
///
/// Course bytes remain immutable in Content Store. This table only points at the
/// latest logical version so raw import jobs can be cleaned up independently.
class InstalledCourses extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withLength(min: 1, max: 240)();
  IntColumn get currentVersion => integer()();
  TextColumn get sourceJobId => text().nullable()();
  DateTimeColumn get installedAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Immutable installation history for a course.
class InstalledCourseVersions extends Table {
  TextColumn get id => text()();
  TextColumn get courseId => text().references(
        InstalledCourses,
        #id,
        onDelete: KeyAction.cascade,
      )();
  IntColumn get version => integer()();
  TextColumn get assetId => text()();
  TextColumn get sourceJobId => text().nullable()();
  IntColumn get itemCount => integer()();
  IntColumn get lessonCount => integer()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {courseId, version},
      ];
}

/// Per-learner enrollment is intentionally separate from device-wide install.
class LearnerCourseEnrollments extends Table {
  TextColumn get id => text()();
  TextColumn get learnerId => text().references(
        LearnerProfiles,
        #id,
        onDelete: KeyAction.cascade,
      )();
  TextColumn get courseId => text().references(
        InstalledCourses,
        #id,
        onDelete: KeyAction.cascade,
      )();
  IntColumn get version => integer()();
  DateTimeColumn get enrolledAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {learnerId, courseId},
      ];
}

@DriftDatabase(
  tables: [
    LearnerProfiles,
    ReviewCards,
    ReviewEvents,
    ImportJobs,
    InstalledCourses,
    InstalledCourseVersions,
    LearnerCourseEnrollments,
  ],
)
class VerbaSeedDatabase extends _$VerbaSeedDatabase {
  VerbaSeedDatabase(QueryExecutor executor) : super(executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (migrator) async {
          await migrator.createAll();
          await _createIndexes();
        },
        onUpgrade: (migrator, from, to) async {
          if (from < 2) {
            await migrator.createTable(installedCourses);
            await migrator.createTable(installedCourseVersions);
            await migrator.createTable(learnerCourseEnrollments);
            await _createCourseIndexes();
          }
        },
        beforeOpen: (_) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  Future<void> _createIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_review_cards_due '
      'ON review_cards (learner_id, due_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_import_jobs_created '
      'ON import_jobs (created_at)',
    );
    await _createCourseIndexes();
  }

  Future<void> _createCourseIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_installed_course_versions_course '
      'ON installed_course_versions (course_id, version)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_learner_course_enrollments_learner '
      'ON learner_course_enrollments (learner_id, updated_at)',
    );
  }
}
