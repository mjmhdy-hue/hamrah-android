import 'dart:convert';

import '../data/db/app_db.dart';
import '../data/repositories/settings_repo.dart';
import '../native/native_bridge.dart';

class SnapshotService {
  SnapshotService({required this.db, required this.settings, required this.bridge});

  final AppDb db;
  final SettingsRepo settings;
  final NativeBridge bridge;

  Future<Map<String, dynamic>> build() async {
    final categories = await db.select(db.categories).get();
    final memory = await db.select(db.merchantMemory).get();
    final values = await settings.all();
    final whitelist = _decodeWhitelist(values['sender_whitelist']);
    return {
      'contractVersion': NativeBridge.contractVersion,
      'categories': [
        for (final c in categories) {'id': c.id, 'nameFa': c.nameFa, 'type': c.type},
      ],
      'memory': {for (final m in memory) m.key: m.categoryId},
      'whitelist': whitelist,
      'settings': {
        'displayUnit': values['display_unit'] ?? 'toman',
        'hideAmounts': values['hide_amounts_always'] == '1',
        'rolloverTime': values['rollover_time'] ?? '23:59',
        'defaultFollowupCount': int.tryParse(values['default_followup_count'] ?? '2') ?? 2,
        'defaultFollowupIntervalMin': int.tryParse(values['default_followup_interval_min'] ?? '15') ?? 15,
        'voiceEnabled': values['voice_enabled'] != '0',
        'contractVersion': NativeBridge.contractVersion,
      },
    };
  }

  Future<void> sync() async {
    await bridge.syncSnapshot(await build());
  }

  List<Map<String, dynamic>> _decodeWhitelist(String? raw) {
    const seeds = [
      {'address': '9830009417', 'bankCode': 'melli', 'enabled': true},
      {'address': '+989999987641', 'bankCode': 'blu', 'enabled': true},
    ];
    if (raw == null || raw.trim().isEmpty) return seeds;
    try {
      final decoded = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      return decoded.isEmpty ? seeds : decoded;
    } catch (_) {
      return seeds;
    }
  }
}
