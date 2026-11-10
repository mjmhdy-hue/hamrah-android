import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

String escapeSqlString(String value) => value.replaceAll("'", "''");

/// Opens the Flutter-owned database with SQLite3MultipleCiphers (drift >= 2.32 setup).
/// The passphrase comes from the Android Keystore through the native bridge and is never stored
/// on disk in plaintext. Throws [StateError] when the cipher build is missing.
QueryExecutor openEncryptedDatabase({required String passphrase}) {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'hamrah', 'app.db'));
    await file.parent.create(recursive: true);
    return NativeDatabase.createInBackground(
      file,
      setup: (raw) {
        final cipher = raw.select('PRAGMA cipher;');
        if (cipher.isEmpty) {
          throw StateError('cipher_unavailable');
        }
        raw.execute("PRAGMA key = '${escapeSqlString(passphrase)}';");
        raw.execute('PRAGMA foreign_keys = ON;');
      },
    );
  });
}

/// Debug-only helper used by tests that run without a device keystore.
QueryExecutor openPlainTestDatabase(sqlite.Database database) => NativeDatabase.opened(database);
