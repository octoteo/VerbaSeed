import 'package:content_source/content_source.dart';
import 'package:test/test.dart';

void main() {
  test('parses GitHub course repository URL', () {
    final source = GitHubCourseSource.parse(
      'https://github.com/octoteo/VerbaSeed/tree/main/examples',
    );

    expect(source.owner, 'octoteo');
    expect(source.repository, 'VerbaSeed');
    expect(source.ref, 'main');
    expect(source.subpath, 'examples');
    expect(
      source.manifestUri().toString(),
      'https://raw.githubusercontent.com/octoteo/VerbaSeed/main/examples/course.json',
    );
  });

  test('compiles plain text into an open course draft', () {
    final course = const CourseDraftCompiler().compilePlainText(
      courseId: 'demo',
      title: 'Demo',
      text: 'hello\nworld',
    );

    expect(course.units.single.lessons.single.items, hasLength(2));
    expect(course.units.single.lessons.single.items.first.text, 'hello');
  });
}
