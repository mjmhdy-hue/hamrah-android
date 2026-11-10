import '../db/app_db.dart';

class SettingsRepo {
  SettingsRepo(this.db);

  final AppDb db;

  Stream<Map<String, String>> watchAll() {
    return db.select(db.settings).watch().map(
          (rows) => {for (final row in rows) row.key: row.value},
        );
  }

  Future<Map<String, String>> all() async {
    final rows = await db.select(db.settings).get();
    return {for (final row in rows) row.key: row.value};
  }

  Future<String> value(String key, {String fallback = ''}) async {
    final row = await (db.select(db.settings)..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value ?? fallback;
  }

  Future<void> put(String key, String value) async {
    await db.into(db.settings).insertOnConflictUpdate(
          SettingsCompanion.insert(key: key, value: value),
        );
  }

  Future<void> putAll(Map<String, String> values) async {
    await db.transaction(() async {
      for (final entry in values.entries) {
        await put(entry.key, entry.value);
      }
    });
  }

  Future<String> displayUnit() => value('display_unit', fallback: 'toman');

  Future<bool> hideAmounts() async => (await value('hide_amounts_always', fallback: '0')) == '1';

  Future<bool> voiceEnabled() async => (await value('voice_enabled', fallback: '1')) == '1';

  Future<bool> voiceConsentShown() async => (await value('voice_consent_shown', fallback: '0')) == '1';
}
