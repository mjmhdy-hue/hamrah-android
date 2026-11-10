import 'package:drift/drift.dart';

import 'app_db.dart';

class SeedCategory {
  const SeedCategory(this.id, this.nameFa, this.icon, this.type);
  final String id;
  final String nameFa;
  final String icon;
  final String type;
}

const seedCategories = <SeedCategory>[
  SeedCategory('cat_food', 'خوراک', 'restaurant', 'expense'),
  SeedCategory('cat_transport', 'حمل‌ونقل', 'directions_bus', 'expense'),
  SeedCategory('cat_bills', 'قبوض', 'receipt', 'expense'),
  SeedCategory('cat_internet', 'اینترنت و شارژ', 'wifi', 'expense'),
  SeedCategory('cat_shopping', 'خرید', 'shopping_bag', 'expense'),
  SeedCategory('cat_health', 'سلامت', 'health_and_safety', 'expense'),
  SeedCategory('cat_fun', 'تفریح', 'celebration', 'expense'),
  SeedCategory('cat_other_expense', 'سایر', 'more_horiz', 'expense'),
  SeedCategory('cat_salary', 'حقوق', 'payments', 'income'),
  SeedCategory('cat_other_income', 'سایر درآمد', 'add_card', 'income'),
  SeedCategory('cat_transfer', 'انتقال بین حساب‌ها', 'swap_horiz', 'transfer'),
];

const defaultSettings = <String, String>{
  'sender_whitelist': '[{"address":"9830009417","bankCode":"melli","enabled":true},'
      '{"address":"+989999987641","bankCode":"blu","enabled":true}]',
  'display_unit': 'toman',
  'hide_amounts_always': '0',
  'rollover_time': '23:59',
  'default_followup_count': '2',
  'default_followup_interval_min': '15',
  'voice_enabled': '1',
  'voice_consent_shown': '0',
  'contract_version': '1',
};

/// Editable defaults only — no bank data, no fake transactions.
Future<void> seedDatabase(AppDb db) async {
  await db.transaction(() async {
    for (final category in seedCategories) {
      await db.into(db.categories).insert(
            CategoriesCompanion.insert(
              id: category.id,
              nameFa: category.nameFa,
              icon: Value(category.icon),
              type: Value(category.type),
              isDefault: const Value(true),
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }
    for (final entry in defaultSettings.entries) {
      await db.into(db.settings).insert(
            SettingsCompanion.insert(key: entry.key, value: entry.value),
            mode: InsertMode.insertOrIgnore,
          );
    }
  });
}
