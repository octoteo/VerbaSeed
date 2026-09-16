import 'package:drift_flutter/drift_flutter.dart';

import 'database.dart';

VerbaSeedDatabase openVerbaSeedDatabase() {
  final executor = driftDatabase(
    name: 'verbaseed',
    web: DriftWebOptions(
      sqlite3Wasm: Uri.parse('sqlite3.wasm'),
      driftWorker: Uri.parse('drift_worker.dart.js'),
    ),
  );
  return VerbaSeedDatabase(executor);
}
