import 'dart:convert';

import 'package:content_source/content_source.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  const sha = '0123456789abcdef0123456789abcdef01234567';

  test('pins GitHub course manifest to resolved commit', () async {
    final client = MockClient((request) async {
      if (request.url.host == 'api.github.com') {
        return http.Response(jsonEncode({'sha': sha}), 200);
      }
      expect(request.url.host, 'raw.githubusercontent.com');
      expect(request.url.path, contains('/$sha/'));
      return http.Response(
        jsonEncode({
          'id': 'demo',
          'title': 'Demo course',
          'sourceLanguage': 'zh-CN',
          'targetLanguage': 'en',
          'units': [
            {'id': 'u1', 'title': 'Unit 1', 'lessons': []},
          ],
        }),
        200,
        headers: {'etag': 'manifest-v1'},
      );
    });

    final source = GitHubCourseSource.parse('https://github.com/example/course');
    final snapshot = await GitHubCourseClient(client: client).fetch(source);

    expect(snapshot.commitSha, sha);
    expect(snapshot.course.id, 'demo');
    expect(snapshot.etag, 'manifest-v1');
    expect(snapshot.manifestUri.path, contains('/$sha/'));
  });

  test('rejects oversized or malformed manifests', () async {
    final client = MockClient((request) async {
      if (request.url.host == 'api.github.com') {
        return http.Response(jsonEncode({'sha': sha}), 200);
      }
      return http.Response('{}', 200);
    });

    final source = GitHubCourseSource.parse('example/course');
    expect(
      () => GitHubCourseClient(client: client).fetch(source),
      throwsA(isA<ContentSourceException>()),
    );
  });
}
