import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:content_source/content_source.dart';
import 'package:content_store/content_store.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_store/local_store.dart';
import 'package:mime/mime.dart';

import '../../data/providers.dart';
import 'camera_capture_page.dart';

class ImportPage extends ConsumerWidget {
  const ImportPage({super.key});

  static const _maxPdfBytes = 100 * 1024 * 1024;
  static const _maxImageBytes = 30 * 1024 * 1024;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobs = ref.watch(importJobsProvider);
    final repository = ref.watch(importRepositoryProvider);
    final assetStore = ref.watch(contentAssetStoreProvider);
    final githubClient = ref.watch(githubCourseClientProvider);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('创建与导入', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        const Text('原始文件与学习状态默认保存在本机；GitHub 课程会固定到解析出的 commit，避免远端内容悄悄变化。'),
        const SizedBox(height: 24),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _SourceCard(
              icon: Icons.camera_alt_outlined,
              title: '拍照导入',
              subtitle: '调用设备摄像头，原图按 SHA-256 内容寻址保存到本地',
              onTap: () => _captureImage(context, assetStore, repository),
            ),
            _SourceCard(
              icon: Icons.image_outlined,
              title: '图片 / OCR',
              subtitle: '选择 JPG、PNG、WebP；本轮完成安全持久化，OCR 解析进入下一处理阶段',
              onTap: () => _pickImage(context, assetStore, repository),
            ),
            _SourceCard(
              icon: Icons.picture_as_pdf_outlined,
              title: 'PDF',
              subtitle: '选择 PDF 并持久化原文件，随后由版面/OCR 管线解析',
              onTap: () => _pickPdf(context, assetStore, repository),
            ),
            _SourceCard(
              icon: Icons.code,
              title: 'GitHub 课程源',
              subtitle: '解析 ref → commit SHA，下载并校验 course.json 后固定版本',
              onTap: () => _importGitHub(context, repository, githubClient),
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
                    child: Text('暂无导入任务。任务元数据会保存在本地 SQLite 中，原始大文件保存到独立 Content Store。'),
                  ),
                )
              : Column(
                  children: [
                    for (final job in items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Card(
                          child: ListTile(
                            leading: Icon(_statusIcon(job.status)),
                            title: Text(job.displayName),
                            subtitle: Text(
                              '${job.sourceType} · ${_statusLabel(job.status)}'
                              '${job.errorMessage == null ? '' : '\n${job.errorMessage}'}',
                            ),
                            isThreeLine: job.errorMessage != null,
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

  Future<void> _captureImage(
    BuildContext context,
    ContentAssetStore assetStore,
    ImportRepository repository,
  ) async {
    final file = await Navigator.of(context).push<XFile>(
      MaterialPageRoute(builder: (_) => const CameraCapturePage()),
    );
    if (file == null || !context.mounted) return;
    try {
      final bytes = await file.readAsBytes();
      await _persistAsset(
        context: context,
        assetStore: assetStore,
        repository: repository,
        bytes: bytes,
        fileName: file.name.isEmpty ? 'camera-${DateTime.now().millisecondsSinceEpoch}.jpg' : file.name,
        mimeType: file.mimeType ?? 'image/jpeg',
        sourceType: ContentSourceType.cameraImage,
        maxBytes: _maxImageBytes,
      );
    } on Object catch (error) {
      if (context.mounted) _showError(context, '拍照导入失败', error);
    }
  }

  Future<void> _pickImage(
    BuildContext context,
    ContentAssetStore assetStore,
    ImportRepository repository,
  ) async {
    final file = await FilePicker.pickFile(
      dialogTitle: '选择教材图片',
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
    );
    if (file == null || !context.mounted) return;
    await _persistPickedFile(
      context: context,
      assetStore: assetStore,
      repository: repository,
      file: file,
      sourceType: ContentSourceType.image,
      maxBytes: _maxImageBytes,
      fallbackMime: 'image/jpeg',
    );
  }

  Future<void> _pickPdf(
    BuildContext context,
    ContentAssetStore assetStore,
    ImportRepository repository,
  ) async {
    final file = await FilePicker.pickFile(
      dialogTitle: '选择教材 PDF',
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    if (file == null || !context.mounted) return;
    await _persistPickedFile(
      context: context,
      assetStore: assetStore,
      repository: repository,
      file: file,
      sourceType: ContentSourceType.pdf,
      maxBytes: _maxPdfBytes,
      fallbackMime: 'application/pdf',
    );
  }

  Future<void> _persistPickedFile({
    required BuildContext context,
    required ContentAssetStore assetStore,
    required ImportRepository repository,
    required PlatformFile file,
    required ContentSourceType sourceType,
    required int maxBytes,
    required String fallbackMime,
  }) async {
    try {
      final knownLength = file.lengthSync() ?? await file.length();
      if (knownLength != null && knownLength > maxBytes) {
        throw FormatException('文件超过 ${maxBytes ~/ (1024 * 1024)} MiB 限制');
      }
      final bytes = await file.readAsBytes();
      final mimeType = lookupMimeType(
            file.name,
            headerBytes: bytes.take(32).toList(growable: false),
          ) ??
          fallbackMime;
      await _persistAsset(
        context: context,
        assetStore: assetStore,
        repository: repository,
        bytes: bytes,
        fileName: file.name,
        mimeType: mimeType,
        sourceType: sourceType,
        maxBytes: maxBytes,
      );
    } on Object catch (error) {
      if (context.mounted) _showError(context, '文件导入失败', error);
    }
  }

  Future<void> _persistAsset({
    required BuildContext context,
    required ContentAssetStore assetStore,
    required ImportRepository repository,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    required ContentSourceType sourceType,
    required int maxBytes,
  }) async {
    if (bytes.isEmpty) throw const FormatException('文件为空');
    if (bytes.length > maxBytes) {
      throw FormatException('文件超过 ${maxBytes ~/ (1024 * 1024)} MiB 限制');
    }
    final asset = await assetStore.put(
      bytes: bytes,
      fileName: fileName,
      mimeType: mimeType,
    );
    final source = ContentSource(
      type: sourceType,
      displayName: asset.fileName,
      metadata: {
        'asset': asset.toJson(),
        'pipeline': 'pending-document-extraction',
      },
    );
    await repository.enqueue(source);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已保存 ${asset.fileName}（${_formatBytes(asset.byteLength)}），等待内容解析')),
      );
    }
  }

  Future<void> _importGitHub(
    BuildContext context,
    ImportRepository repository,
    GitHubCourseClient githubClient,
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
            child: const Text('校验并导入'),
          ),
        ],
      ),
    );
    if (submitted != true) return;

    String? jobId;
    try {
      final githubSource = GitHubCourseSource.parse(controller.text);
      final source = githubSource.toContentSource();
      jobId = await repository.enqueue(source);
      await repository.updateStatus(jobId, ImportJobState.processing);
      final snapshot = await githubClient.fetch(githubSource);
      final resolved = source.copyWith(metadata: snapshot.toMetadata());
      await repository.replaceSource(
        jobId,
        resolved,
        state: ImportJobState.ready,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已导入 ${snapshot.course.title}，固定到 ${snapshot.commitSha.substring(0, 8)}')),
        );
      }
    } on Object catch (error) {
      if (jobId != null) {
        await repository.updateStatus(
          jobId,
          ImportJobState.failed,
          errorMessage: '$error',
        );
      }
      if (context.mounted) _showError(context, 'GitHub 课程导入失败', error);
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
      final id = await repository.enqueue(source);
      await repository.updateStatus(id, ImportJobState.ready);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '已生成 ${draft.units.single.lessons.single.items.length} 个学习项',
            ),
          ),
        );
      }
    } on Object catch (error) {
      if (context.mounted) _showError(context, '编译失败', error);
    }
  }

  void _showError(BuildContext context, String title, Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$title：$error')),
    );
  }

  static String _statusLabel(String value) => switch (value) {
        'queued' => '等待解析',
        'processing' => '处理中',
        'ready' => '可用',
        'failed' => '失败',
        'cancelled' => '已取消',
        _ => value,
      };

  static IconData _statusIcon(String value) => switch (value) {
        'processing' => Icons.sync,
        'ready' => Icons.check_circle_outline,
        'failed' => Icons.error_outline,
        'cancelled' => Icons.cancel_outlined,
        _ => Icons.schedule_outlined,
      };

  static String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KiB';
    return '$bytes B';
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
