library course_schema;

enum Accent { curriculum, british, american }

enum LearningActivityType {
  watch,
  listen,
  repeat,
  phonics,
  spelling,
  dictation,
  translation,
  reading,
  speaking,
}

final class Course {
  const Course({
    required this.id,
    required this.title,
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.units,
    this.minimumAge,
    this.maximumAge,
    this.defaultAccent = Accent.curriculum,
    this.version = '0.1.0',
  });

  final String id;
  final String title;
  final String sourceLanguage;
  final String targetLanguage;
  final int? minimumAge;
  final int? maximumAge;
  final Accent defaultAccent;
  final String version;
  final List<CourseUnit> units;

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'sourceLanguage': sourceLanguage,
        'targetLanguage': targetLanguage,
        'minimumAge': minimumAge,
        'maximumAge': maximumAge,
        'defaultAccent': defaultAccent.name,
        'version': version,
        'units': units.map((unit) => unit.toJson()).toList(),
      };
}

final class CourseUnit {
  const CourseUnit({required this.id, required this.title, required this.lessons});

  final String id;
  final String title;
  final List<Lesson> lessons;

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'lessons': lessons.map((lesson) => lesson.toJson()).toList(),
      };
}

final class Lesson {
  const Lesson({
    required this.id,
    required this.title,
    required this.items,
    this.activities = const [],
  });

  final String id;
  final String title;
  final List<LearningItem> items;
  final List<LearningActivityType> activities;

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'items': items.map((item) => item.toJson()).toList(),
        'activities': activities.map((activity) => activity.name).toList(),
      };
}

final class LearningItem {
  const LearningItem({
    required this.id,
    required this.text,
    required this.translation,
    this.ipaBritish,
    this.ipaAmerican,
    this.phonics = const [],
  });

  final String id;
  final String text;
  final String translation;
  final String? ipaBritish;
  final String? ipaAmerican;
  final List<PhonicsSegment> phonics;

  Map<String, Object?> toJson() => {
        'id': id,
        'text': text,
        'translation': translation,
        'ipaBritish': ipaBritish,
        'ipaAmerican': ipaAmerican,
        'phonics': phonics.map((segment) => segment.toJson()).toList(),
      };
}

final class PhonicsSegment {
  const PhonicsSegment({required this.grapheme, required this.phoneme});

  final String grapheme;
  final String phoneme;

  Map<String, Object?> toJson() => {'grapheme': grapheme, 'phoneme': phoneme};
}
