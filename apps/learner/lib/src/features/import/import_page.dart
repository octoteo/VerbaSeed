import 'package:content_source/content_source.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_store/local_store.dart';

import '../../data/providers.dart';

class ImportPage extends ConsumerWidget {
  const ImportPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobs = ref.watch(importJobsProvider);
    final repository = ref.watch(importRepositoryProvider);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('创建与导入', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        const Text('所有来源先形成可追踪的本地导入任务，再进入统一 Course Compiler。'),
        const SizedBox(height: 24),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _SourceCard(
              icon: Icons.document_scanner_outlined,
              title: '拍照 / OCR',
              subtitle: 'Provider 契约已就绪，设备摄像头与 OCR 在下一增量接入',
              onTap: () => _showProviderStatus(context, '拍照 / OCR'),
            ),
            _SourceCard(
              icon: Icons.picture_as_pdf_outlined,
              title: 'PDF',
              subtitle: 'Provider 契约已就绪，PDF 字节持久化与版面解析在下一增量接入',
              onTap: () => _showProviderStatus(context, 'PDF'),
            ),
            _SourceCard(
              icon: Icons.code,
              title: 'GitHub 课程源',
              subtitle: '校验仓库地址并创建可恢复的本地导入任务',
              onTap: () => _enqueueGitHub(context, repository),
            ),
            _SourceCard(
              icon: Icons.text_snippet_outlined,
              title: '粘贴文本',
              subtitle: '立即编译为 Open Course 草稿并保存到导入队列',
              onTap: () => _compileText(context, repository),
            ),
          ],
        ),
        const SizedBox(height: 32),
        Text('本地导入队列', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        jobs.when(
          data: (items) => items.isEmpty
              ? const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('暂无导入任务。任务元数据会保存在本地 SQLite 中。'),
                  ),
                )
              : Column(
                  children: [
                    for (final job in items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Card(
                          child: ListTile(
                            leading: const Icon(Icons.inventory_2_outlined),
                            title: Text(job.displayName),
                            subtitle: Text('${job.sourceType} · ${job.status}'),
                            trailing: Text(
                              '${job.createdAt.toLocal().month}/${job.createdAt.toLocal().day}',
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
          loading: () => const LinearProgressIndicator(),
          error: (error, _) => Text('无法读取导入队列：$error'),
        ),
      ],
    );
  }

  Future<void> _enqueueGitHub(
    BuildContext context,
    ImportRepository repository,
  ) async {
    final controller = TextEditingController(text: 'https://github.com/');
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('添加 GitHub 课程源'),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '仓库地址',
              hintText: 'https://github.com/owner/repository',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('加入队列'),
          ),
        ],
      ),
    );
    if (submitted != true) return;

    try {
      final source = GitHubCourseSource.parse(controller.text).toContentSource();
      await repository.enqueue(source);
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('地址无效：$error')),
        );
      }
    }
  }

  Future<void> _compileText(
    BuildContext context,
    ImportRepository repository,
  ) async {
    final titleController = TextEditingController();
    final textController = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('把文本变成课程草稿'),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: '课程名称'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: textController,
                minLines: 6,
                maxLines: 10,
                decoration: const InputDecoration(
                  labelText: '学习文本（每行生成一个学习项）',
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('编译'),
          ),
        ],
      ),
    );
    if (submitted != true) return;

    try {
      final courseId = 'local-${DateTime.now().toUtc().microsecondsSinceEpoch}';
      final draft = const CourseDraftCompiler().compilePlainText(
        courseId: courseId,
        title: titleController.text,
        text: textController.text,
      );
      final source = ContentSource(
        type: ContentSourceType.plainText,
        displayName: draft.title,
        metadata: {
          'draftCourse': draft.toJson(),
          'itemCount': draft.units.single.lessons.single.items.length,
        },
      );
      await repository.enqueue(source);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '已生成 ${draft.units.single.lessons.single.items.length} 个学习项并保存到本地队列',
            ),
          ),
        );
      }
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('编译失败：$error')),
        );
      }
    }
  }

  void _showProviderStatus(BuildContext context, String provider) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$provider 的统一数据契约已接入；设备读取与解析器将在下一增量完成。')),
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 320,
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(child: Icon(icon)),
                const SizedBox(height: 16),
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(subtitle),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
