import 'dart:typed_data';

import 'content_asset.dart';

abstract interface class ContentAssetStore {
  Future<ContentAsset> put({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  });

  Future<ContentAsset?> metadata(String id);

  Future<Uint8List?> read(String id, {bool verifyIntegrity = true});

  Future<bool> contains(String id);

  Future<void> delete(String id);

  Future<void> close();
}

final class MemoryContentAssetStore implements ContentAssetStore {
  final Map<String, ({ContentAsset asset, Uint8List bytes})> _assets = {};

  @override
  Future<ContentAsset> put({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    final asset = ContentAsset.fromBytes(
      bytes: bytes,
      fileName: fileName,
      mimeType: mimeType,
    );
    _assets[asset.id] = (asset: asset, bytes: Uint8List.fromList(bytes));
    return asset;
  }

  @override
  Future<ContentAsset?> metadata(String id) async => _assets[id]?.asset;

  @override
  Future<Uint8List?> read(String id, {bool verifyIntegrity = true}) async {
    final entry = _assets[id];
    if (entry == null) return null;
    final bytes = Uint8List.fromList(entry.bytes);
    if (verifyIntegrity) {
      final actual = ContentAsset.fromBytes(
        bytes: bytes,
        fileName: entry.asset.fileName,
        mimeType: entry.asset.mimeType,
      ).sha256;
      if (actual != entry.asset.sha256) {
        throw StateError('Content asset integrity check failed: $id');
      }
    }
    return bytes;
  }

  @override
  Future<bool> contains(String id) async => _assets.containsKey(id);

  @override
  Future<void> delete(String id) async {
    _assets.remove(id);
  }

  @override
  Future<void> close() async {
    _assets.clear();
  }
}
