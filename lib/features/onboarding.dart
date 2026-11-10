import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';
import '../providers.dart';
import '../widgets/common.dart';

class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> with WidgetsBindingObserver {
  bool _sms = false;
  bool _notifications = false;
  bool _exact = true;
  Map<String, dynamic>? _diagnostics;
  bool _busy = false;

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
      final diagnostics = await bridge.diagnostics();
      if (mounted) {
        setState(() {
          _sms = sms == 'granted';
          _notifications = notifications == 'granted';
          _exact = exact;
          _diagnostics = diagnostics;
        });
      }
    } catch (_) {
      // keep defaults; Diagnostics shows the reason
    }
  }

  Future<void> _finish() async {
    setState(() => _busy = true);
    await ref.read(settingsRepoProvider).put('onboarding_done', '1');
    await ref.read(syncCoordinatorProvider).run(force: true);
    if (mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final restrictedHint = !_sms && (_diagnostics != null);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: HamrahColors.primary,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.account_balance_wallet_outlined, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Text('همراه', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'تراکنش‌های بانکی از پیامک، بدون اینترنت، روی همین گوشی.\n'
              'پیامک‌ها و مبلغ‌ها از دستگاه بیرون نمی‌روند و هر دو پایگاه داده رمزنگاری‌شده‌اند.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.7),
            ),
            const SizedBox(height: 20),
            _PermissionCard(
              icon: Icons.notifications_active_outlined,
              title: 'اعلان تراکنش و یادآور',
              description: 'برای نمایش فوری تراکنش شناسایی‌شده و یادآورها لازم است.',
              status: _notifications ? 'فعال' : 'غیرفعال',
              active: _notifications,
              actionLabel: _notifications ? null : 'اجازه دادن',
              onAction: () async {
                await ref.read(bridgeProvider).requestNotificationPermission();
                await Future<void>.delayed(const Duration(milliseconds: 600));
                await _refresh();
              },
            ),
            _PermissionCard(
              icon: Icons.sms_outlined,
              title: 'خواندن پیامک بانک (فقط دریافت)',
              description: 'فقط پیامک‌های فرستنده‌های تأییدشدهٔ بانک پردازش می‌شوند؛ سایر پیامک‌ها ذخیره نمی‌شوند.',
              status: _sms ? 'فعال' : 'غیرفعال',
              active: _sms,
              actionLabel: _sms ? null : 'اجازه دادن',
              onAction: () async {
                await ref.read(bridgeProvider).requestSmsPermission();
                await Future<void>.delayed(const Duration(milliseconds: 800));
                await _refresh();
              },
            ),
            if (restrictedHint && !_sms)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: HamrahColors.gold.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('اگر پیامک فعال نشد', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 6),
                    Text(
                      'در اندروید ۱۵ و بالاتر، برای برنامه‌های نصب‌شده از بیرون، اجازهٔ پیامک «تنظیم محدود» است. '
                      'مسیر: اطلاعات برنامه ← منوی سه‌نقطه ← اجازهٔ تنظیمات محدود ← مجوزها ← پیامک ← اجازه دادن.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.6),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: () => ref.read(bridgeProvider).openAppDetails(),
                      child: const Text('باز کردن اطلاعات برنامه'),
                    ),
                  ],
                ),
              ),
            _PermissionCard(
              icon: Icons.alarm_outlined,
              title: 'آلارم دقیق',
              description: 'برای یادآوری سرِ وقت. اگر فعال نباشد، یادآورها ممکن است کمی دیر اعلام شوند.',
              status: _exact ? 'فعال' : 'غیرفعال',
              active: _exact,
              actionLabel: _exact ? null : 'تنظیم',
              onAction: () async {
                await ref.read(bridgeProvider).openExactAlarmSettings();
              },
            ),
            _PermissionCard(
              icon: Icons.mic_none_outlined,
              title: 'میکروفن (اختیاری)',
              description: 'فقط وقتی دکمهٔ میکروفن را بزنید. گفتار توسط سرویس دستگاه تشخیص داده می‌شود.',
              status: 'اختیاری',
              active: true,
              actionLabel: null,
              onAction: null,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _finish,
              child: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_sms ? 'شروع' : 'فعلاً بدون پیامک ادامه بده'),
            ),
            const SizedBox(height: 10),
            Text(
              'بدون اینترنت. بدون حساب کاربری. بدون تبلیغات. مجوز پیامک فقط «دریافت» است، نه خواندن صندوق پیام‌ها.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.status,
    required this.active,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String description;
  final String status;
  final bool active;
  final String? actionLabel;
  final Future<void> Function()? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: HamrahCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CategoryAvatar(icon: null, color: active ? HamrahColors.primary : HamrahColors.gold),
                const SizedBox(width: 10),
                Expanded(child: Text(title, style: Theme.of(context).textTheme.titleSmall)),
                StatusPill(text: status, color: active ? HamrahColors.income : HamrahColors.gold),
              ],
            ),
            const SizedBox(height: 8),
            Text(description, style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.6)),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 10),
              OutlinedButton(onPressed: () => onAction!(), child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
