import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_store/local_store.dart';

import '../../data/providers.dart';

class ProfilesPage extends ConsumerWidget {
  const ProfilesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profiles = ref.watch(learnerProfilesProvider);
    final repository = ref.watch(learnerRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('学习者档案')),
      body: profiles.when(
        data: (items) => items.isEmpty
            ? const _EmptyProfiles()
            : ListView.separated(
                padding: const EdgeInsets.all(24),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final profile = items[index];
                  return Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      leading: CircleAvatar(
                        child: Text(profile.displayName.characters.first.toUpperCase()),
                      ),
                      title: Text(profile.displayName),
                      subtitle: Text(
                        profile.birthYear == null
                            ? '${profile.nativeLanguage} → ${profile.targetLanguage}'
                            : '${profile.birthYear} 年出生 · ${profile.nativeLanguage} → ${profile.targetLanguage}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (profile.isActive)
                            const Chip(label: Text('当前'))
                          else
                            TextButton(
                              onPressed: () => repository.setActive(profile.id),
                              child: const Text('切换'),
                            ),
                          IconButton(
                            tooltip: '删除档案',
                            onPressed: () => _confirmDelete(
                              context,
                              repository,
                              profile.id,
                              profile.displayName,
                            ),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                      onTap: profile.isActive
                          ? null
                          : () => repository.setActive(profile.id),
                    ),
                  );
                },
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('无法读取本地档案：$error')),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createProfile(context, repository),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('新建档案'),
      ),
    );
  }

  Future<void> _createProfile(
    BuildContext context,
    LearnerRepository repository,
  ) async {
    final nameController = TextEditingController();
    final yearController = TextEditingController();
    var accent = 'curriculum';

    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('新建学习者'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: '昵称'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: yearController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '出生年份（可选）'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: accent,
                  decoration: const InputDecoration(labelText: '默认发音'),
                  items: const [
                    DropdownMenuItem(value: 'curriculum', child: Text('跟随课程')),
                    DropdownMenuItem(value: 'british', child: Text('英音')),
                    DropdownMenuItem(value: 'american', child: Text('美音')),
                  ],
                  onChanged: (value) => setState(() => accent = value ?? accent),
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
              child: const Text('创建'),
            ),
          ],
        ),
      ),
    );

    if (submitted != true) return;
    final birthYear = int.tryParse(yearController.text.trim());
    try {
      await repository.createProfile(
        displayName: nameController.text,
        birthYear: birthYear,
        preferredAccent: accent,
        makeActive: true,
      );
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('创建失败：$error')),
        );
      }
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    LearnerRepository repository,
    String id,
    String name,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除本地档案？'),
        content: Text('将同时删除 $name 的本地复习状态与学习事件。此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await repository.deleteProfile(id);
    }
  }
}

class _EmptyProfiles extends StatelessWidget {
  const _EmptyProfiles();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.family_restroom, size: 56),
            const SizedBox(height: 16),
            Text('还没有学习者档案', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text('档案、复习记录和导入任务默认只保存在当前设备。'),
          ],
        ),
      ),
    );
  }
}
