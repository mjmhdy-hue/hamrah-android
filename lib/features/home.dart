import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/formatting.dart';
import '../core/theme.dart';
import '../data/db/app_db.dart';
import '../data/repositories/finance_repo.dart';
import '../providers.dart';
import '../widgets/common.dart';
import 'shell.dart';
import 'transactions.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dates = ref.watch(datesProvider);
    final accounts = ref.watch(accountsProvider);
    final pending = ref.watch(pendingCountProvider).valueOrNull ?? 0;
    final unrecognized = ref.watch(unrecognizedCountProvider).valueOrNull ?? 0;
    final reminders = ref.watch(remindersProvider).valueOrNull ?? const [];
    final finance = ref.watch(financeRepoProvider);

    final todayReminders = reminders.where((item) {
      final due = item.occurrence?.scheduledFor ?? item.reminder.dueAt;
      return dates.isToday(due) || due.isBefore(DateTime.now().toUtc());
    }).toList();

    return RefreshIndicator(
      onRefresh: () => ref.read(syncCoordinatorProvider).run(force: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          PageHeader(
            title: 'همراه',
            subtitle: dates.dateWithWeekday(DateTime.now().toUtc()),
            actions: [
              IconCircle(
                icon: Icons.receipt_long_outlined,
                tooltip: 'تراکنش‌ها',
                onTap: () => context.go('/transactions'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          accounts.when(
            loading: () => const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
            error: (error, _) => HamrahCard(child: Text('حساب‌ها بارگذاری نشد: $error')),
            data: (rows) {
              if (rows.isEmpty) {
                return HamrahCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('اولین پیامک بانکی', style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 6),
                      Text(
                        'به‌محض رسیدن پیامک از فرستندهٔ تأییدشده، حساب و تراکنش به‌طور خودکار ساخته می‌شود. '
                        'فرستنده‌ها را در تنظیمات می‌بینید.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.7),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: () => context.go('/settings'),
                        child: const Text('بررسی فرستنده‌ها'),
                      ),
                    ],
                  ),
                );
              }
              return FutureBuilder<Map<String, int>>(
                future: finance.latestGaps(),
                builder: (context, gapSnapshot) {
                  final gaps = gapSnapshot.data ?? const <String, int>{};
                  return Column(
                    children: [
                      for (final account in rows)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _AccountCard(account: account, gap: gaps[account.id]),
                        ),
                    ],
                  );
                },
              );
            },
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  title: 'در انتظار دسته‌بندی',
                  value: faDigits(pending.toString()),
                  icon: Icons.sell_outlined,
                  color: HamrahColors.gold,
                  onTap: () => context.go('/transactions?status=pending'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatCard(
                  title: 'پیامک ناشناس',
                  value: faDigits(unrecognized.toString()),
                  icon: Icons.mark_email_unread_outlined,
                  color: HamrahColors.expense,
                  onTap: () => context.push('/unrecognized'),
                ),
              ),
            ],
          ),
          SectionHeader(
            title: 'یادآورهای امروز',
            trailing: TextButton(onPressed: () => context.go('/reminders'), child: const Text('همه')),
          ),
          if (todayReminders.isEmpty)
            HamrahCard(
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline, color: HamrahColors.income),
                  const SizedBox(width: 10),
                  Expanded(child: Text('یادآوری برای امروز نداری.', style: Theme.of(context).textTheme.bodyMedium)),
                  TextButton(onPressed: () => context.go('/reminders'), child: const Text('ساخت')),
                ],
              ),
            )
          else
            HamrahCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < todayReminders.length; i++) ...[
                    ListTile(
                      leading: const CategoryAvatar(icon: 'celebration', color: HamrahColors.gold),
                      title: Text(todayReminders[i].reminder.title),
                      subtitle: Text(
                        dates.isToday(todayReminders[i].occurrence?.scheduledFor ?? todayReminders[i].reminder.dueAt)
                            ? dates.clock(todayReminders[i].occurrence?.scheduledFor ?? todayReminders[i].reminder.dueAt)
                            : 'عقب‌افتاده • ${dates.longDate(todayReminders[i].occurrence?.scheduledFor ?? todayReminders[i].reminder.dueAt)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      trailing: IconButton(
                        tooltip: 'انجام شد',
                        icon: const Icon(Icons.check_circle_outline),
                        onPressed: () async {
                          await ref.read(reminderServiceProvider).complete(todayReminders[i].reminder.id);
                          await ref.read(syncCoordinatorProvider).run(force: true);
                        },
                      ),
                      onTap: () => context.go('/reminders'),
                    ),
                    if (i != todayReminders.length - 1) const Divider(height: 1, indent: 64),
                  ],
                ],
              ),
            ),
          SectionHeader(
            title: 'تراکنش‌های اخیر',
            trailing: TextButton(onPressed: () => context.go('/transactions'), child: const Text('همه')),
          ),
          _RecentTransactions(),
        ],
      ),
    );
  }
}

class _AccountCard extends ConsumerWidget {
  const _AccountCard({required this.account, this.gap});
  final Account account;
  final int? gap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dates = ref.watch(datesProvider);
    final bankName = switch (account.bankCode) {
      'melli' => 'بانک ملی ایران',
      'blu' => 'بلو',
      _ => account.bankCode,
    };
    return HamrahCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CategoryAvatar(icon: 'bank', color: HamrahColors.primary, size: 40),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(account.displayName ?? bankName, style: Theme.of(context).textTheme.titleSmall),
                    if (account.accountHint.isNotEmpty)
                      Text('شناسه حساب: ${faDigits(account.accountHint)}', style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              if (gap != null)
                Tooltip(
                  message: 'اختلاف مانده: پیامکی بین دو تراکنش ثبت نشده است',
                  child: StatusPill(text: 'اختلاف مانده', color: HamrahColors.gold),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (account.lastBalanceRial != null) ...[
            Text('ماندهٔ اعلامی بانک', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 2),
            AmountPlain(rial: account.lastBalanceRial!, style: Theme.of(context).textTheme.headlineSmall),
            if (account.lastBalanceAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${dates.longDate(account.lastBalanceAt!)} • ${dates.clock(account.lastBalanceAt!)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ] else
            Text('مانده‌ای از بانک ثبت نشده است.', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.onTap,
  });
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return HamrahCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 10),
          Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(title, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _RecentTransactions extends ConsumerWidget {
  const _RecentTransactions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stream = ref.watch(financeRepoProvider).watchTransactions(limit: 5);
    return StreamBuilder<List<TxRow>>(
      stream: stream,
      builder: (context, snapshot) {
        final rows = snapshot.data ?? const <TxRow>[];
        if (rows.isEmpty) {
          return HamrahCard(
            child: Text('هنوز تراکنشی ثبت نشده است.', style: Theme.of(context).textTheme.bodyMedium),
          );
        }
        return HamrahCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                TransactionTile(row: rows[i], dense: true),
                if (i != rows.length - 1) const Divider(height: 1, indent: 66),
              ],
            ],
          ),
        );
      },
    );
  }
}
