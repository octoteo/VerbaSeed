import 'dart:convert';

import 'package:content_source/content_source.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  const sha1 = '0123456789abcdef0123456789abcdef01234567';
  const sha2 = '89abcdef0123456789abcdef0123456789abcdef';

  test('pins GitHub course manifest to resolved commit', () async {
    final client = MockClient((request) async {
      if (request.url.host == 'api.github.com') {
        return http.Response(jsonEncode({'sha': sha1}), 200);
      }
      expect(request.url.host, 'raw.githubusercontent.com');
      expect(request.url.path, contains('/$sha1/'));
      return _courseResponse(title: 'Demo course', etag: 'manifest-v1');
    });

    final source = GitHubCourseSource.parse('https://github.com/example/course');
    final snapshot = await GitHubCourseClient(client: client).fetch(source);

    expect(snapshot.commitSha, sha1);
    expect(snapshot.course.id, 'demo');
    expect(snapshot.etag, 'manifest-v1');
    expect(snapshot.manifestUri.path, contains('/$sha1/'));
  });

  test('fetchAtCommit never resolves the branch again', () async {
    var apiRequests = 0;
    final client = MockClient((request) async {
      if (request.url.host == 'api.github.com') {
        apiRequests += 1;
        return http.Response(jsonEncode({'sha': sha2}), 200);
      }
      expect(request.url.host, 'raw.githubusercontent.com');
      expect(request.url.path, contains('/$sha1/'));
      return _courseResponse(title: 'Pinned preview');
    });

    final source = GitHubCourseSource.parse('example/course');
    final snapshot = await GitHubCourseClient(client: client).fetchAtCommit(
      source,
      sha1,
    );

    expect(apiRequests, 0);
    expect(snapshot.commitSha, sha1);
    expect(snapshot.course.title, 'Pinned preview');
  });

  test('fetchUpdate returns null without downloading when ref is unchanged', () async {
    var rawRequests = 0;
    final client = MockClient((request) async {
      if (request.url.host == 'api.github.com') {
        return http.Response(jsonEncode({'sha': sha1}), 200);
      }
      rawRequests += 1;
      return _courseResponse(title: 'Unexpected');
    });

    final source = GitHubCourseSource.parse('example/course');
    final update = await GitHubCourseClient(client: client).fetchUpdate(
      source,
      currentCommitSha: sha1,
    );

    expect(update, isNull);
    expect(rawRequests, 0);
  });

  test('fetchUpdate downloads exactly the newly resolved commit', () async {
    var apiRequests = 0;
    var rawRequests = 0;
    final client = MockClient((request) async {
      if (request.url.host == 'api.github.com') {
        apiRequests += 1;
        return http.Response(jsonEncode({'sha': sha2}), 200);
      }
      rawRequests += 1;
      expect(request.url.host, 'raw.githubusercontent.com');
      expect(request.url.path, contains('/$sha2/'));
      return _courseResponse(title: 'Updated course', etag: 'manifest-v2');
    });

    final source = GitHubCourseSource.parse('example/course');
    final update = await GitHubCourseClient(client: client).fetchUpdate(
      source,
      currentCommitSha: sha1,
    );

    expect(apiRequests, 1);
    expect(rawRequests, 1);
    expect(update, isNotNull);
    expect(update!.commitSha, sha2);
    expect(update.course.title, 'Updated course');
    expect(update.etag, 'manifest-v2');
  });

  test('rejects malformed manifests', () async {
    final client = MockClient((request) async {
      if (request.url.host == 'api.github.com') {
        return http.Response(jsonEncode({'sha': sha1}), 200);
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

http.Response _courseResponse({
  required String title,
  String? etag,
}) =>
    http.Response.bytes(
      utf8.encode(
        jsonEncode({
          'id': 'demo',
          'title': title,
          'sourceLanguage': 'zh-CN',
          'targetLanguage': 'en',
          'units': [
            {
              'id': 'u1',
              'title': 'Unit 1',
              'lessons': [
                {
                  'id': 'l1',
                  'title': 'Lesson 1',
                  'items': [
                    {
                      'id': 'item-1',
                      'text': 'Hello',
                      'translation': '你好',
                    },
                  ],
                },
              ],
            },
          ],
        }),
      ),
      200,
      headers: {
        'content-type': 'application/json; charset=utf-8',
        if (etag != null) 'etag': etag,
      },
    );
