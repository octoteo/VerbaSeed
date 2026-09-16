import 'package:content_source/content_source.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:local_store/local_store.dart';

import '../../data/github_course_sync_service.dart';
import '../../data/providers.dart';

class GitHubCourseUpdatesPage extends ConsumerWidget {
  const GitHubCourseUpdatesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobsState = ref.watch(importJobsProvider);
    final coursesState = ref.watch(installedCoursesProvider);
    final syncService = ref.watch(githubCourseSyncServiceProvider);

    if (jobsState.isLoading || coursesState.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (jobsState.hasError) {
      return _ErrorView(message: '无法读取 GitHub 导入来源：${jobsState.error}');
    }
    if (coursesState.hasError) {
      return _ErrorView(message: '无法读取本地课程库：${coursesState.error}');
    }

    final jobs = jobsState.asData?.value ?? const <ImportJob>[];
    final courses = coursesState.asData?.value ?? const <InstalledCourse>[];
    final jobsById = <String, ImportJob>{for (final job in jobs) job.id: job};

    final pending = <({ImportJob job, GitHubCourseSnapshot snapshot})>[];
    for (final job in jobs) {
      final snapshot = syncService.importSnapshot(job);
      if (snapshot != null) pending.add((job: job, snapshot: snapshot));
    }

    final tracked =
        <({InstalledCourse course, GitHubCourseTracking tracking})>[];
    final trackingErrors = <String>[];
    for (final course in courses) {
      try {
        final sourceJob = course.sourceJobId == null
            ? null
            : jobsById[course.sourceJobId!];
        final tracking = syncService.trackingForLocal(
          course: course,
          sourceJob: sourceJob,
        );
        if (tracking != null) {
          tracked.add((course: course, tracking: tracking));
        }
      } on Object catch (error) {
        trackingErrors.add('${course.title}：$error');
      }
    }

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('GitHub 课程与更新', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        const Text(
          'VerbaSeed 只会在你点击“检查更新”时访问 GitHub。检查会固定到一个明确的 commit；'
          '确认升级后安装的就是刚刚预览的那个快照，不会自动追随随后发生的分支变化。',
        ),
        const SizedBox(height: 8),
        const Text(
          '升级只改变设备默认课程版本。已经开始学习的档案继续固定在原版本；需要回滚时可回到“教材世界”选择历史版本。',
        ),
        if (trackingErrors.isNotEmpty) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('部分 GitHub 来源元数据无法读取：\n${trackingErrors.join('\n')}'),
            ),
          ),
        ],
        if (pending.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('待安装 GitHub 快照', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          const Text('这些课程已经过结构校验并固定到 commit，但还没有写入设备课程库。'),
          const SizedBox(height: 12),
          for (final entry in pending) ...[
            _PendingGitHubCourseCard(
              job: entry.job,
              snapshot: entry.snapshot,
            ),
            const SizedBox(height: 12),
          ],
        ],
        if (tracked.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('已安装 GitHub 课程', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          for (final entry in tracked) ...[
            _InstalledGitHubCourseCard(
              course: entry.course,
              tracking: entry.tracking,
            ),
            const SizedBox(height: 12),
          ],
        ],
        if (pending.isEmpty && tracked.isEmpty) ...[
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('还没有可管理的 GitHub 课程。'),
                  const SizedBox(height: 8),
                  const Text('先从“创建与导入”添加 GitHub 仓库，VerbaSeed 会把 course.json 固定到解析出的 commit。'),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => context.go('/import'),
                    icon: const Icon(Icons.add_link),
                    label: const Text('去添加 GitHub 课程'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _PendingGitHubCourseCard extends ConsumerStatefulWidget {
  const _PendingGitHubCourseCard({
    required this.job,
    required this.snapshot,
  });

  final ImportJob job;
  final GitHubCourseSnapshot snapshot;

  @override
  ConsumerState<_PendingGitHubCourseCard> createState() =>
      _PendingGitHubCourseCardState();
}

class _PendingGitHubCourseCardState
    extends ConsumerState<_PendingGitHubCourseCard> {
  bool _installing = false;

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(snapshot.course.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              '${snapshot.source.owner}/${snapshot.source.repository}@${snapshot.source.ref} · '
              '${snapshot.commitSha.substring(0, 8)}',
            ),
            const SizedBox(height: 12),
            const Text('安装只会把这个不可变快照加入设备课程库，不会自动加入任何学习者的复习计划。'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _installing ? null : _install,
              icon: _installing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_done_outlined),
              label: Text(_installing ? '正在安装…' : '安装到设备'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _install() async {
    setState(() => _installing = true);
    try {
      final result = await ref
          .read(githubCourseSyncServiceProvider)
          .installImportedCourse(widget.job.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.reusedVersion
                ? '课程内容与已有历史版本一致，已复用 v${result.version}'
                : '课程已安装为设备版本 v${result.version}',
          ),
          action: SnackBarAction(
            label: '教材世界',
            onPressed: () => context.go('/curriculum'),
          ),
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('GitHub 课程安装失败：$error')),
      );
    } finally {
      if (mounted) setState(() => _installing = false);
    }
  }
}

class _InstalledGitHubCourseCard extends ConsumerStatefulWidget {
  const _InstalledGitHubCourseCard({
    required this.course,
    required this.tracking,
  });

  final InstalledCourse course;
  final GitHubCourseTracking tracking;

  @override
  ConsumerState<_InstalledGitHubCourseCard> createState() =>
      _InstalledGitHubCourseCardState();
}

class _InstalledGitHubCourseCardState
    extends ConsumerState<_InstalledGitHubCourseCard> {
  GitHubCourseUpdatePreview? _preview;
  bool _checking = false;
  bool _applying = false;

  @override
  void didUpdateWidget(covariant _InstalledGitHubCourseCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tracking.key != widget.tracking.key) {
      _preview = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tracking = widget.tracking;
    final preview = _preview;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.course.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              '${tracking.source.owner}/${tracking.source.repository}@${tracking.source.ref} · '
              '设备 v${tracking.installedVersion} · ${tracking.commitSha.substring(0, 8)}',
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: _checking || _applying ? null : _check,
                  icon: _checking
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync_outlined),
                  label: Text(_checking ? '正在检查…' : '检查 GitHub 更新'),
                ),
                OutlinedButton.icon(
                  onPressed: () => context.go('/curriculum'),
                  icon: const Icon(Icons.history),
                  label: const Text('版本与回滚'),
                ),
              ],
            ),
            if (preview != null) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              Text('发现新快照', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              Text(
                '${tracking.commitSha.substring(0, 8)} → '
                '${preview.snapshot.commitSha.substring(0, 8)} · '
                '${preview.lessonCount} 课节 · ${preview.itemCount} 项',
              ),
              if (preview.snapshot.course.title != widget.course.title) ...[
                const SizedBox(height: 4),
                Text('新标题：${preview.snapshot.course.title}'),
              ],
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _applying ? null : _confirmAndApply,
                icon: _applying
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.system_update_alt_outlined),
                label: Text(_applying ? '正在升级…' : '升级设备默认版本'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    try {
      final preview = await ref
          .read(githubCourseSyncServiceProvider)
          .checkForUpdate(widget.tracking);
      if (!mounted) return;
      if (preview == null) {
        setState(() => _preview = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '已是 ${widget.tracking.source.ref} 的最新 commit '
              '${widget.tracking.commitSha.substring(0, 8)}',
            ),
          ),
        );
      } else {
        setState(() => _preview = preview);
      }
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('检查 GitHub 更新失败：$error')),
      );
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _confirmAndApply() async {
    final preview = _preview;
    if (preview == null) return;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('升级设备默认课程版本？'),
            content: Text(
              '将安装已预览的 commit ${preview.snapshot.commitSha.substring(0, 8)}。\n\n'
              '现有学习者继续固定在各自当前课程版本，不会静默重建复习计划；'
              '历史版本仍可从“教材世界”回滚。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('确认升级'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    setState(() => _applying = true);
    try {
      final result = await ref
          .read(githubCourseSyncServiceProvider)
          .applyUpdate(preview);
      if (!mounted) return;
      setState(() => _preview = null);
      final message = result.reusedVersion
          ? '远端 commit 已更新；内容与历史版本一致，设备继续使用 v${result.version}'
          : '设备默认课程已升级到 v${result.version} · ${result.commitSha.substring(0, 8)}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$message；现有学习者版本保持不变')),
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('GitHub 课程升级失败：$error')),
      );
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(message),
          ),
        ),
      );
}
