import 'package:course_schema/course_schema.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/course_draft_review_service.dart';
import '../../data/providers.dart';

class CourseDraftReviewPage extends ConsumerStatefulWidget {
  const CourseDraftReviewPage({
    required this.jobId,
    super.key,
  });

  final String jobId;

  @override
  ConsumerState<CourseDraftReviewPage> createState() =>
      _CourseDraftReviewPageState();
}

class _CourseDraftReviewPageState
    extends ConsumerState<CourseDraftReviewPage> {
  final TextEditingController _titleController = TextEditingController();
  CourseDraftReview? _review;
  _EditableCourse? _draft;
  Object? _error;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final review =
          await ref.read(courseDraftReviewServiceProvider).load(widget.jobId);
      if (!mounted) return;
      _applyReview(review);
      setState(() {
        _loading = false;
        _error = null;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  void _applyReview(CourseDraftReview review) {
    _review = review;
    _draft = _EditableCourse.fromCourse(review.course);
    _titleController.text = review.course.title;
  }

  Future<void> _save({required bool accept}) async {
    final draft = _draft;
    if (draft == null || _saving) return;
    draft.title = _titleController.text;

    setState(() => _saving = true);
    try {
      final review = await ref.read(courseDraftReviewServiceProvider).save(
            jobId: widget.jobId,
            course: draft.toCourse(),
            accept: accept,
          );
      if (!mounted) return;
      _applyReview(review);
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            accept
                ? '课程草稿已人工接受，后续可安装到本地课程库'
                : '课程草稿已保存为新的本地修订版本',
          ),
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败：$error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('课程草稿复核'),
        actions: [
          IconButton(
            tooltip: '重新载入本地草稿',
            onPressed: _saving ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: switch ((_loading, _error, _review, _draft)) {
        (true, _, _, _) => const Center(child: CircularProgressIndicator()),
        (false, final Object error, _, _) => _ErrorView(
            error: error,
            onRetry: _load,
          ),
        (false, null, final CourseDraftReview review,
              final _EditableCourse draft) =>
          _buildEditor(context, review, draft),
        _ => const Center(child: Text('课程草稿状态无效')),
      },
      bottomNavigationBar: _review == null || _draft == null || _error != null
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _saving ? null : () => _save(accept: false),
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('保存草稿'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _saving ? null : () => _save(accept: true),
                      icon: _saving
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.verified_outlined),
                      label: Text(
                        _review?.status == 'accepted' ? '重新接受' : '接受草稿',
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildEditor(
    BuildContext context,
    CourseDraftReview review,
    _EditableCourse draft,
  ) {
    final theme = Theme.of(context);
    final itemCount = draft.units
        .expand((unit) => unit.lessons)
        .expand((lesson) => lesson.items)
        .length;
    final lessonCount = draft.units.expand((unit) => unit.lessons).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      review.status == 'accepted'
                          ? Icons.verified
                          : review.requiresReview
                              ? Icons.rate_review_outlined
                              : Icons.auto_stories_outlined,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        review.status == 'accepted'
                            ? '已人工接受'
                            : review.requiresReview
                                ? '需要人工复核'
                                : '本地课程草稿已生成',
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('$lessonCount 个课节 · $itemCount 个学习项 · 全程本地处理'),
                if (review.warnings.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  for (final warning in review.warnings)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.info_outline, size: 18),
                          const SizedBox(width: 8),
                          Expanded(child: Text(warning)),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _titleController,
          decoration: const InputDecoration(
            labelText: '课程名称',
            border: OutlineInputBorder(),
          ),
          textInputAction: TextInputAction.done,
        ),
        const SizedBox(height: 16),
        for (final unit in draft.units)
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.menu_book_outlined),
                  title: Text(unit.title),
                  subtitle: Text('${unit.lessons.length} 个课节'),
                ),
                for (final lesson in unit.lessons)
                  _LessonEditor(
                    key: ValueKey(lesson.id),
                    lesson: lesson,
                    onChanged: () => setState(() {}),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _LessonEditor extends StatelessWidget {
  const _LessonEditor({
    required this.lesson,
    required this.onChanged,
    super.key,
  });

  final _EditableLesson lesson;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      initiallyExpanded: true,
      title: Text(lesson.title),
      subtitle: Text('${lesson.items.length} 个学习项'),
      childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      children: [
        if (lesson.items.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('此课节已没有学习项；至少需要在整门课程中保留一个学习项。'),
          ),
        for (var index = 0; index < lesson.items.length; index++)
          KeyedSubtree(
            key: ValueKey(lesson.items[index].id),
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '学习项 ${index + 1}',
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                          ),
                          IconButton(
                            tooltip: '移除误识别项',
                            onPressed: () {
                              lesson.items.removeAt(index);
                              onChanged();
                            },
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                      TextFormField(
                        initialValue: lesson.items[index].text,
                        decoration: const InputDecoration(
                          labelText: '英语内容',
                          hintText: '例如 Open your book.',
                        ),
                        onChanged: (value) => lesson.items[index].text = value,
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        initialValue: lesson.items[index].translation,
                        decoration: const InputDecoration(
                          labelText: '中文释义（可选）',
                        ),
                        onChanged: (value) =>
                            lesson.items[index].translation = value,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 12),
              Text(
                '无法打开课程草稿',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text('$error', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _EditableCourse {
  _EditableCourse({
    required this.original,
    required this.title,
    required this.units,
  });

  factory _EditableCourse.fromCourse(Course course) => _EditableCourse(
        original: course,
        title: course.title,
        units: course.units
            .map(_EditableUnit.fromUnit)
            .toList(growable: false),
      );

  final Course original;
  String title;
  final List<_EditableUnit> units;

  Course toCourse() => Course(
        id: original.id,
        title: title.trim(),
        sourceLanguage: original.sourceLanguage,
        targetLanguage: original.targetLanguage,
        minimumAge: original.minimumAge,
        maximumAge: original.maximumAge,
        defaultAccent: original.defaultAccent,
        version: original.version,
        units: units.map((unit) => unit.toUnit()).toList(growable: false),
      );
}

final class _EditableUnit {
  _EditableUnit({
    required this.id,
    required this.title,
    required this.lessons,
  });

  factory _EditableUnit.fromUnit(CourseUnit unit) => _EditableUnit(
        id: unit.id,
        title: unit.title,
        lessons: unit.lessons
            .map(_EditableLesson.fromLesson)
            .toList(growable: false),
      );

  final String id;
  final String title;
  final List<_EditableLesson> lessons;

  CourseUnit toUnit() => CourseUnit(
        id: id,
        title: title,
        lessons: lessons.map((lesson) => lesson.toLesson()).toList(growable: false),
      );
}

final class _EditableLesson {
  _EditableLesson({
    required this.id,
    required this.title,
    required this.activities,
    required this.items,
  });

  factory _EditableLesson.fromLesson(Lesson lesson) => _EditableLesson(
        id: lesson.id,
        title: lesson.title,
        activities: lesson.activities,
        items: lesson.items
            .map(_EditableItem.fromItem)
            .toList(growable: true),
      );

  final String id;
  final String title;
  final List<LearningActivityType> activities;
  final List<_EditableItem> items;

  Lesson toLesson() => Lesson(
        id: id,
        title: title,
        activities: activities,
        items: items.map((item) => item.toItem()).toList(growable: false),
      );
}

final class _EditableItem {
  _EditableItem({
    required this.original,
    required this.text,
    required this.translation,
  });

  factory _EditableItem.fromItem(LearningItem item) => _EditableItem(
        original: item,
        text: item.text,
        translation: item.translation,
      );

  final LearningItem original;
  String text;
  String translation;

  String get id => original.id;

  LearningItem toItem() => LearningItem(
        id: original.id,
        text: text.trim(),
        translation: translation.trim(),
        ipaBritish: original.ipaBritish,
        ipaAmerican: original.ipaAmerican,
        phonics: original.phonics,
      );
}
