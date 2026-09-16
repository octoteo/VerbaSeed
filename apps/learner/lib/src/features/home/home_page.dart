import 'package:flutter/material.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 12,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('早上好 👋', style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 6),
                Text('今天继续一点点，让英语真正长在脑子里。', style: Theme.of(context).textTheme.bodyLarge),
              ],
            ),
            FilledButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.play_arrow),
              label: const Text('继续今日学习'),
            ),
          ],
        ),
        const SizedBox(height: 28),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 980 ? 3 : constraints.maxWidth >= 620 ? 2 : 1;
            final width = (constraints.maxWidth - (columns - 1) * 16) / columns;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _MetricCard(width: width, icon: Icons.local_fire_department_outlined, title: '连续学习', value: '3 天', caption: '保持节奏比一次学很久更重要'),
                _MetricCard(width: width, icon: Icons.refresh, title: '今日复习', value: '12', caption: '由 FSRS 安排的到期内容'),
                _MetricCard(width: width, icon: Icons.psychology_outlined, title: '掌握度', value: '68%', caption: '基于单词、句型、听说表现综合估计'),
              ],
            );
          },
        ),
        const SizedBox(height: 28),
        Text('今天的学习路径', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 14),
        const _TaskCard(
          icon: Icons.hearing,
          title: '听音辨词',
          subtitle: '5 分钟 · 8 个词',
          progress: 0.25,
        ),
        const SizedBox(height: 12),
        const _TaskCard(
          icon: Icons.record_voice_over_outlined,
          title: 'Phonics · sh / ee',
          subtitle: '6 分钟 · 发音与拼读',
          progress: 0,
        ),
        const SizedBox(height: 12),
        const _TaskCard(
          icon: Icons.keyboard_alt_outlined,
          title: '句子输入',
          subtitle: '8 分钟 · 中译英 + 拼写',
          progress: 0,
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.width, required this.icon, required this.title, required this.value, required this.caption});

  final double width;
  final IconData icon;
  final String title;
  final String value;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon),
              const SizedBox(height: 18),
              Text(title, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              Text(value, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(caption),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.icon, required this.title, required this.subtitle, required this.progress});

  final IconData icon;
  final String title;
  final String subtitle;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () {},
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              CircleAvatar(radius: 24, child: Icon(icon)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(subtitle),
                    const SizedBox(height: 12),
                    LinearProgressIndicator(value: progress),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
