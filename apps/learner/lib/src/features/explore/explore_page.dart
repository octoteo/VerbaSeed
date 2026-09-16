import 'package:flutter/material.dart';

class ExplorePage extends StatelessWidget {
  const ExplorePage({super.key});

  @override
  Widget build(BuildContext context) {
    const paths = [
      ('动画启蒙', '从可理解输入开始，让高频表达自然重复出现', Icons.ondemand_video_outlined),
      ('Phonics', '音素意识、字母音、拼读和可解码阅读', Icons.graphic_eq),
      ('绘本阅读', '边听边读，逐步建立词汇和句型理解', Icons.menu_book_outlined),
      ('听说训练', '跟读、复述、角色扮演和发音反馈', Icons.record_voice_over_outlined),
    ];

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('启蒙世界', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        const Text('3–6 岁优先听、看、说和拼读；IPA 数据在底层保留，但不会强迫幼儿记符号。'),
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (context, constraints) {
            final itemWidth = constraints.maxWidth >= 900
                ? (constraints.maxWidth - 16) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: paths
                  .map((item) => SizedBox(
                        width: itemWidth,
                        child: Card(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(24),
                            onTap: () {},
                            child: Padding(
                              padding: const EdgeInsets.all(22),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CircleAvatar(radius: 26, child: Icon(item.$3)),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(item.$1, style: Theme.of(context).textTheme.titleLarge),
                                        const SizedBox(height: 8),
                                        Text(item.$2),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.arrow_forward),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ))
                  .toList(),
            );
          },
        ),
      ],
    );
  }
}
