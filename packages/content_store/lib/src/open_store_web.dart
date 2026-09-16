import 'dart:typed_data';

import 'package:idb_shim/idb_browser.dart';

import 'content_asset.dart';
import 'content_asset_store.dart';

ContentAssetStore openContentAssetStore() => _WebContentAssetStore();

final class _WebContentAssetStore implements ContentAssetStore {
  static const _databaseName = 'verbaseed-content-assets';
  static const _storeName = 'assets';
  Database? _database;

  Future<Database> _open() async {
    final existing = _database;
    if (existing != null) return existing;
    final database = await idbFactoryBrowser.open(
      _databaseName,
      version: 1,
      onUpgradeNeeded: (event) {
        final db = event.database;
        if (!db.objectStoreNames.contains(_storeName)) {
          db.createObjectStore(_storeName, keyPath: 'id');
        }
      },
    );
    _database = database;
    return database;
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
    final db = await _open();
    final transaction = db.transaction(_storeName, idbModeReadWrite);
    await transaction.objectStore(_storeName).put({
      'id': asset.id,
      'metadata': asset.toJson(),
      'bytes': bytes,
    });
    await transaction.completed;
    return asset;
  }

  Future<Map<Object?, Object?>?> _record(String id) async {
    final db = await _open();
    final transaction = db.transaction(_storeName, idbModeReadOnly);
    final value = await transaction.objectStore(_storeName).getObject(id);
    await transaction.completed;
    if (value == null) return null;
    return Map<Object?, Object?>.from(value as Map);
  }

  @override
  Future<ContentAsset?> metadata(String id) async {
    final record = await _record(id);
    if (record == null) return null;
    return ContentAsset.fromJson(
      Map<String, Object?>.from(record['metadata']! as Map),
    );
  }

  @override
  Future<Uint8List?> read(String id, {bool verifyIntegrity = true}) async {
    final record = await _record(id);
    if (record == null) return null;
    final rawBytes = record['bytes'];
    final bytes = switch (rawBytes) {
      final Uint8List value => Uint8List.fromList(value),
      final List<int> value => Uint8List.fromList(value),
      final List value => Uint8List.fromList(value.cast<int>()),
      _ => throw StateError('Invalid byte payload for content asset: $id'),
    };
    if (verifyIntegrity) {
      final asset = ContentAsset.fromJson(
        Map<String, Object?>.from(record['metadata']! as Map),
      );
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
  Future<bool> contains(String id) async => await _record(id) != null;

  @override
  Future<void> delete(String id) async {
    final db = await _open();
    final transaction = db.transaction(_storeName, idbModeReadWrite);
    await transaction.objectStore(_storeName).delete(id);
    await transaction.completed;
  }

  @override
  Future<void> close() async {
    _database?.close();
    _database = null;
  }
}
