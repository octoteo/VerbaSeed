import 'package:content_source/content_source.dart';
import 'package:document_processing/document_processing.dart';
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

  test('compiles bilingual extracted pages into deterministic lessons', () {
    final document = ExtractedDocument(
      assetId: 'asset-1',
      mimeType: 'application/pdf',
      providerId: 'test-pdf',
      extractedAt: DateTime.utc(2026, 9, 16),
      pages: [
        ExtractedPage(
          pageNumber: 1,
          text: '你好\nHello\n再见 — Goodbye\n1',
        ),
        ExtractedPage(
          pageNumber: 2,
          text: 'How are you?\nHow are you?\n课堂练习',
        ),
      ],
    );

    final result = const CourseDraftCompiler().compileExtractedDocument(
      document: document,
      courseId: 'import-demo',
      title: 'Imported Demo',
    );

    final lessons = result.course.units.single.lessons;
    final items = lessons.expand((lesson) => lesson.items).toList();
    expect(lessons, hasLength(2));
    expect(items.map((item) => item.text), [
      'Hello',
      'Goodbye',
      'How are you?',
    ]);
    expect(items[0].translation, '你好');
    expect(items[1].translation, '再见');
    expect(result.itemCount, 3);
    expect(result.droppedLineCount, greaterThanOrEqualTo(1));
    expect(result.toMetadata()['compiledLessonCount'], 2);
  });

  test('flags sparse document drafts for review', () {
    final document = ExtractedDocument(
      assetId: 'asset-2',
      mimeType: 'image/png',
      providerId: 'test-ocr',
      extractedAt: DateTime.utc(2026, 9, 16),
      pages: [
        ExtractedPage(
          pageNumber: 1,
          text: 'Hello',
          blocks: [
            DocumentTextBlock(text: 'Hello', confidence: 0.55),
          ],
        ),
      ],
    );

    final result = const CourseDraftCompiler().compileExtractedDocument(
      document: document,
      courseId: 'sparse-demo',
      title: 'Sparse Demo',
    );

    expect(result.itemCount, 1);
    expect(result.requiresReview, isTrue);
    expect(result.warnings, isNotEmpty);
  });

  test('rejects extracted documents without English learning text', () {
    final document = ExtractedDocument(
      assetId: 'asset-3',
      mimeType: 'image/png',
      providerId: 'test-ocr',
      extractedAt: DateTime.utc(2026, 9, 16),
      pages: [ExtractedPage(pageNumber: 1, text: '只有中文内容')],
    );

    expect(
      () => const CourseDraftCompiler().compileExtractedDocument(
        document: document,
        courseId: 'no-english',
        title: 'No English',
      ),
      throwsFormatException,
    );
  });
}
