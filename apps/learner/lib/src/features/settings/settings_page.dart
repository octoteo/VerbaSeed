import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('设置', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 20),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: const Text('学习者档案'),
                subtitle: const Text('本地优先 · 支持一个设备多个学习者'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/profiles'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.sync_outlined),
                title: const Text('GitHub 课程与更新'),
                subtitle: const Text('手动检查、预览和升级；历史版本可随时回滚'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/settings/github-courses'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.backup_outlined),
                title: const Text('备份与恢复'),
                subtitle: const Text('导出学习状态与课程历史 manifest；校验后可覆盖式恢复'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/settings/backup-restore'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.record_voice_over_outlined),
                title: const Text('默认发音'),
                subtitle: const Text('跟随课程（支持英音 / 美音）'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {},
              ),
              const Divider(height: 1),
              const ListTile(
                leading: Icon(Icons.cloud_off_outlined),
                title: Text('离线与隐私'),
                subtitle: Text('学习者、复习状态与导入任务默认保存在设备本地'),
                trailing: Icon(Icons.verified_user_outlined),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('VerbaSeed 0.2.13', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                const Text('AGPL-3.0 · Local-first · Drift/SQLite · Open Course Protocol'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
