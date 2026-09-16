import 'package:flutter/material.dart';

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
              const ListTile(
                leading: Icon(Icons.person_outline),
                title: Text('学习者档案'),
                subtitle: Text('本地优先 · 支持一个设备多个学习者'),
                trailing: Icon(Icons.chevron_right),
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
                subtitle: Text('核心学习不需要账号或云服务'),
                trailing: Icon(Icons.chevron_right),
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
                Text('VerbaSeed 0.1.0', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                const Text('AGPL-3.0 · Local-first · Open Course Protocol'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
