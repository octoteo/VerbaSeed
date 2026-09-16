library content_source;

export 'src/github_course_client.dart';

import 'package:course_schema/course_schema.dart';
import 'package:document_processing/document_processing.dart';

enum ContentSourceType {
  cameraImage,
  image,
  pdf,
  file,
  github,
  web,
  subtitle,
  plainText,
}

enum ImportJobState { queued, processing, ready, failed, cancelled }

final class ContentSource {
  const ContentSource({
    required this.type,
    required this.displayName,
    this.uri,
    this.metadata = const {},
  });

  final ContentSourceType type;
  final String displayName;
  final Uri? uri;
  final Map<String, Object?> metadata;

  ContentSource copyWith({
    ContentSourceType? type,
    String? displayName,
    Uri? uri,
    Map<String, Object?>? metadata,
  }) =>
      ContentSource(
        type: type ?? this.type,
        displayName: displayName ?? this.displayName,
        uri: uri ?? this.uri,
        metadata: metadata ?? this.metadata,
      );

  Map<String, Object?> toJson() => {
        'type': type.name,
        'displayName': displayName,
        'uri': uri?.toString(),
        'metadata': metadata,
      };

  factory ContentSource.fromJson(Map<String, Object?> json) => ContentSource(
        type: ContentSourceType.values.byName(json['type']! as String),
        displayName: json['displayName']! as String,
        uri: switch (json['uri']) {
          final String value when value.isNotEmpty => Uri.parse(value),
          _ => null,
        },
        metadata: Map<String, Object?>.from(
          (json['metadata'] as Map?) ?? const <String, Object?>{},
        ),
      );
}

final class GitHubCourseSource {
  const GitHubCourseSource({
    required this.owner,
    required this.repository,
    this.ref = 'main',
    this.subpath = '',
  });

  final String owner;
  final String repository;
  final String ref;
  final String subpath;

  factory GitHubCourseSource.parse(String input) {
    final trimmed = input.trim();
    final normalized = trimmed.contains('://') ? trimmed : 'https://github.com/$trimmed';
    final uri = Uri.tryParse(normalized);
    if (uri == null || uri.scheme != 'https' || uri.host.toLowerCase() != 'github.com') {
      throw const FormatException('请输入 github.com 上的 HTTPS 仓库地址');
    }

    final segments = uri.pathSegments.where((segment) => segment.isNotEmpty).toList();
    if (segments.length < 2) {
      throw const FormatException('GitHub 地址需要包含 owner/repository');
    }

    final owner = segments[0];
    final repository = segments[1].replaceFirst(RegExp(r'\.git$'), '');
    var ref = 'main';
    var subpath = '';

    if (segments.length >= 4 && segments[2] == 'tree') {
      ref = segments[3];
      if (segments.length > 4) {
        subpath = segments.sublist(4).join('/');
      }
    }

    return GitHubCourseSource(
      owner: owner,
      repository: repository,
      ref: ref,
      subpath: subpath,
    );
  }

  Uri manifestUri({String manifestName = 'course.json', String? resolvedRef}) {
    final parts = <String>[owner, repository, resolvedRef ?? ref];
    if (subpath.isNotEmpty) {
      parts.addAll(subpath.split('/'));
    }
    parts.add(manifestName);
    return Uri.https('raw.githubusercontent.com', parts.join('/'));
  }

  ContentSource toContentSource() => ContentSource(
        type: ContentSourceType.github,
        displayName: '$owner/$repository',
        uri: Uri.https('github.com', '/$owner/$repository'),
        metadata: {
          'owner': owner,
          'repository': repository,
          'ref': ref,
          'subpath': subpath,
          'manifestUri': manifestUri().toString(),
        },
      );
}

final class CourseDraftCompilation {
  const CourseDraftCompilation({
    required this.course,
    required this.candidateLineCount,
    required this.droppedLineCount,
    required this.pageCount,
    required this.requiresReview,
    this.warnings = const [],
  });

  final Course course;
  final int candidateLineCount;
  final int droppedLineCount;
  final int pageCount;
  final bool requiresReview;
  final List<String> warnings;

  int get itemCount => course.units
      .expand((unit) => unit.lessons)
      .expand((lesson) => lesson.items)
      .length;

  int get lessonCount =>
      course.units.expand((unit) => unit.lessons).length;

  Map<String, Object?> toMetadata() => {
        'compiledItemCount': itemCount,
        'compiledLessonCount': lessonCount,
        'candidateLineCount': candidateLineCount,
        'droppedLineCount': droppedLineCount,
        'compiledPageCount': pageCount,
        'courseDraftNeedsReview': requiresReview,
        if (warnings.isNotEmpty) 'courseDraftWarnings': warnings,
      };
}

final class CourseDraftCompiler {
  const CourseDraftCompiler();

  Course compilePlainText({
    required String courseId,
    required String title,
    required String text,
    String sourceLanguage = 'zh-CN',
    String targetLanguage = 'en',
  }) {
    final lines = text
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);

    if (lines.isEmpty) {
      throw const FormatException('文本中没有可编译的学习内容');
    }

    final items = <LearningItem>[
      for (var index = 0; index < lines.length; index++)
        LearningItem(
          id: '$courseId-item-${index + 1}',
          text: lines[index],
          translation: '',
        ),
    ];

    return Course(
      id: courseId,
      title: title.trim().isEmpty ? 'Untitled course' : title.trim(),
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
      units: [
        CourseUnit(
          id: '$courseId-unit-1',
          title: 'Imported content',
          lessons: [
            Lesson(
              id: '$courseId-lesson-1',
              title: 'Imported lesson',
              items: items,
              activities: const [
                LearningActivityType.listen,
                LearningActivityType.repeat,
                LearningActivityType.spelling,
                LearningActivityType.translation,
              ],
            ),
          ],
        ),
      ],
    );
  }

  CourseDraftCompilation compileExtractedDocument({
    required ExtractedDocument document,
    required String courseId,
    required String title,
    String sourceLanguage = 'zh-CN',
    String targetLanguage = 'en',
    int maxItemsPerLesson = 20,
  }) {
    if (courseId.trim().isEmpty) {
      throw const FormatException('courseId cannot be empty');
    }
    if (maxItemsPerLesson < 1) {
      throw RangeError.range(maxItemsPerLesson, 1, null, 'maxItemsPerLesson');
    }

    final pageCandidates = <int, List<_DraftCandidate>>{};
    var candidateLineCount = 0;
    var droppedLineCount = 0;
    final seen = <String>{};
    final confidences = <double>[];

    for (final page in document.pages) {
      for (final block in page.blocks) {
        final confidence = block.confidence;
        if (confidence != null) confidences.add(confidence);
      }

      final rawLines = _pageLines(page);
      candidateLineCount += rawLines.length;
      var index = 0;
      while (index < rawLines.length) {
        final current = rawLines[index];
        final inline = _splitBilingual(current);
        if (inline != null) {
          if (_addCandidate(pageCandidates, seen, page.pageNumber, inline)) {
            index += 1;
            continue;
          }
        }

        if (index + 1 < rawLines.length) {
          final next = rawLines[index + 1];
          final pair = _pairAdjacent(current, next);
          if (pair != null &&
              _addCandidate(pageCandidates, seen, page.pageNumber, pair)) {
            index += 2;
            continue;
          }
        }

        if (_isTargetEnglish(current)) {
          final candidate = _DraftCandidate(text: current, translation: '');
          if (!_addCandidate(pageCandidates, seen, page.pageNumber, candidate)) {
            droppedLineCount += 1;
          }
        } else {
          droppedLineCount += 1;
        }
        index += 1;
      }
    }

    final totalItems = pageCandidates.values.fold<int>(
      0,
      (total, values) => total + values.length,
    );
    if (totalItems == 0) {
      throw const FormatException('解析结果中没有检测到可生成英语学习项的文本');
    }

    final lessons = <Lesson>[];
    var globalItemIndex = 0;
    for (final entry in pageCandidates.entries) {
      final candidates = entry.value;
      for (var offset = 0; offset < candidates.length; offset += maxItemsPerLesson) {
        final end = (offset + maxItemsPerLesson).clamp(0, candidates.length);
        final chunk = candidates.sublist(offset, end);
        final section = offset ~/ maxItemsPerLesson + 1;
        final items = <LearningItem>[];
        for (final candidate in chunk) {
          globalItemIndex += 1;
          items.add(
            LearningItem(
              id: '$courseId-item-$globalItemIndex',
              text: candidate.text,
              translation: candidate.translation,
            ),
          );
        }
        final hasTranslations =
            chunk.any((candidate) => candidate.translation.isNotEmpty);
        lessons.add(
          Lesson(
            id: '$courseId-page-${entry.key}-part-$section',
            title: candidates.length > maxItemsPerLesson
                ? 'Page ${entry.key} · Part $section'
                : 'Page ${entry.key}',
            items: items,
            activities: [
              LearningActivityType.reading,
              LearningActivityType.spelling,
              LearningActivityType.dictation,
              if (hasTranslations) LearningActivityType.translation,
            ],
          ),
        );
      }
    }

    final warnings = <String>[];
    var requiresReview = false;
    if (totalItems < 3) {
      warnings.add('仅生成 $totalItems 个学习项，建议确认识别范围或 OCR 质量。');
      requiresReview = true;
    }
    if (confidences.isNotEmpty) {
      final average =
          confidences.reduce((left, right) => left + right) / confidences.length;
      if (average < 0.70) {
        warnings.add('OCR 平均置信度较低（${(average * 100).round()}%），建议人工复核。');
        requiresReview = true;
      }
    }
    if (droppedLineCount > 0) {
      warnings.add('已忽略 $droppedLineCount 行页码、中文说明或非英语学习文本。');
    }

    final course = Course(
      id: courseId,
      title: title.trim().isEmpty ? 'Imported course' : title.trim(),
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
      units: [
        CourseUnit(
          id: '$courseId-unit-1',
          title: 'Imported document',
          lessons: lessons,
        ),
      ],
    );

    return CourseDraftCompilation(
      course: course,
      candidateLineCount: candidateLineCount,
      droppedLineCount: droppedLineCount,
      pageCount: document.pages.length,
      requiresReview: requiresReview,
      warnings: List.unmodifiable(warnings),
    );
  }

  static List<String> _pageLines(ExtractedPage page) {
    final source = page.blocks.isNotEmpty
        ? page.blocks.expand((block) => block.text.split(RegExp(r'\r?\n')))
        : page.text.split(RegExp(r'\r?\n'));
    final lines = <String>[];
    for (final raw in source) {
      final normalized = _normalizeLine(raw);
      if (normalized.isEmpty || _isNoise(normalized)) continue;
      lines.add(normalized);
    }
    return lines;
  }

  static String _normalizeLine(String value) {
    var normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    normalized = normalized.replaceFirst(
      RegExp(r'^\s*(?:[-*•·▪◦]+|\d+[.)、])\s*'),
      '',
    );
    return normalized.trim();
  }

  static bool _isNoise(String value) =>
      RegExp(r'^(?:page\s*)?\d{1,4}$', caseSensitive: false).hasMatch(value) ||
      RegExp(r'^[^A-Za-z\u3400-\u9FFF]{1,8}$').hasMatch(value);

  static _DraftCandidate? _splitBilingual(String value) {
    const separators = ['\t', ' | ', '｜', ' — ', ' – ', ' - ', '：', ': '];
    for (final separator in separators) {
      final index = value.indexOf(separator);
      if (index <= 0 || index >= value.length - separator.length) continue;
      final left = value.substring(0, index).trim();
      final right = value.substring(index + separator.length).trim();
      if (_isTargetEnglish(left) && _isSourceChinese(right)) {
        return _DraftCandidate(text: left, translation: right);
      }
      if (_isSourceChinese(left) && _isTargetEnglish(right)) {
        return _DraftCandidate(text: right, translation: left);
      }
    }
    return null;
  }

  static _DraftCandidate? _pairAdjacent(String first, String second) {
    if (_isSourceChinese(first) && _isTargetEnglish(second)) {
      return _DraftCandidate(text: second, translation: first);
    }
    if (_isTargetEnglish(first) && _isSourceChinese(second)) {
      return _DraftCandidate(text: first, translation: second);
    }
    return null;
  }

  static bool _isTargetEnglish(String value) {
    final counts = _languageCounts(value);
    return counts.latin >= 2 && counts.latin >= counts.han;
  }

  static bool _isSourceChinese(String value) {
    final counts = _languageCounts(value);
    return counts.han >= 1 && counts.han >= counts.latin;
  }

  static _LanguageCounts _languageCounts(String value) {
    var latin = 0;
    var han = 0;
    for (final rune in value.runes) {
      if ((rune >= 0x41 && rune <= 0x5A) ||
          (rune >= 0x61 && rune <= 0x7A)) {
        latin += 1;
      } else if ((rune >= 0x3400 && rune <= 0x4DBF) ||
          (rune >= 0x4E00 && rune <= 0x9FFF)) {
        han += 1;
      }
    }
    return _LanguageCounts(latin: latin, han: han);
  }

  static bool _addCandidate(
    Map<int, List<_DraftCandidate>> pages,
    Set<String> seen,
    int pageNumber,
    _DraftCandidate candidate,
  ) {
    final key = candidate.text.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (key.isEmpty || !seen.add(key)) return false;
    pages.putIfAbsent(pageNumber, () => <_DraftCandidate>[]).add(candidate);
    return true;
  }
}

final class _DraftCandidate {
  const _DraftCandidate({required this.text, required this.translation});

  final String text;
  final String translation;
}

final class _LanguageCounts {
  const _LanguageCounts({required this.latin, required this.han});

  final int latin;
  final int han;
}
