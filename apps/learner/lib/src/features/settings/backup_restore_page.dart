import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/backup_service.dart';
import '../../data/providers.dart';

class BackupRestorePage extends ConsumerStatefulWidget {
  const BackupRestorePage({super.key});

  @override
  ConsumerState<BackupRestorePage> createState() => _BackupRestorePageState();
}

class _BackupRestorePageState extends ConsumerState<BackupRestorePage> {
  static const _maxBackupBytes = 64 * 1024 * 1024;

  bool _busy = false;
  String? _status;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('备份与恢复')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('本地学习数据备份', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text(
            '备份包含学习者档案、复习卡与复习事件、课程安装历史、学习者课程版本绑定，以及所有已安装历史版本的课程 manifest。',
          ),
          const SizedBox(height: 12),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.privacy_tip_outlined),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '当前备份是可移植的可读 JSON，不加密。它不会包含原始 PDF、图片或普通未完成的导入队列；请把备份文件保存在你信任的位置。',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.download_outlined),
                  title: const Text('导出完整备份'),
                  subtitle: const Text('校验所有历史课程资产后生成 .json 便携备份'),
                  trailing: _busy
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.chevron_right),
                  onTap: _busy ? null : _exportBackup,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.restore_outlined),
                  title: const Text('从备份恢复'),
                  subtitle: const Text('先完整校验，再明确确认覆盖当前本地学习状态'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _busy ? null : _importBackup,
                ),
              ],
            ),
          ),
          if (_status != null) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_status!),
              ),
            ),
          ],
          const SizedBox(height: 20),
          const Text(
            '恢复采用覆盖式语义：确认后会替换当前设备上的学习者、复习状态、课程安装历史与课程绑定，并清除普通本地导入队列。课程原始资料不会从备份中恢复。',
          ),
        ],
      ),
    );
  }

  Future<void> _exportBackup() async {
    setState(() {
      _busy = true;
      _status = '正在校验本地学习状态与历史课程资产…';
    });
    try {
      final bytes = await ref.read(verbaSeedBackupServiceProvider).exportBackup();
      if (!mounted) return;
      final now = DateTime.now().toUtc();
      final fileName =
          'verbaseed-backup-${now.year.toString().padLeft(4, '0')}'
          '${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}-'
          '${now.hour.toString().padLeft(2, '0')}'
          '${now.minute.toString().padLeft(2, '0')}.json';
      final saved = await FilePicker.saveFile(
        dialogTitle: '保存 VerbaSeed 备份',
        fileName: fileName,
        bytes: bytes,
        mimeType: 'application/json',
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      if (!mounted) return;
      setState(() {
        _status = saved == null
            ? '已取消导出。'
            : '备份导出完成，共 ${_formatBytes(bytes.length)}。';
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _status = '备份导出失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importBackup() async {
    final file = await FilePicker.pickFile(
      dialogTitle: '选择 VerbaSeed JSON 备份',
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (file == null || !mounted) return;

    setState(() {
      _busy = true;
      _status = '正在读取并校验备份…';
    });
    try {
      final knownLength = file.lengthSync() ?? await file.length();
      if (knownLength != null && knownLength > _maxBackupBytes) {
        throw const FormatException('备份文件超过 64 MiB 限制');
      }
      final bytes = await file.readAsBytes();
      if (bytes.length > _maxBackupBytes) {
        throw const FormatException('备份文件超过 64 MiB 限制');
      }
      final service = ref.read(verbaSeedBackupServiceProvider);
      final preview = service.inspectBackup(bytes);
      if (!mounted) return;
      final confirmed = await _confirmRestore(context, preview);
      if (confirmed != true || !mounted) {
        setState(() => _status = '已取消恢复；本机数据未改变。');
        return;
      }

      setState(() => _status = '备份已通过校验，正在原子替换本地学习状态…');
      final result = await service.restoreBackup(bytes);
      if (!mounted) return;
      setState(() {
        _status =
            '恢复完成：${result.preview.learnerCount} 个学习者、'
            '${result.preview.courseCount} 门课程、'
            '${result.preview.courseVersionCount} 个课程历史版本、'
            '${result.preview.reviewCardCount} 张复习卡。';
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _status = '恢复失败，本机学习状态未被部分覆盖：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _confirmRestore(
    BuildContext context,
    VerbaSeedBackupPreview preview,
  ) =>
      showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('确认覆盖本机学习状态？'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('备份时间：${_formatTime(preview.exportedAt)}'),
                const SizedBox(height: 12),
                Text('学习者：${preview.learnerCount}'),
                Text('课程：${preview.courseCount}'),
                Text('课程历史版本：${preview.courseVersionCount}'),
                Text('课程绑定：${preview.enrollmentCount}'),
                Text('复习卡：${preview.reviewCardCount}'),
                Text('复习事件：${preview.reviewEventCount}'),
                const SizedBox(height: 16),
                const Text(
                  '继续后会覆盖当前设备上的对应本地状态。恢复失败会回滚数据库事务，但已经校验并写入 Content Store 的内容寻址课程资产可能保留为未引用缓存。',
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
              child: const Text('确认恢复'),
            ),
          ],
        ),
      );
}

String _formatTime(DateTime value) {
  final local = value.toLocal();
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')} '
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

String _formatBytes(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KiB';
  return '$bytes B';
}
