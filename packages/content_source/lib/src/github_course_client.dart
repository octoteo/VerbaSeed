import 'dart:convert';

import 'package:course_schema/course_schema.dart';
import 'package:http/http.dart' as http;

import '../content_source.dart' show GitHubCourseSource;

final class ContentSourceException implements Exception {
  const ContentSourceException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class GitHubCourseSnapshot {
  const GitHubCourseSnapshot({
    required this.source,
    required this.commitSha,
    required this.manifestUri,
    required this.course,
    required this.fetchedAt,
    this.etag,
  });

  factory GitHubCourseSnapshot.fromMetadata(Map<String, Object?> metadata) {
    final owner = metadata['owner'] as String?;
    final repository = metadata['repository'] as String?;
    final requestedRef =
        (metadata['requestedRef'] ?? metadata['ref']) as String? ?? 'main';
    final subpath = metadata['subpath'] as String? ?? '';
    final resolvedCommit = metadata['resolvedCommit'] as String?;
    final rawCourse = metadata['course'];
    final rawFetchedAt = metadata['fetchedAt'] as String?;
    if (owner == null || owner.trim().isEmpty) {
      throw const FormatException('missing GitHub owner');
    }
    if (repository == null || repository.trim().isEmpty) {
      throw const FormatException('missing GitHub repository');
    }
    if (resolvedCommit == null) {
      throw const FormatException('missing resolved commit');
    }
    final commitSha = _normalizeCommitSha(resolvedCommit);
    if (rawCourse is! Map) {
      throw const FormatException('missing GitHub course manifest');
    }
    if (rawFetchedAt == null) {
      throw const FormatException('missing GitHub fetch timestamp');
    }

    final source = GitHubCourseSource(
      owner: owner,
      repository: repository,
      ref: requestedRef,
      subpath: subpath,
    );
    final rawManifestUri = metadata['manifestUri'] as String?;
    return GitHubCourseSnapshot(
      source: source,
      commitSha: commitSha,
      manifestUri: rawManifestUri == null
          ? source.manifestUri(resolvedRef: commitSha)
          : Uri.parse(rawManifestUri),
      course: Course.fromJson(Map<String, Object?>.from(rawCourse)),
      fetchedAt: DateTime.parse(rawFetchedAt).toUtc(),
      etag: metadata['etag'] as String?,
    );
  }

  final GitHubCourseSource source;
  final String commitSha;
  final Uri manifestUri;
  final Course course;
  final DateTime fetchedAt;
  final String? etag;

  Map<String, Object?> toMetadata() => {
        'owner': source.owner,
        'repository': source.repository,
        'requestedRef': source.ref,
        'subpath': source.subpath,
        'resolvedCommit': commitSha,
        'manifestUri': manifestUri.toString(),
        'etag': etag,
        'fetchedAt': fetchedAt.toUtc().toIso8601String(),
        'course': course.toJson(),
      };
}

abstract interface class GitHubCourseRemote {
  Future<GitHubCourseSnapshot> fetch(
    GitHubCourseSource source, {
    String manifestName = 'course.json',
  });

  Future<GitHubCourseSnapshot> fetchAtCommit(
    GitHubCourseSource source,
    String commitSha, {
    String manifestName = 'course.json',
  });

  Future<GitHubCourseSnapshot?> fetchUpdate(
    GitHubCourseSource source, {
    required String currentCommitSha,
    String manifestName = 'course.json',
  });
}

final class GitHubCourseClient implements GitHubCourseRemote {
  GitHubCourseClient({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  static const maxManifestBytes = 4 * 1024 * 1024;

  final http.Client _client;
  final bool _ownsClient;

  @override
  Future<GitHubCourseSnapshot> fetch(
    GitHubCourseSource source, {
    String manifestName = 'course.json',
  }) async {
    final commitSha = await resolveCommit(source);
    return fetchAtCommit(
      source,
      commitSha,
      manifestName: manifestName,
    );
  }

  @override
  Future<GitHubCourseSnapshot> fetchAtCommit(
    GitHubCourseSource source,
    String commitSha, {
    String manifestName = 'course.json',
  }) async {
    final normalizedCommit = _normalizeCommitSha(commitSha);
    final manifestUri = source.manifestUri(
      manifestName: manifestName,
      resolvedRef: normalizedCommit,
    );
    final response = await _client.get(manifestUri);
    if (response.statusCode != 200) {
      throw ContentSourceException(
        '无法读取课程清单 (${response.statusCode}): $manifestUri',
      );
    }
    if (response.bodyBytes.length > maxManifestBytes) {
      throw const ContentSourceException('课程清单超过 4 MiB 安全限制');
    }

    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final course = Course.fromJson(Map<String, Object?>.from(decoded as Map));
      _validateCourse(course);
      return GitHubCourseSnapshot(
        source: source,
        commitSha: normalizedCommit,
        manifestUri: manifestUri,
        course: course,
        fetchedAt: DateTime.now().toUtc(),
        etag: response.headers['etag'],
      );
    } on ContentSourceException {
      rethrow;
    } on Object catch (error) {
      throw ContentSourceException('课程清单格式无效: $error');
    }
  }

  @override
  Future<GitHubCourseSnapshot?> fetchUpdate(
    GitHubCourseSource source, {
    required String currentCommitSha,
    String manifestName = 'course.json',
  }) async {
    final current = _normalizeCommitSha(currentCommitSha);
    final resolved = await resolveCommit(source);
    if (resolved == current) return null;
    return fetchAtCommit(
      source,
      resolved,
      manifestName: manifestName,
    );
  }

  Future<String> resolveCommit(GitHubCourseSource source) async {
    final uri = Uri.https(
      'api.github.com',
      '/repos/${source.owner}/${source.repository}/commits/${Uri.encodeComponent(source.ref)}',
    );
    final response = await _client.get(
      uri,
      headers: const {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      },
    );
    if (response.statusCode != 200) {
      throw ContentSourceException(
        '无法解析 GitHub 版本 (${response.statusCode}): ${source.owner}/${source.repository}@${source.ref}',
      );
    }

    try {
      final decoded = jsonDecode(response.body);
      final sha = (decoded as Map)['sha'] as String?;
      if (sha == null) {
        throw const FormatException('missing commit sha');
      }
      return _normalizeCommitSha(sha);
    } on Object catch (error) {
      throw ContentSourceException('GitHub 版本响应格式无效: $error');
    }
  }

  Future<bool> hasUpdate(GitHubCourseSnapshot snapshot) async =>
      await resolveCommit(snapshot.source) != snapshot.commitSha;

  void close() {
    if (_ownsClient) _client.close();
  }

  void _validateCourse(Course course) {
    if (course.id.trim().isEmpty ||
        course.title.trim().isEmpty ||
        course.targetLanguage.trim().isEmpty ||
        course.units.isEmpty) {
      throw const ContentSourceException('课程必须包含 id、title、targetLanguage 和至少一个 unit');
    }
  }
}

String _normalizeCommitSha(String value) {
  final normalized = value.trim().toLowerCase();
  if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(normalized)) {
    throw const FormatException('invalid GitHub commit sha');
  }
  return normalized;
}
