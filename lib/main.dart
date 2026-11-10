import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import 'app.dart';
import 'data/db/app_db.dart';
import 'data/db/open_db.dart';
import 'data/db/seed.dart';
import 'data/repositories/settings_repo.dart';
import 'native/native_bridge.dart';
import 'providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();

  final bridge = NativeBridge();
  try {
    final passphrase = await bridge.dbKey();
    final db = AppDb(openEncryptedDatabase(passphrase: passphrase));
    await db.customSelect('SELECT 1').getSingle();
    await seedDatabase(db);
    final settings = SettingsRepo(db);
    final onboarded = (await settings.value('onboarding_done', fallback: '0')) == '1';
    runApp(
      ProviderScope(
        overrides: [
          dbProvider.overrideWithValue(db),
          bridgeProvider.overrideWithValue(bridge),
        ],
        child: HamrahApp(onboarded: onboarded),
      ),
    );
  } catch (e) {
    runApp(RecoveryApp(message: e.toString()));
  }
}
