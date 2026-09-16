import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:content_source/content_source.dart';
import 'package:content_store/content_store.dart';
import 'package:document_processing/document_processing.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_store/local_store.dart';
import 'package:mime/mime.dart';

import '../../data/document_import_coordinator.dart';
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
    final documentCoordinator = ref.watch(documentImportCoordinatorProvider);

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
              subtitle: '选择 JPG、PNG、WebP；原图持久化后进入可恢复的文档解析队列',
              onTap: () => _pickImage(context, assetStore, repository),
            ),
            _SourceCard(
              icon: Icons.picture_as_pdf_outlined,
              title: 'PDF',
              subtitle: '选择 PDF 并持久化原文件，可按页范围提取本地文本与版面',
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
                      _buildJobCard(
                        context,
                        job,
                        repository,
                        documentCoordinator,
                      ),
                  ],
                ),
          loading: () => const LinearProgressIndicator(),
          error: (error, _) => Text('无法读取导入队列：$error'),
        ),
      ],
    );
  }

  Widget _buildJobCard(
    BuildContext context,
    ImportJob job,
    ImportRepository repository,
    DocumentImportCoordinator documentCoordinator,
  ) {
    final source = repository.decodeSource(job);
    final processingState = _documentProcessingState(source);
    final showPdfAction = source.type == ContentSourceType.pdf &&
        (processingState == null || !processingState.isTerminal);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: ListTile(
          leading: Icon(_statusIcon(job.status)),
          title: Text(job.displayName),
          subtitle: Text(
            '${job.sourceType} · ${_statusLabel(job.status)}'
            '${_documentProcessingLabel(source)}'
            '${job.errorMessage == null ? '' : '\n${job.errorMessage}'}',
          ),
          isThreeLine: job.errorMessage != null || processingState != null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${job.createdAt.toLocal().month}/${job.createdAt.toLocal().day}',
              ),
              if (showPdfAction) ...[
                const SizedBox(width: 4),
                IconButton(
                  tooltip: _pdfActionTooltip(processingState),
                  onPressed: () => _processPdf(
                    context,
                    job,
                    source,
                    processingState,
                    documentCoordinator,
                  ),
                  icon: Icon(_pdfActionIcon(processingState)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _processPdf(
    BuildContext context,
    ImportJob job,
    ContentSource source,
    DocumentProcessingState? processingState,
    DocumentImportCoordinator coordinator,
  ) async {
    PageRange? pageRange;
    var replacePageRange = false;
    if (processingState == null ||
        (processingState.phase == DocumentProcessingPhase.queued &&
            processingState.attempt == 0)) {
      final selection = await _selectPageRange(
        context,
        existing: _pageRangeFromSource(source),
      );
      if (selection == null || !context.mounted) return;
      pageRange = selection.range;
      replacePageRange = true;
    }

    try {
      final result = await coordinator.processPdf(
        job,
        pageRange: pageRange,
        replacePageRange: replacePageRange,
      );
      if (!context.mounted) return;
      final message = switch (result.phase) {
        DocumentProcessingPhase.succeeded => 'PDF 文本与版面解析完成，结果已安全保存到本机',
        DocumentProcessingPhase.retryScheduled =>
          '本次解析未完成，将在 ${_formatRetryTime(result.nextAttemptAt)} 后允许重试',
        DocumentProcessingPhase.extracting => '解析任务仍在处理中；异常中断后会按超时规则恢复',
        DocumentProcessingPhase.failed =>
          'PDF 解析失败：${result.lastErrorMessage ?? result.lastErrorCode ?? '未知错误'}',
        DocumentProcessingPhase.cancelled => 'PDF 解析已取消',
        DocumentProcessingPhase.queued => 'PDF 已进入解析队列',
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } on Object catch (error) {
      if (context.mounted) _showError(context, 'PDF 解析失败', error);
    }
  }

  Future<_PageRangeSelection?> _selectPageRange(
    BuildContext context, {
    PageRange? existing,
  }) async {
    final startController = TextEditingController(
      text: existing?.startPage.toString() ?? '',
    );
    final endController = TextEditingController(
      text: existing?.endPage.toString() ?? '',
    );
    String? validationError;

    final selection = await showDialog<_PageRangeSelection>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('选择 PDF 解析范围'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('留空并选择“全部页面”，或输入起止页码。页码从 1 开始。'),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: startController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: '起始页'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: endController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: '结束页'),
                      ),
                    ),
                  ],
                ),
                if (validationError != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    validationError!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                const _PageRangeSelection(range: null),
              ),
              child: const Text('全部页面'),
            ),
            FilledButton(
              onPressed: () {
                final start = int.tryParse(startController.text.trim());
                final end = int.tryParse(endController.text.trim());
                if (start == null || end == null || start < 1 || end < start) {
                  setState(() {
                    validationError = '请输入有效页码，并确保结束页不小于起始页。';
                  });
                  return;
                }
                Navigator.pop(
                  dialogContext,
                  _PageRangeSelection(
                    range: PageRange(startPage: start, endPage: end),
                  ),
                );
              },
              child: const Text('解析所选页面'),
            ),
          ],
        ),
      ),
    );

    startController.dispose();
    endController.dispose();
    return selection;
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
      if (!context.mounted) return;
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
      if (!context.mounted) return;
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
    final processingState = DocumentRetryStateMachine().initial(
      at: DateTime.now().toUtc(),
    );
    final source = ContentSource(
      type: sourceType,
      displayName: asset.fileName,
      metadata: withDocumentProcessingState(
        {
          'asset': asset.toJson(),
          'pipeline': 'document-extraction-v1',
        },
        processingState,
      ),
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

  static DocumentProcessingState? _documentProcessingState(
    ContentSource source,
  ) {
    try {
      return documentProcessingStateFromMetadata(source.metadata);
    } on Object {
      return null;
    }
  }

  static PageRange? _pageRangeFromSource(ContentSource source) {
    final raw = source.metadata['pageRange'];
    if (raw is! Map) return null;
    try {
      return PageRange.fromJson(Map<String, Object?>.from(raw));
    } on Object {
      return null;
    }
  }

  static String _documentProcessingLabel(ContentSource source) {
    final raw = source.metadata[documentProcessingMetadataKey];
    if (raw == null) return '';
    try {
      final state = documentProcessingStateFromMetadata(source.metadata)!;
      final requiresOcr = source.metadata['requiresOcr'] == true;
      final range = _pageRangeFromSource(source);
      final rangeText = range == null ? '' : ' · 页 ${range.startPage}-${range.endPage}';
      final label = switch (state.phase) {
        DocumentProcessingPhase.queued => '待处理$rangeText',
        DocumentProcessingPhase.extracting =>
          '处理中（${state.attempt}/${state.maxAttempts}）$rangeText',
        DocumentProcessingPhase.retryScheduled =>
          '等待重试（已尝试 ${state.attempt}/${state.maxAttempts}）$rangeText',
        DocumentProcessingPhase.succeeded when requiresOcr =>
          '文本层为空，等待 OCR$rangeText',
        DocumentProcessingPhase.succeeded => '已完成$rangeText',
        DocumentProcessingPhase.failed =>
          '失败：${state.lastErrorMessage ?? state.lastErrorCode ?? '未知错误'}$rangeText',
        DocumentProcessingPhase.cancelled => '已取消$rangeText',
      };
      return '\n文档解析：$label';
    } on Object catch (error) {
      return '\n文档解析：状态无效（$error）';
    }
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

  static IconData _pdfActionIcon(DocumentProcessingState? state) =>
      switch (state?.phase) {
        DocumentProcessingPhase.retryScheduled => Icons.refresh,
        DocumentProcessingPhase.extracting => Icons.restore,
        _ => Icons.play_arrow,
      };

  static String _pdfActionTooltip(DocumentProcessingState? state) =>
      switch (state?.phase) {
        DocumentProcessingPhase.retryScheduled => '重试 PDF 解析',
        DocumentProcessingPhase.extracting => '检查并恢复解析任务',
        _ => '解析 PDF 文本与版面',
      };

  static String _formatRetryTime(DateTime? value) {
    if (value == null) return '稍后';
    final local = value.toLocal();
    final minute = local.minute.toString().padLeft(2, '0');
    final second = local.second.toString().padLeft(2, '0');
    return '${local.hour}:$minute:$second';
  }

  static String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KiB';
    return '$bytes B';
  }
}

final class _PageRangeSelection {
  const _PageRangeSelection({required this.range});

  final PageRange? range;
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
