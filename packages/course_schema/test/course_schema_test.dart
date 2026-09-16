import 'package:course_schema/course_schema.dart';
import 'package:test/test.dart';

void main() {
  test('serializes a bilingual course with accent metadata', () {
    const course = Course(
      id: 'demo-course',
      title: 'Demo Course',
      sourceLanguage: 'zh-CN',
      targetLanguage: 'en',
      defaultAccent: Accent.curriculum,
      units: [
        CourseUnit(
          id: 'u1',
          title: 'Unit 1',
          lessons: [
            Lesson(
              id: 'l1',
              title: 'Hello',
              activities: [LearningActivityType.listen, LearningActivityType.repeat],
              items: [
                LearningItem(
                  id: 'hello',
                  text: 'hello',
                  translation: '你好',
                  ipaBritish: '/həˈləʊ/',
                  ipaAmerican: '/həˈloʊ/',
                ),
              ],
            ),
          ],
        ),
      ],
    );

    final json = course.toJson();
    expect(json['id'], 'demo-course');
    expect(json['defaultAccent'], 'curriculum');
    expect((json['units']! as List<Object?>), hasLength(1));
  });
}
