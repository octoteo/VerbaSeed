import 'dart:async';

import 'package:content_source/content_source.dart';
import 'package:document_processing/document_processing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_store/local_store.dart';

import '../../data/providers.dart';
import 'import_page.dart';

/// Adds automatic image OCR and a small recovery surface around [ImportPage].
///
/// The existing import page remains the single place that acquires and persists
/// source assets. This wrapper observes the durable import queue and starts OCR
/// only after the image is safely stored. Retry and interrupted-run recovery are
/// always driven from the persisted processing state, so closing the app never
/// makes the UI the owner of a job.
class OcrImportPage extends ConsumerStatefulWidget {
  const OcrImportPage({super.key});

  @override
  ConsumerState<OcrImportPage> createState() => _OcrImportPageState();
}

class _OcrImportPageState extends ConsumerState<OcrImportPage> {
  final Map<String, ImportJob> _automaticQueue = <String, ImportJob>{};
  final Set<String> _automaticAttempted = <String>{};
  bool _automaticRunnerActive = false;

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<List<ImportJob>>>(importJobsProvider, (previous, next) {
      next.whenData(_queueFreshImagesForOcr);
    });

    final jobs = ref.watch(importJobsProvider);
    final coordinator = ref.watch(documentImportCoordinatorProvider);
    final repository = ref.watch(importRepositoryProvider);

    return Column(
      children: [
        jobs.when(
          data: (items) => _OcrQueuePanel(
            jobs: items,
            repository: repository,
            available: coordinator.imageExtractionAvailable,
            onProcess: _processImageManually,
          ),
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
        ),
        const Expanded(child: ImportPage()),
      ],
    );
  }

  void _queueFreshImagesForOcr(List<ImportJob> jobs) {
    if (!mounted) return;
    final coordinator = ref.read(documentImportCoordinatorProvider);
    if (!coordinator.imageExtractionAvailable) return;

    final repository = ref.read(importRepositoryProvider);
    for (final job in jobs) {
      if (_automaticAttempted.contains(job.id)) continue;
      final source = _decodeSource(repository, job);
      if (source == null || !_isImageSource(source)) continue;

      final state = _processingState(source);
      final isFresh = state == null ||
          (state.phase == DocumentProcessingPhase.queued && state.attempt == 0);
      if (!isFresh) continue;

      _automaticAttempted.add(job.id);
      _automaticQueue[job.id] = job;
    }

    if (_automaticQueue.isNotEmpty) {
      unawaited(_drainAutomaticQueue());
    }
  }

  Future<void> _drainAutomaticQueue() async {
    if (_automaticRunnerActive) return;
    _automaticRunnerActive = true;
    try {
      while (_automaticQueue.isNotEmpty) {
        final entry = _automaticQueue.entries.first;
        _automaticQueue.remove(entry.key);
        try {
          await ref.read(documentImportCoordinatorProvider).processImage(entry.value);
        } on Object catch (error) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('本地 OCR 启动失败：$error')),
          );
        }
      }
    } finally {
      _automaticRunnerActive = false;
      if (_automaticQueue.isNotEmpty && mounted) {
        unawaited(_drainAutomaticQueue());
      }
    }
  }

  Future<void> _processImageManually(ImportJob job) async {
    try {
      final result = await ref.read(documentImportCoordinatorProvider).processImage(job);
      if (!mounted) return;
      final message = switch (result.phase) {
        DocumentProcessingPhase.succeeded => '图片 OCR 完成，识别结果已安全保存到本机',
        DocumentProcessingPhase.retryScheduled =>
          'OCR 暂未完成，已保存恢复点；到达重试时间后可再次执行',
        DocumentProcessingPhase.extracting => 'OCR 仍在处理中；若上次异常中断，将按恢复规则继续',
        DocumentProcessingPhase.failed =>
          'OCR 失败：${result.lastErrorMessage ?? result.lastErrorCode ?? '未知错误'}',
        DocumentProcessingPhase.cancelled => 'OCR 已取消',
        DocumentProcessingPhase.queued => '图片已进入 OCR 队列',
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('OCR 执行失败：$error')),
      );
    }
  }
}

class _OcrQueuePanel extends StatelessWidget {
  const _OcrQueuePanel({
    required this.jobs,
    required this.repository,
    required this.available,
    required this.onProcess,
  });

  final List<ImportJob> jobs;
  final ImportRepository repository;
  final bool available;
  final Future<void> Function(ImportJob job) onProcess;

  @override
  Widget build(BuildContext context) {
    final imageJobs = <({ImportJob job, ContentSource source})>[];
    for (final job in jobs) {
      final source = _decodeSource(repository, job);
      if (source != null && _isImageSource(source)) {
        imageJobs.add((job: job, source: source));
      }
    }
    if (imageJobs.isEmpty) return const SizedBox.shrink();

    final pendingCount = imageJobs.where((item) {
      final state = _processingState(item.source);
      return state == null || !state.isTerminal;
    }).length;
    final reviewCount = imageJobs.where(
      (item) => item.source.metadata['requiresReview'] == true,
    ).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Card(
        child: ExpansionTile(
          leading: Icon(
            available ? Icons.document_scanner_outlined : Icons.phonelink_erase_outlined,
          ),
          title: Text(available ? '本地图片 OCR 已连接' : '当前平台不提供本地图片 OCR'),
          subtitle: Text(
            available
                ? '新拍摄/导入图片会在原图落盘后自动识别；$pendingCount 个可恢复任务'
                    '${reviewCount == 0 ? '' : ' · $reviewCount 个结果需人工检查'}'
                : '图片仍会安全保存；请在 Android/iOS 设备上执行离线识别。',
          ),
          children: [
            for (final item in imageJobs.take(6))
              _OcrJobTile(
                job: item.job,
                source: item.source,
                available: available,
                onProcess: onProcess,
              ),
            if (imageJobs.length > 6)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('另有 ${imageJobs.length - 6} 个图片任务，可在下方完整导入队列查看。'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _OcrJobTile extends StatelessWidget {
  const _OcrJobTile({
    required this.job,
    required this.source,
    required this.available,
    required this.onProcess,
  });

  final ImportJob job;
  final ContentSource source;
  final bool available;
  final Future<void> Function(ImportJob job) onProcess;

  @override
  Widget build(BuildContext context) {
    final state = _processingState(source);
    final actionAvailable = available && (state == null || !state.isTerminal);
    final empty = source.metadata['ocrEmpty'] == true;
    final needsReview = source.metadata['requiresReview'] == true;

    return ListTile(
      dense: true,
      leading: Icon(_stateIcon(state, empty: empty)),
      title: Text(job.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(_stateLabel(state, empty: empty, needsReview: needsReview)),
      trailing: actionAvailable
          ? IconButton(
              tooltip: _actionTooltip(state),
              onPressed: () => onProcess(job),
              icon: Icon(_actionIcon(state)),
            )
          : null,
    );
  }

  static String _stateLabel(
    DocumentProcessingState? state, {
    required bool empty,
    required bool needsReview,
  }) {
    if (state == null) return '等待 OCR';
    return switch (state.phase) {
      DocumentProcessingPhase.queued => '等待 OCR',
      DocumentProcessingPhase.extracting => '正在离线识别',
      DocumentProcessingPhase.retryScheduled =>
        '等待恢复 · 已尝试 ${state.attempt}/${state.maxAttempts}',
      DocumentProcessingPhase.succeeded when empty || needsReview => '识别完成，但未检测到文本，需要人工检查',
      DocumentProcessingPhase.succeeded => '识别完成',
      DocumentProcessingPhase.failed =>
        '失败：${state.lastErrorMessage ?? state.lastErrorCode ?? '未知错误'}',
      DocumentProcessingPhase.cancelled => '已取消',
    };
  }

  static IconData _stateIcon(DocumentProcessingState? state, {required bool empty}) {
    if (state == null) return Icons.schedule_outlined;
    return switch (state.phase) {
      DocumentProcessingPhase.queued => Icons.schedule_outlined,
      DocumentProcessingPhase.extracting => Icons.sync,
      DocumentProcessingPhase.retryScheduled => Icons.restore,
      DocumentProcessingPhase.succeeded when empty => Icons.rate_review_outlined,
      DocumentProcessingPhase.succeeded => Icons.check_circle_outline,
      DocumentProcessingPhase.failed => Icons.error_outline,
      DocumentProcessingPhase.cancelled => Icons.cancel_outlined,
    };
  }

  static IconData _actionIcon(DocumentProcessingState? state) =>
      switch (state?.phase) {
        DocumentProcessingPhase.retryScheduled => Icons.refresh,
        DocumentProcessingPhase.extracting => Icons.restore,
        _ => Icons.play_arrow,
      };

  static String _actionTooltip(DocumentProcessingState? state) =>
      switch (state?.phase) {
        DocumentProcessingPhase.retryScheduled => '重试本地 OCR',
        DocumentProcessingPhase.extracting => '检查并恢复 OCR',
        _ => '开始本地 OCR',
      };
}

ContentSource? _decodeSource(ImportRepository repository, ImportJob job) {
  try {
    return repository.decodeSource(job);
  } on Object {
    return null;
  }
}

bool _isImageSource(ContentSource source) =>
    source.type == ContentSourceType.image ||
    source.type == ContentSourceType.cameraImage;

DocumentProcessingState? _processingState(ContentSource source) {
  try {
    return documentProcessingStateFromMetadata(source.metadata);
  } on Object {
    return null;
  }
}
