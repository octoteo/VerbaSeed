import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'content_asset.dart';
import 'content_asset_store.dart';

ContentAssetStore openContentAssetStore() => _IoContentAssetStore();

final class _IoContentAssetStore implements ContentAssetStore {
  Future<Directory>? _rootFuture;

  Future<Directory> _root() => _rootFuture ??= _createRoot();

  Future<Directory> _createRoot() async {
    final support = await getApplicationSupportDirectory();
    final root = Directory(p.join(support.path, 'verbaseed', 'content-assets-v1'));
    await root.create(recursive: true);
    return root;
  }

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
    final root = await _root();
    final contentFile = File(p.join(root.path, '${asset.id}.bin'));
    final metadataFile = File(p.join(root.path, '${asset.id}.json'));

    if (!await contentFile.exists()) {
      final temporary = File('${contentFile.path}.tmp-${DateTime.now().microsecondsSinceEpoch}');
      await temporary.writeAsBytes(bytes, flush: true);
      try {
        await temporary.rename(contentFile.path);
      } on FileSystemException {
        if (!await contentFile.exists()) rethrow;
        await temporary.delete().catchError((_) => temporary);
      }
    }

    final metadataTemporary = File('${metadataFile.path}.tmp-${DateTime.now().microsecondsSinceEpoch}');
    await metadataTemporary.writeAsString(jsonEncode(asset.toJson()), flush: true);
    if (await metadataFile.exists()) {
      await metadataFile.delete();
    }
    await metadataTemporary.rename(metadataFile.path);
    return asset;
  }

  @override
  Future<ContentAsset?> metadata(String id) async {
    final root = await _root();
    final file = File(p.join(root.path, '$id.json'));
    if (!await file.exists()) return null;
    final decoded = jsonDecode(await file.readAsString());
    return ContentAsset.fromJson(Map<String, Object?>.from(decoded as Map));
  }

  @override
  Future<Uint8List?> read(String id, {bool verifyIntegrity = true}) async {
    final root = await _root();
    final file = File(p.join(root.path, '$id.bin'));
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    if (verifyIntegrity) {
      final asset = await metadata(id);
      if (asset == null) {
        throw StateError('Missing metadata for content asset: $id');
      }
      final actual = ContentAsset.fromBytes(
        bytes: bytes,
        fileName: asset.fileName,
        mimeType: asset.mimeType,
      ).sha256;
      if (actual != asset.sha256) {
        throw StateError('Content asset integrity check failed: $id');
      }
    }
    return bytes;
  }

  @override
  Future<bool> contains(String id) async {
    final root = await _root();
    return File(p.join(root.path, '$id.bin')).exists();
  }

  @override
  Future<void> delete(String id) async {
    final root = await _root();
    for (final suffix in ['bin', 'json']) {
      final file = File(p.join(root.path, '$id.$suffix'));
      if (await file.exists()) await file.delete();
    }
  }

  @override
  Future<void> close() async {}
}
