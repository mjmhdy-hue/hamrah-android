import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';
import '../data/db/app_db.dart';
import '../data/repositories/finance_repo.dart';
import '../providers.dart';
import '../services/import_service.dart';
import '../widgets/common.dart';
import '../widgets/mic_button.dart';

class QuickCategorizePage extends ConsumerStatefulWidget {
  const QuickCategorizePage({super.key, required this.txUid});
  final String txUid;

  @override
  ConsumerState<QuickCategorizePage> createState() => _QuickCategorizePageState();
}

class _QuickCategorizePageState extends ConsumerState<QuickCategorizePage> {
  late Future<TxRow?> _future;
  final _note = TextEditingController();
  final _scaffold = GlobalKey<ScaffoldMessengerState>();
  String? _categoryId;
  bool _saving = false;
  bool _initialized = false;
  String? _voiceHint;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<TxRow?> _load() async {
    await ref.read(syncCoordinatorProvider).run(force: true);
    return ref.read(financeRepoProvider).byUid(widget.txUid);
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  String _normalize(String value) => value
      .replaceAll('\u200c', '')
      .replaceAll('\u064a', 'ی')
      .replaceAll('\u0643', 'ک')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  Future<void> _onTranscript(String text, List<Category> categories) async {
    final normalized = _normalize(text);
    Category? match;
    for (final category in categories) {
      if (normalized.contains(_normalize(category.nameFa))) {
        match = category;
        break;
      }
    }
    setState(() {
      if (match != null) {
        _categoryId = match.id;
        _voiceHint = 'دستهٔ «${match.nameFa}» انتخاب شد.';
      } else {
        final current = _note.text.trim();
        _note.text = current.isEmpty ? text : '$current $text';
        _voiceHint = 'متن گفتار در یادداشت گذاشته شد؛ دسته را انتخاب کنید.';
      }
    });
  }

  Future<void> _save(TxRow row, List<Category> categories) async {
    final categoryId = _categoryId;
    if (categoryId == null) {
      _scaffold.currentState?.showSnackBar(const SnackBar(content: Text('یک دسته انتخاب کنید')));
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
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final dates = ref.watch(datesProvider);
    return ScaffoldMessenger(
      key: _scaffold,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('دسته‌بندی سریع'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => context.canPop() ? context.pop() : context.go('/'),
          ),
        ),
        body: FutureBuilder<TxRow?>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final row = snapshot.data;
            if (row == null) {
              return EmptyState(
                title: 'تراکنش پیدا نشد',
                message: 'ممکن است حذف شده باشد یا وارد‌کردن پیامک‌ها کامل نشده باشد.',
                action: FilledButton(
                  onPressed: () => setState(() => _future = _load()),
                  child: const Text('تلاش دوباره'),
                ),
              );
            }
            final tx = row.tx;
            if (!_initialized) {
              _initialized = true;
              _note.text = tx.note ?? '';
              _categoryId = tx.categoryId;
            }
            final categories = ref.watch(categoriesProvider).valueOrNull ?? const <Category>[];
            final relevant = categories.where((c) => c.type == (tx.direction == 'in' ? 'income' : 'expense')).toList();
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      children: [
                        Text(
                          tx.direction == 'in' ? 'واریز' : 'برداشت',
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                color: tx.direction == 'in' ? HamrahColors.income : HamrahColors.expense,
                              ),
                        ),
                        const SizedBox(height: 6),
                        AmountText(rial: tx.amountRial, direction: tx.direction, large: true),
                        const SizedBox(height: 8),
                        Text(
                          tx.purposeText ?? tx.label,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${dates.longDate(tx.occurredAt)} • ${dates.clock(tx.occurredAt)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text('دسته', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final category in relevant)
                      ChoiceChip(
                        avatar: Icon(iconFor(category.icon), size: 18),
                        label: Text(category.nameFa),
                        selected: _categoryId == category.id,
                        onSelected: (_) => setState(() => _categoryId = category.id),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _note,
                        minLines: 1,
                        maxLines: 3,
                        decoration: const InputDecoration(labelText: 'یادداشت', hintText: 'اختیاری'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: MicButton(onTranscript: (text) => _onTranscript(text, relevant)),
                    ),
                  ],
                ),
                if (_voiceHint != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_voiceHint!, style: Theme.of(context).textTheme.bodySmall),
                  ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: _saving ? null : () => _save(row, relevant),
                  child: _saving
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('ذخیره'),
                ),
                const SizedBox(height: 10),
                Text(
                  'همراه این دسته را برای پیام‌های مشابه به یاد می‌سپارد. پیامک هیچ‌وقت از دستگاه خارج نمی‌شود.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
