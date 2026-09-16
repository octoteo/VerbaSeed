import 'dart:typed_data';

import 'package:content_store/content_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('content-addressed store deduplicates and verifies bytes', () async {
    final store = MemoryContentAssetStore();
    final bytes = Uint8List.fromList([1, 2, 3, 4]);

    final first = await store.put(
      bytes: bytes,
      fileName: 'lesson.pdf',
      mimeType: 'application/pdf',
    );
    final second = await store.put(
      bytes: bytes,
      fileName: 'lesson-copy.pdf',
      mimeType: 'application/pdf',
    );

    expect(first.id, second.id);
    expect(first.sha256, hasLength(64));
    expect(await store.contains(first.id), isTrue);
    expect(await store.read(first.id), orderedEquals(bytes));

    await store.delete(first.id);
    expect(await store.contains(first.id), isFalse);
  });
}
