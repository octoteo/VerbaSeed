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

  factory Course.fromJson(Map<String, Object?> json) => Course(
        id: json['id']! as String,
        title: json['title']! as String,
        sourceLanguage: json['sourceLanguage']! as String,
        targetLanguage: json['targetLanguage']! as String,
        minimumAge: _intOrNull(json['minimumAge']),
        maximumAge: _intOrNull(json['maximumAge']),
        defaultAccent: Accent.values.byName(
          (json['defaultAccent'] as String?) ?? Accent.curriculum.name,
        ),
        version: (json['version'] as String?) ?? '0.1.0',
        units: _objectList(json['units'])
            .map((unit) => CourseUnit.fromJson(_objectMap(unit)))
            .toList(growable: false),
      );
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

  factory CourseUnit.fromJson(Map<String, Object?> json) => CourseUnit(
        id: json['id']! as String,
        title: json['title']! as String,
        lessons: _objectList(json['lessons'])
            .map((lesson) => Lesson.fromJson(_objectMap(lesson)))
            .toList(growable: false),
      );
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

  factory Lesson.fromJson(Map<String, Object?> json) => Lesson(
        id: json['id']! as String,
        title: json['title']! as String,
        items: _objectList(json['items'])
            .map((item) => LearningItem.fromJson(_objectMap(item)))
            .toList(growable: false),
        activities: _objectList(json['activities'])
            .map((activity) => LearningActivityType.values.byName(activity as String))
            .toList(growable: false),
      );
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

  factory LearningItem.fromJson(Map<String, Object?> json) => LearningItem(
        id: json['id']! as String,
        text: json['text']! as String,
        translation: (json['translation'] as String?) ?? '',
        ipaBritish: json['ipaBritish'] as String?,
        ipaAmerican: json['ipaAmerican'] as String?,
        phonics: _objectList(json['phonics'])
            .map((segment) => PhonicsSegment.fromJson(_objectMap(segment)))
            .toList(growable: false),
      );
}

final class PhonicsSegment {
  const PhonicsSegment({required this.grapheme, required this.phoneme});

  final String grapheme;
  final String phoneme;

  Map<String, Object?> toJson() => {'grapheme': grapheme, 'phoneme': phoneme};

  factory PhonicsSegment.fromJson(Map<String, Object?> json) => PhonicsSegment(
        grapheme: json['grapheme']! as String,
        phoneme: json['phoneme']! as String,
      );
}

int? _intOrNull(Object? value) => switch (value) {
      final int value => value,
      final num value => value.toInt(),
      _ => null,
    };

List<Object?> _objectList(Object? value) => switch (value) {
      final List<Object?> value => value,
      final List value => List<Object?>.from(value),
      _ => const [],
    };

Map<String, Object?> _objectMap(Object? value) =>
    Map<String, Object?>.from(value! as Map);
