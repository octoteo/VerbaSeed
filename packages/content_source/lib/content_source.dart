library content_source;

import 'package:course_schema/course_schema.dart';

enum ContentSourceType {
  cameraImage,
  pdf,
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

  Uri manifestUri({String manifestName = 'course.json'}) {
    final parts = <String>[owner, repository, ref];
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
}
