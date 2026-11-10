import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/formatting.dart';
import '../core/theme.dart';
import '../data/db/app_db.dart';
import '../providers.dart';
import '../widgets/common.dart';
import 'shell.dart';

const _banks = {
  'melli': {
    'name': 'بانک ملی ایران',
    'types': ['برداشت', 'خرید اینترنتی', 'حقوق', 'حواله پل'],
    'seed': '9830009417',
  },
  'blu': {
    'name': 'بلو',
    'types': ['برداشت پول', 'واریز پول', 'خرید بسته اینترنت'],
    'seed': '+989999987641',
  },
};

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsStreamProvider).asData?.value ?? const <String, String>{};
    final dates = ref.watch(datesProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        const PageHeader(title: 'تنظیمات', subtitle: 'همه‌چیز روی همین دستگاه می‌ماند'),
        const SectionHeader(title: 'بانک‌ها و فرستنده‌ها'),
        _SendersCard(settings: settings),
        const SectionHeader(title: 'دسترسی‌ها'),
        _PermissionsCard(),
        const SectionHeader(title: 'نمایش'),
        HamrahCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.payments_outlined),
                title: const Text('واحد نمایش مبلغ'),
                subtitle: Text(settings['display_unit'] == 'rial' ? 'ریال' : 'تومان (پیش‌فرض)'),
                trailing: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'toman', label: Text('تومان')),
                    ButtonSegment(value: 'rial', label: Text('ریال')),
                  ],
                  selected: {settings['display_unit'] ?? 'toman'},
                  onSelectionChanged: (value) async {
                    await ref.read(settingsRepoProvider).put('display_unit', value.first);
                    await ref.read(syncCoordinatorProvider).run(force: true);
                  },
                ),
              ),
              const Divider(height: 1, indent: 56),
              SwitchListTile(
                secondary: const Icon(Icons.visibility_off_outlined),
                title: const Text('همیشه مبلغ‌ها را پنهان کن'),
                subtitle: const Text('روی صفحهٔ قفل و اعلان‌ها'),
                value: settings['hide_amounts_always'] == '1',
                onChanged: (value) async {
                  await ref.read(settingsRepoProvider).put('hide_amounts_always', value ? '1' : '0');
                  await ref.read(syncCoordinatorProvider).run(force: true);
                },
              ),
            ],
          ),
        ),
        const SectionHeader(title: 'ورودی صوتی'),
        HamrahCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.mic_none_outlined),
                title: const Text('ورود صوتی'),
                subtitle: const Text('فقط در صفحهٔ برنامه و با زدن دکمهٔ میکروفن'),
                value: settings['voice_enabled'] != '0',
                onChanged: (value) async {
                  await ref.read(settingsRepoProvider).put('voice_enabled', value ? '1' : '0');
                  await ref.read(syncCoordinatorProvider).run(force: true);
                },
              ),
              const Divider(height: 1, indent: 56),
              const ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('تشخیص گفتار با سرویس دستگاه'),
                subtitle: Text('واژه‌های گفته‌شده ممکن است بسته به دستگاه به سرویس آنلاین دستگاه ارسال شوند؛ '
                    'هرگز متن پیامک یا مبلغ تراکنش ارسال نمی‌شود.'),
              ),
            ],
          ),
        ),
        const SectionHeader(title: 'امنیت'),
        const _SecurityCard(),
        const SectionHeader(title: 'قابلیت اطمینان'),
        _ReliabilityCard(settings: settings),
        const SectionHeader(title: 'پیامک‌ها'),
        HamrahCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.mark_email_unread_outlined),
                title: const Text('صندوق پیامک‌های ناشناس'),
                subtitle: const Text('پیامک‌های فرستندهٔ تأییدشده که قالبشان پشتیبانی نمی‌شود'),
                trailing: Consumer(builder: (context, ref, _) {
                  final count = ref.watch(unrecognizedCountProvider).asData?.value ?? 0;
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      StatusPill(text: faDigits(count.toString()), color: count == 0 ? HamrahColors.income : HamrahColors.gold),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_left),
                    ],
                  );
                }),
                onTap: () => context.push('/unrecognized'),
              ),
            ],
          ),
        ),
        const SectionHeader(title: 'پشتیبانی برنامه'),
        HamrahCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.troubleshoot_outlined),
                title: const Text('عیب‌یابی'),
                subtitle: const Text('وضعیت مجوزها، رمزنگاری، آخرین پیامک و گزارش رویدادها'),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => context.push('/diagnostics'),
              ),
              const Divider(height: 1, indent: 56),
              const ListTile(
                leading: Icon(Icons.lock_outline),
                title: Text('همراه نسخهٔ ۱.۰.۰'),
                subtitle: Text('بدون اینترنت در نسخهٔ نهایی • بدون حساب کاربری • بدون تبلیغات'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'آخرین بازبینی: ${dates.longDate(DateTime.now().toUtc())}',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _SendersCard extends ConsumerWidget {
  const _SendersCard({required this.settings});
  final Map<String, String> settings;

  List<Map<String, dynamic>> get _list {
    try {
      return (jsonDecode(settings['sender_whitelist'] ?? '[]') as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _save(WidgetRef ref, List<Map<String, dynamic>> value) async {
    await ref.read(settingsRepoProvider).put('sender_whitelist', jsonEncode(value));
    await ref.read(syncCoordinatorProvider).run(force: true);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = _list;
    return HamrahCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (final entry in list)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Row(
                children: [
                  const CategoryAvatar(icon: 'bank', size: 40),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              _banks[entry['bankCode']]?['name'] as String? ?? 'فرستندهٔ پشتیبانی‌نشده',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(width: 8),
                            if (_banks.containsKey(entry['bankCode']))
                              StatusPill(text: 'پشتیبانی‌شده', color: HamrahColors.income)
                            else
                              StatusPill(text: 'پشتیبانی نمی‌شود', color: HamrahColors.expense),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(faDigits(entry['address'] as String), style: Theme.of(context).textTheme.bodySmall),
                        if (_banks[entry['bankCode']] != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'پیام‌های تأییدشده: ${(_banks[entry['bankCode']]!['types'] as List).join('، ')}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Switch(
                    value: entry['enabled'] != false,
                    onChanged: (value) async {
                      entry['enabled'] = value;
                      await _save(ref, list);
                    },
                  ),
                  IconButton(
                    tooltip: 'حذف فرستنده',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      list.remove(entry);
                      await _save(ref, list);
                    },
                  ),
                ],
              ),
            ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('افزودن فرستنده'),
            subtitle: const Text('فقط فرستنده‌های بانک ملی و بلو دارای قالب تأییدشده‌اند'),
            onTap: () async {
              final controller = TextEditingController();
              final address = await showDialog<String>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('افزودن فرستنده'),
                  content: TextField(
                    controller: controller,
                    autofocus: true,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(hintText: 'مثلاً +989999987641'),
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, controller.text.trim()),
                      child: const Text('افزودن'),
                    ),
                  ],
                ),
              );
              if (address == null || address.isEmpty) return;
              final canonical = _canonical(address);
              String? bank;
              for (final entry in _banks.entries) {
                if (_canonical(entry.value['seed'] as String) == canonical) bank = entry.key;
              }
              final updated = [
                ...list,
                {'address': address, 'bankCode': bank, 'enabled': true},
              ];
              await _save(ref, updated);
              if (!context.mounted) return;
              if (bank == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('این فرستنده پشتیبانی نمی‌شود؛ پیام‌هایش در صندوق ناشناس می‌ماند.')),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  static String _canonical(String address) {
    var value = address.replaceAll(' ', '').replaceAll('-', '').trim();
    if (value.startsWith('+')) {
      value = value.substring(1);
    } else if (value.startsWith('00')) {
      value = value.substring(2);
    }
    if (value.startsWith('98') && value.length > 2) value = value.substring(2);
    if (value.startsWith('0') && value.length > 1) value = value.substring(1);
    return value;
  }
}

class _PermissionsCard extends ConsumerStatefulWidget {
  @override
  ConsumerState<_PermissionsCard> createState() => _PermissionsCardState();
}

class _PermissionsCardState extends ConsumerState<_PermissionsCard> with WidgetsBindingObserver {
  String _sms = '…';
  String _notifications = '…';
  bool _exact = false;
  bool _mic = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final bridge = ref.read(bridgeProvider);
    try {
      final sms = await bridge.smsPermissionState();
      final notifications = await bridge.notificationPermissionState();
      final exact = await bridge.canScheduleExactAlarms();
      final mic = (await bridge.micPermissionState()) == 'granted';
      if (mounted) {
        setState(() {
          _sms = sms;
          _notifications = notifications;
          _exact = exact;
          _mic = mic;
        });
      }
    } catch (_) {}
  }

  Widget _tile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool ok,
    required String actionLabel,
    required Future<void> Function() action,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusPill(text: ok ? 'فعال' : 'غیرفعال', color: ok ? HamrahColors.income : HamrahColors.expense),
          const SizedBox(width: 6),
          if (!ok) TextButton(onPressed: () => action(), child: Text(actionLabel)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bridge = ref.read(bridgeProvider);
    return HamrahCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _tile(
            icon: Icons.sms_outlined,
            title: 'دریافت پیامک',
            subtitle: 'در اندروید ۱۵+ ممکن است نیاز به «اجازهٔ تنظیمات محدود» باشد',
            ok: _sms == 'granted',
            actionLabel: 'اجازه',
            action: () async {
              await bridge.requestSmsPermission();
              await Future<void>.delayed(const Duration(milliseconds: 800));
              await _refresh();
            },
          ),
          const Divider(height: 1, indent: 56),
          _tile(
            icon: Icons.notifications_active_outlined,
            title: 'اعلان‌ها',
            subtitle: 'برای تراکنش و یادآور',
            ok: _notifications == 'granted',
            actionLabel: 'اجازه',
            action: () async {
              await bridge.requestNotificationPermission();
              await Future<void>.delayed(const Duration(milliseconds: 600));
              await _refresh();
            },
          ),
          if (_sms != 'granted') ...[
            const Divider(height: 1, indent: 56),
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: const Text('تنظیمات مجوز پیامک (اندروید ۱۵+)'),
              subtitle: const Text('اطلاعات برنامه ← منو ← اجازهٔ تنظیمات محدود ← مجوزها ← پیامک'),
              onTap: () => bridge.openAppDetails(),
            ),
          ],
          const Divider(height: 1, indent: 56),
          _tile(
            icon: Icons.alarm_outlined,
            title: 'آلارم دقیق',
            subtitle: 'بدون آن یادآورها ممکن است دیر اعلام شوند',
            ok: _exact,
            actionLabel: 'تنظیم',
            action: () async {
              await bridge.openExactAlarmSettings();
            },
          ),
          const Divider(height: 1, indent: 56),
          _tile(
            icon: Icons.mic_none_outlined,
            title: 'میکروفن',
            subtitle: 'فقط هنگام لمس دکمهٔ میکروفن درخواست می‌شود',
            ok: _mic,
            actionLabel: 'اجازه',
            action: () async {
              await bridge.requestMicPermission();
              await Future<void>.delayed(const Duration(milliseconds: 600));
              await _refresh();
            },
          ),
        ],
      ),
    );
  }
}

class _SecurityCard extends ConsumerWidget {
  const _SecurityCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _load(ref),
      builder: (context, snapshot) {
        final data = snapshot.data ?? const <String, dynamic>{};
        return HamrahCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              ListTile(
                leading: Icon(Icons.enhanced_encryption_outlined, color: data['cipher'] == true ? HamrahColors.income : HamrahColors.expense),
                title: const Text('رمزنگاری پایگاه داده'),
                subtitle: Text(data['cipherMessage'] as String? ?? 'در حال بررسی…'),
                trailing: StatusPill(
                  text: data['cipher'] == true ? 'فعال' : 'نامشخص',
                  color: data['cipher'] == true ? HamrahColors.income : HamrahColors.gold,
                ),
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: const Icon(Icons.vpn_key_outlined),
                title: const Text('کلید دستگاه'),
                subtitle: Text(data['keyState'] == 'ok' ? 'کلید Android Keystore موجود است' : 'وضعیت: ${data['keyState'] ?? 'نامشخص'}'),
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: const Icon(Icons.backup_outlined),
                title: const Text('پشتیبان‌گیری'),
                subtitle: const Text('خاموش است؛ کلید رمزنگاری بین دستگاه‌ها منتقل نمی‌شود'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<Map<String, dynamic>> _load(WidgetRef ref) async {
    final db = ref.read(dbProvider);
    final bridge = ref.read(bridgeProvider);
    var cipher = false;
    String message = 'نامشخص';
    try {
      final rows = await db.customSelect('PRAGMA cipher;').get();
      cipher = rows.isNotEmpty;
      message = cipher ? 'SQLite3MultipleCiphers فعال است' : 'خروجی PRAGMA cipher خالی است';
    } catch (e) {
      message = 'بررسی رمزنگاری ناموفق: $e';
    }
    String keyState = 'نامشخص';
    try {
      final diagnostics = await bridge.diagnostics();
      keyState = (diagnostics['keyState'] ?? 'نامشخص') as String;
    } catch (_) {}
    return {'cipher': cipher, 'cipherMessage': message, 'keyState': keyState};
  }
}

class _ReliabilityCard extends ConsumerWidget {
  const _ReliabilityCard({required this.settings});
  final Map<String, String> settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> toggle(String key, bool value) async {
      await ref.read(settingsRepoProvider).put(key, value ? '1' : '0');
    }

    return HamrahCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.battery_saver_outlined),
            title: const Text('بهینه‌سازی باتری'),
            subtitle: const Text('در تنظیمات سیستم، محدودیت باتری همراه را بردارید'),
            trailing: TextButton(
              onPressed: () => ref.read(bridgeProvider).openBatterySettings(),
              child: const Text('باز کردن'),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.check_circle_outline),
            title: const Text('محدودیت باتری را برداشتم'),
            value: settings['reliability_battery'] == '1',
            onChanged: (value) => toggle('reliability_battery', value),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.check_circle_outline),
            title: const Text('اجازهٔ اجرای خودکار را دادم'),
            value: settings['reliability_autostart'] == '1',
            onChanged: (value) => toggle('reliability_autostart', value),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.check_circle_outline),
            title: const Text('همراه را از فهرست پاک‌سازی خارج کردم'),
            value: settings['reliability_recent'] == '1',
            onChanged: (value) => toggle('reliability_recent', value),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Text(
              'این موردها قابل بررسی خودکار نیستند و فقط برای یادآوری خودتان است. '
              'همراه دربارهٔ سازگاری با برندهای مختلف گوشی ادعایی ندارد.',
              style: TextStyle(fontSize: 12, height: 1.6),
            ),
          ),
        ],
      ),
    );
  }
}

class UnrecognizedPage extends ConsumerWidget {
  const UnrecognizedPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dates = ref.watch(datesProvider);
    final stream = ref.watch(financeRepoProvider).watchUnrecognized();
    return Scaffold(
      appBar: AppBar(title: const Text('پیامک‌های ناشناس')),
      body: StreamBuilder<List<SmsRecord>>(
        stream: stream,
        builder: (context, snapshot) {
          final rows = snapshot.data ?? const <SmsRecord>[];
          if (rows.isEmpty) {
            return const EmptyState(
              title: 'پیامک ناشناسی نیست',
              message: 'پیامک‌های فرستندهٔ تأییدشده که قالبشان شناسایی نشود اینجا نگه داشته می‌شوند؛ بدون ساخت تراکنش.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final sms = rows[index];
              return HamrahCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.help_outline, size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'فرستندهٔ ناشناس • ${dates.dateWithWeekday(sms.receivedAt)} ${dates.clock(sms.receivedAt)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        StatusPill(text: 'پشتیبانی نمی‌شود', color: HamrahColors.gold),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(sms.body, style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.7)),
                    const SizedBox(height: 8),
                    Text(
                      'کد خطا: ${sms.parseErrorCode ?? 'نامشخص'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class DiagnosticsPage extends ConsumerStatefulWidget {
  const DiagnosticsPage({super.key});

  @override
  ConsumerState<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends ConsumerState<DiagnosticsPage> with WidgetsBindingObserver {
  Map<String, dynamic>? _native;
  String? _error;
  Map<String, dynamic> _main = const {};
  bool _voiceReady = false;
  String? _voiceError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final db = ref.read(dbProvider);
    final bridge = ref.read(bridgeProvider);
    final voice = ref.read(voiceServiceProvider);
    try {
      final native = await bridge.diagnostics();
      var cipher = false;
      String schema = '?';
      try {
        cipher = (await db.customSelect('PRAGMA cipher;').get()).isNotEmpty;
        final version = await db.customSelect('PRAGMA user_version;').get();
        schema = version.isEmpty ? '?' : version.first.data.values.first.toString();
      } catch (_) {}
      final counts = <String, dynamic>{};
      counts['transactions'] = (await db.select(db.transactions).get()).length;
      counts['reminders'] = (await db.select(db.reminders).get()).length;
      counts['rawSms'] = (await db.select(db.rawSms).get()).length;
      final available = await voice.ensureInitialized();
      if (mounted) {
        setState(() {
          _native = native;
          _error = null;
          _main = {
            'cipher': cipher,
            'schemaVersion': schema,
            'counts': counts,
            'contractVersion': 1,
          };
          _voiceReady = available;
          _voiceError = voice.lastError;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final native = _native;
    final nativeData = (native?['native'] as Map?)?.cast<String, dynamic>() ?? const {};
    final lastSms = (nativeData['lastSms'] as Map?)?.cast<String, dynamic>();
    final logs = (nativeData['log'] as List?) ?? const [];
    final dates = ref.watch(datesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('عیب‌یابی'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh), tooltip: 'به‌روزرسانی'),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          if (_error != null)
            HamrahCard(child: Text('خواندن وضعیت ناموفق بود: $_error', style: const TextStyle(color: HamrahColors.expense))),
          const SectionHeader(title: 'پایگاه داده'),
          HamrahCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                InfoRow(label: 'رمزنگاری (PRAGMA cipher)', value: _main['cipher'] == true ? 'فعال' : 'نامشخص'),
                const Divider(height: 1),
                InfoRow(label: 'نسخهٔ اسکیمای Flutter', value: _main['schemaVersion']?.toString() ?? '?'),
                const Divider(height: 1),
                InfoRow(label: 'نسخهٔ قرارداد', value: '${_main['contractVersion']}'),
                const Divider(height: 1),
                InfoRow(label: 'پایگاه دادهٔ بومی باز است', value: nativeData['nativeDbOpen'] == true ? 'بله' : 'خیر'),
                const Divider(height: 1),
                InfoRow(label: 'کلید دستگاه', value: (native?['keyState'] ?? '?').toString()),
                const Divider(height: 1),
                InfoRow(label: 'تراکنش‌های Flutter', value: '${(_main['counts'] as Map?)?['transactions'] ?? '?'}'),
              ],
            ),
          ),
          const SectionHeader(title: 'پیامک و اعلان'),
          HamrahCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                InfoRow(label: 'مجوز پیامک', value: (native?['smsPermission'] ?? '?').toString()),
                const Divider(height: 1),
                InfoRow(label: 'گیرندهٔ پیامک ثبت شده', value: native?['receiverEnabled'] == true ? 'بله' : 'خیر'),
                const Divider(height: 1),
                InfoRow(label: 'مجوز اعلان', value: (native?['notificationPermission'] ?? '?').toString()),
                const Divider(height: 1),
                InfoRow(label: 'کانال تراکنش', value: (native?['notificationChannelTx'] ?? '?').toString()),
                const Divider(height: 1),
                InfoRow(label: 'آلارم دقیق', value: native?['exactAlarmAllowed'] == true ? 'مجاز' : 'غیرمجاز'),
                const Divider(height: 1),
                InfoRow(label: 'آخرین پیامک', value: lastSms == null ? 'ثبت نشده' : (lastSms['status'] ?? '?').toString()),
                if (lastSms != null && lastSms['receivedAt'] != null)
                  InfoRow(
                    label: 'زمان آخرین پیامک',
                    value: dates.dateWithWeekday(DateTime.fromMillisecondsSinceEpoch((lastSms['receivedAt'] as num).toInt(), isUtc: true)) +
                        ' ${dates.clock(DateTime.fromMillisecondsSinceEpoch((lastSms['receivedAt'] as num).toInt(), isUtc: true))}',
                  ),
                const Divider(height: 1),
                InfoRow(label: 'پیامک ناشناس / رمز پویا', value: '${nativeData['unrecognizedCount'] ?? '?'} / ${nativeData['otpCount'] ?? '?'}'),
                const Divider(height: 1),
                InfoRow(label: 'تکراری‌های نادیده‌گرفته‌شده', value: '${nativeData['duplicates'] ?? '?'}'),
                const Divider(height: 1),
                InfoRow(label: 'در انتظار ورود به Flutter', value: '${nativeData['pendingImport'] ?? '?'}'),
              ],
            ),
          ),
          const SectionHeader(title: 'گفتار'),
          HamrahCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InfoRow(label: 'سرویس تشخیص گفتار', value: _voiceReady ? 'در دسترس' : 'در دسترس نیست'),
                if (_voiceError != null) Text('علت: $_voiceError', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 4),
                Text(
                  'میکروفن فقط در پیش‌زمینه و با لمس دکمه فعال می‌شود. متن گفتار ذخیره نمی‌شود.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SectionHeader(title: 'گزارش رویدادها (۲۰۰ مورد آخر)', subtitle: 'فقط کد رویداد و وضعیت؛ هرگز متن پیامک، نام یا مبلغ'),
          HamrahCard(
            padding: const EdgeInsets.all(12),
            child: logs.isEmpty
                ? Text('رویدادی ثبت نشده است.', style: Theme.of(context).textTheme.bodySmall)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final entry in logs.take(60))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Text(
                            '${dates.clock(DateTime.fromMillisecondsSinceEpoch(((entry as Map)['ts'] as num).toInt(), isUtc: true))}'
                            '  ${entry['code']}'
                            '${entry['detail'] == null ? '' : '  ${entry['detail']}'}',
                            style: Theme.of(context).textTheme.bodySmall,
                            textDirection: TextDirection.ltr,
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
