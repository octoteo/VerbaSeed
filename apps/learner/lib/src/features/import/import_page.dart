import 'package:flutter/material.dart';

class ImportPage extends StatelessWidget {
  const ImportPage({super.key});

  @override
  Widget build(BuildContext context) {
    const sources = [
      ('拍照 / OCR', '拍摄课本或练习页，生成结构化课程草稿', Icons.document_scanner_outlined),
      ('PDF', '导入本地 PDF，识别章节、单词、句子和图片', Icons.picture_as_pdf_outlined),
      ('GitHub 课程源', '安装兼容 Open Course Schema 的课程仓库', Icons.code),
      ('网页 / 字幕', '把网页、视频字幕或文本转成学习材料', Icons.language),
    ];

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('创建与导入', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        const Text('所有来源最终都会进入同一个 Course Compiler，再转换成统一课程模型。'),
        const SizedBox(height: 24),
        ...sources.map(
          (source) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                leading: CircleAvatar(child: Icon(source.$3)),
                title: Text(source.$1),
                subtitle: Text(source.$2),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${source.$1} 将在内容编译器阶段接入')),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
