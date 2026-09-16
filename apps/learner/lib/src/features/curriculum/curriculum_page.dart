import 'package:flutter/material.dart';

class CurriculumPage extends StatelessWidget {
  const CurriculumPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('教材世界', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        const Text('首批以中国小学英语课程作为适配验证，同时保持课程协议与出版社无关。'),
        const SizedBox(height: 24),
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
                          Text('PEP 小学英语', style: Theme.of(context).textTheme.titleLarge),
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
