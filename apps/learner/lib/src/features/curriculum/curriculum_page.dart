import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:local_store/local_store.dart';

import '../../data/providers.dart';

class CurriculumPage extends ConsumerWidget {
  const CurriculumPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courses = ref.watch(installedCoursesProvider);
    final activeLearnerState = ref.watch(activeLearnerProvider);
    final activeLearner = activeLearnerState.asData?.value;
    final enrollmentState = activeLearner == null
        ? null
        : ref.watch(learnerCourseEnrollmentsProvider(activeLearner.id));
    final enrolledCourseIds = enrollmentState?.asData?.value
            .map((enrollment) => enrollment.courseId)
            .toSet() ??
        const <String>{};

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('教材世界', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        const Text('导入、复核并安装到设备的课程会进入这里；课程数据与学习进度默认保存在本地。'),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: Text(
                '我的本地课程',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            if (activeLearner != null)
              Chip(
                avatar: const Icon(Icons.person_outline, size: 18),
                label: Text('当前：${activeLearner.displayName}'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        courses.when(
          data: (items) {
            if (items.isEmpty) {
              return _EmptyCourseLibrary(
                hasActiveLearner: activeLearner != null,
                onImport: () => context.go('/import'),
                onProfiles: () => context.push('/profiles'),
              );
            }
            return Column(
              children: [
                for (var index = 0; index < items.length; index++) ...[
                  _InstalledCourseCard(
                    course: items[index],
                    activeLearner: activeLearner,
                    enrolled: enrolledCourseIds.contains(items[index].id),
                    enrollmentLoading:
                        activeLearner != null && enrollmentState?.isLoading == true,
                    onEnroll: activeLearner == null
                        ? null
                        : () async {
                            try {
                              final result = await ref
                                  .read(courseInstallationServiceProvider)
                                  .enrollInstalledCourse(
                                    courseId: items[index].id,
                                    learnerId: activeLearner.id,
                                  );
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '已加入 ${activeLearner.displayName} 的学习计划：'
                                    '${result.itemCount} 个学习项',
                                  ),
                                ),
                              );
                            } on Object catch (error) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('加入课程失败：$error')),
                              );
                            }
                          },
                  ),
                  if (index != items.length - 1) const SizedBox(height: 12),
                ],
              ],
            );
          },
          loading: () => const Card(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
          error: (error, _) => Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text('无法读取本地课程库：$error'),
            ),
          ),
        ),
        const SizedBox(height: 28),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const CircleAvatar(child: Icon(Icons.school_outlined)),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'PEP 小学英语',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const Text('课程适配验证 · 内容不随代码仓库非法分发'),
                        ],
                      ),
                    ),
                    const Chip(label: Text('规划中')),
                  ],
                ),
                const SizedBox(height: 20),
                const LinearProgressIndicator(value: 0.12),
                const SizedBox(height: 10),
                const Text('课程结构、英美音元数据、Phonics、句型和活动映射正在接入。'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text('支持的学习活动', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        const Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Chip(label: Text('单词')),
            Chip(label: Text('Phonics')),
            Chip(label: Text('IPA')),
            Chip(label: Text('听写')),
            Chip(label: Text('中译英')),
            Chip(label: Text('跟读')),
            Chip(label: Text('阅读')),
            Chip(label: Text('语法')),
          ],
        ),
      ],
    );
  }
}

class _EmptyCourseLibrary extends StatelessWidget {
  const _EmptyCourseLibrary({
    required this.hasActiveLearner,
    required this.onImport,
    required this.onProfiles,
  });

  final bool hasActiveLearner;
  final VoidCallback onImport;
  final VoidCallback onProfiles;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Wrap(
          spacing: 16,
          runSpacing: 16,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '还没有已安装课程',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  const Text('可以从图片、拍照、PDF 或 GitHub 导入资料，复核后再明确安装到本地课程库。'),
                ],
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!hasActiveLearner)
                  OutlinedButton.icon(
                    onPressed: onProfiles,
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text('先建学习者'),
                  ),
                FilledButton.icon(
                  onPressed: onImport,
                  icon: const Icon(Icons.add_to_photos_outlined),
                  label: const Text('导入课程'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InstalledCourseCard extends StatelessWidget {
  const _InstalledCourseCard({
    required this.course,
    required this.activeLearner,
    required this.enrolled,
    required this.enrollmentLoading,
    required this.onEnroll,
  });

  final InstalledCourse course;
  final LearnerProfile? activeLearner;
  final bool enrolled;
  final bool enrollmentLoading;
  final Future<void> Function()? onEnroll;

  @override
  Widget build(BuildContext context) {
    final learner = activeLearner;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CircleAvatar(
              radius: 24,
              child: Icon(Icons.local_library_outlined),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(course.title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text('本地版本 v${course.currentVersion} · 内容资产独立于导入任务保存'),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Chip(label: Text('v${course.currentVersion}')),
                      if (learner == null)
                        const Chip(label: Text('设备已安装'))
                      else if (enrolled)
                        Chip(
                          avatar: const Icon(Icons.check, size: 18),
                          label: Text('已加入 ${learner.displayName}'),
                        )
                      else if (enrollmentLoading)
                        const Chip(label: Text('读取学习计划…'))
                      else
                        OutlinedButton.icon(
                          onPressed: onEnroll,
                          icon: const Icon(Icons.person_add_alt_1),
                          label: Text('加入 ${learner.displayName}'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
