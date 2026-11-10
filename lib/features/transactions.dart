import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/formatting.dart';
import '../core/theme.dart';
import '../data/db/app_db.dart';
import '../data/repositories/finance_repo.dart';
import '../providers.dart';
import '../services/import_service.dart';
import '../widgets/common.dart';
import 'shell.dart';

class TransactionsPage extends ConsumerStatefulWidget {
  const TransactionsPage({super.key, this.status});

  final String? status;

  @override
  ConsumerState<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends ConsumerState<TransactionsPage> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dates = ref.watch(datesProvider);
    final stream = ref.watch(financeRepoProvider).watchTransactions(
          search: _query,
          status: widget.status == 'pending' ? 'pending_category' : null,
        );

    return Column(
      children: [
        PageHeader(
          title: widget.status == 'pending' ? 'در انتظار دسته‌بندی' : 'تراکنش‌ها',
          subtitle: widget.status == 'pending' ? 'با انتخاب دسته، یادگیری همراه کامل می‌شود' : 'یادگیری دسته‌ها از همین‌جا شکل می‌گیرد',
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              hintText: 'جست‌وجو در مبلغ، توضیح یا یادداشت',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _search.clear();
                        setState(() => _query = '');
                      },
                    ),
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<TxRow>>(
            stream: stream,
            builder: (context, snapshot) {
              final rows = snapshot.data ?? const <TxRow>[];
              if (snapshot.connectionState == ConnectionState.waiting && rows.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }
              if (rows.isEmpty) {
                return EmptyState(
                  title: _query.isEmpty ? 'هنوز تراکنشی ثبت نشده' : 'نتیجه‌ای پیدا نشد',
                  message: _query.isEmpty
                      ? 'پیامک‌های بانکی شناسایی‌شده به‌صورت خودکار اینجا می‌آیند.'
                      : 'عبارت دیگری را امتحان کنید.',
                  icon: Icons.receipt_long_outlined,
                );
              }
              final groups = <String, List<TxRow>>{};
              for (final row in rows) {
                groups.putIfAbsent(dates.date(row.tx.occurredAt), () => []).add(row);
              }
              return RefreshIndicator(
                onRefresh: () => ref.read(syncCoordinatorProvider).run(force: true),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  children: [
                    for (final entry in groups.entries) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                        child: Row(
                          children: [
                            Text(entry.key, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                            const SizedBox(width: 8),
                            Expanded(child: Divider(color: Theme.of(context).dividerColor)),
                          ],
                        ),
                      ),
                      HamrahCard(
                        padding: EdgeInsets.zero,
                        child: Column(
                          children: [
                            for (var i = 0; i < entry.value.length; i++) ...[
                              TransactionTile(row: entry.value[i]),
                              if (i != entry.value.length - 1) const Divider(height: 1, indent: 68),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class TransactionTile extends ConsumerWidget {
  const TransactionTile({super.key, required this.row, this.dense = false});
  final TxRow row;
  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tx = row.tx;
    final dates = ref.watch(datesProvider);
    final title = tx.counterparty ?? tx.purposeText ?? (row.category?.nameFa ?? tx.label);
    final pending = tx.status == 'pending_category';
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      leading: CategoryAvatar(icon: row.category?.icon ?? 'wallet', size: dense ? 38 : 42),
      title: Row(
        children: [
          Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis)),
          if (tx.balanceGapRial != null && tx.balanceGapRial != 0)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Tooltip(
                message: 'اختلاف مانده با تراکنش قبلی',
                child: Icon(Icons.error_outline, size: 16, color: HamrahColors.gold),
              ),
            ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(
          children: [
            Flexible(child: Text(tx.label, maxLines: 1, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 6),
            Text('•', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(width: 6),
            Text(dates.clock(tx.occurredAt), style: Theme.of(context).textTheme.bodySmall),
            if (pending) ...[
              const SizedBox(width: 8),
              StatusPill(text: 'دسته‌بندی نشده', color: HamrahColors.gold),
            ],
          ],
        ),
      ),
      trailing: AmountText(rial: tx.amountRial, direction: tx.direction, showSign: true),
      onTap: () => pending ? context.push('/quick?tx=${tx.txUid}') : showTransactionSheet(context, tx.txUid),
    );
  }
}

Future<void> showTransactionSheet(BuildContext context, String txUid) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _TransactionSheet(txUid: txUid),
    ),
  );
}

class _TransactionSheet extends ConsumerStatefulWidget {
  const _TransactionSheet({required this.txUid});
  final String txUid;

  @override
  ConsumerState<_TransactionSheet> createState() => _TransactionSheetState();
}

class _TransactionSheetState extends ConsumerState<_TransactionSheet> {
  late Future<TxRow?> _future;
  final _note = TextEditingController();
  String? _categoryId;
  bool _saving = false;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _future = ref.read(financeRepoProvider).byUid(widget.txUid);
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dates = ref.watch(datesProvider);
    return FutureBuilder<TxRow?>(
      future: _future,
      builder: (context, snapshot) {
        final row = snapshot.data;
        if (row == null) {
          return const SizedBox(height: 180, child: Center(child: CircularProgressIndicator()));
        }
        if (!_initialized) {
          _initialized = true;
          _note.text = row.tx.note ?? '';
          _categoryId = row.tx.categoryId;
        }
        final tx = row.tx;
        final categories = ref.watch(categoriesProvider).asData?.value ?? const <Category>[];
        final relevant = categories.where((c) => c.type == (tx.direction == 'in' ? 'income' : 'expense')).toList();
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CategoryAvatar(icon: row.category?.icon ?? 'wallet', size: 46),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tx.counterparty ?? tx.purposeText ?? tx.label,
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 2),
                        Text(
                          '${tx.direction == 'in' ? 'واریز' : 'برداشت'} • ${dates.longDate(tx.occurredAt)} • ${dates.clock(tx.occurredAt)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Center(child: AmountText(rial: tx.amountRial, direction: tx.direction, large: true)),
              const SizedBox(height: 8),
              if (tx.balanceAfterRial != null)
                Center(
                  child: Text(
                    'ماندهٔ اعلامی بانک: ${formatMoneyShort(tx.balanceAfterRial!)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              if (tx.balanceGapRial != null && tx.balanceGapRial != 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: HamrahColors.gold.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'اختلاف مانده: بین این پیامک و تراکنش قبلی، مبلغی ثبت نشده است. '
                      'همراه مانده را اصلاح نمی‌کند و فقط این اختلاف را نشان می‌دهد.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
              const SizedBox(height: 18),
              Text('دسته‌بندی', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final category in relevant)
                    ChoiceChip(
                      label: Text(category.nameFa),
                      selected: _categoryId == category.id,
                      onSelected: (_) => setState(() => _categoryId = category.id),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _note,
                decoration: const InputDecoration(hintText: 'یادداشت (اختیاری)'),
                minLines: 1,
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: _saving ? null : () => _save(row),
                      child: _saving
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('ذخیره'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton(
                    onPressed: _saving ? null : () => _delete(tx),
                    child: const Text('حذف'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  String formatMoneyShort(int rial) {
    final unit = ref.read(settingsStreamProvider).asData?.value?['display_unit'] ?? 'toman';
    return unit == 'rial' ? '${faDigits(grouped(rial))} ریال' : '${faDigits(grouped(rial ~/ 10))} تومان';
  }

  Future<void> _save(TxRow row) async {
    final categoryId = _categoryId;
    if (categoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('یک دسته انتخاب کنید')));
      return;
    }
    setState(() => _saving = true);
    await ref.read(financeRepoProvider).categorize(
          txUid: row.tx.txUid,
          categoryId: categoryId,
          note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          memoryKey: ImportService.memoryKeyFor(row.tx),
        );
    await ref.read(syncCoordinatorProvider).run(force: true);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete(TxRecord tx) async {
    setState(() => _saving = true);
    await ref.read(financeRepoProvider).softDelete(tx.txUid);
    if (mounted) Navigator.of(context).pop();
  }
}
