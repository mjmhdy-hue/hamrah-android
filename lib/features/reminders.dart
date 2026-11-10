import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/formatting.dart';
import '../core/theme.dart';
import '../data/db/app_db.dart';
import '../data/repositories/reminders_repo.dart';
import '../providers.dart';
import '../widgets/common.dart';
import '../widgets/jalali_picker.dart';
import '../widgets/mic_button.dart';
import 'shell.dart';

class RemindersPage extends ConsumerWidget {
  const RemindersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dates = ref.watch(datesProvider);
    final reminders = ref.watch(remindersProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showReminderEditor(context),
        icon: const Icon(Icons.add),
        label: const Text('یادآور جدید'),
      ),
      body: Column(
        children: [
          PageHeader(
            title: 'یادآورها',
            subtitle: dates.dateWithWeekday(DateTime.now().toUtc()),
          ),
          Expanded(
            child: reminders.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => EmptyState(title: 'بارگذاری نشد', message: error.toString()),
              data: (items) {
                if (items.isEmpty) {
                  return EmptyState(
                    title: 'یادآوری نداری',
                    message: 'یک کار با تاریخ و ساعت شمسی بساز؛ همراه سر وقت یادت می‌اندازد.',
                    icon: Icons.alarm_outlined,
                    action: FilledButton(
                      onPressed: () => showReminderEditor(context),
                      child: const Text('ساخت یادآور'),
                    ),
                  );
                }
                final today = <ReminderWithOccurrence>[];
                final later = <ReminderWithOccurrence>[];
                final overdue = <ReminderWithOccurrence>[];
                for (final item in items) {
                  final due = item.occurrence?.scheduledFor ?? item.reminder.dueAt;
                  if (dates.isToday(due)) {
                    today.add(item);
                  } else if (due.isBefore(DateTime.now().toUtc())) {
                    overdue.add(item);
                  } else {
                    later.add(item);
                  }
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                  children: [
                    if (overdue.isNotEmpty) ...[
                      SectionHeader(title: 'عقب‌افتاده', subtitle: 'به‌صورت خودکار به روز بعد منتقل می‌شوند'),
                      _Group(items: overdue),
                    ],
                    if (today.isNotEmpty) ...[
                      SectionHeader(title: 'امروز'),
                      _Group(items: today),
                    ],
                    if (later.isNotEmpty) ...[
                      SectionHeader(title: 'پیش رو'),
                      _Group(items: later),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Group extends ConsumerWidget {
  const _Group({required this.items});
  final List<ReminderWithOccurrence> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return HamrahCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            _ReminderTile(item: items[i]),
            if (i != items.length - 1) const Divider(height: 1, indent: 20),
          ],
        ],
      ),
    );
  }
}

class _ReminderTile extends ConsumerWidget {
  const _ReminderTile({required this.item});
  final ReminderWithOccurrence item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dates = ref.watch(datesProvider);
    final due = item.occurrence?.scheduledFor ?? item.reminder.dueAt;
    final color = switch (item.reminder.priority) {
      2 => HamrahColors.expense,
      0 => HamrahColors.income,
      _ => HamrahColors.gold,
    };
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      leading: Container(
        width: 8,
        height: 40,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
      ),
      title: Text(item.reminder.title),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          '${dates.longDate(due)} • ${dates.clock(due)}'
          '${item.reminder.rolloverCount > 0 ? ' • ${faDigits(item.reminder.rolloverCount.toString())} بار منتقل شده' : ''}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'انجام شد',
            onPressed: () async {
              await ref.read(reminderServiceProvider).complete(item.reminder.id);
              await ref.read(syncCoordinatorProvider).run(force: true);
            },
            icon: const Icon(Icons.check_circle_outline),
          ),
          IconButton(
            tooltip: 'ویرایش',
            onPressed: () => showReminderEditor(context, reminder: item.reminder),
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      onTap: () => showReminderEditor(context, reminder: item.reminder),
    );
  }
}

Future<void> showReminderEditor(BuildContext context, {Reminder? reminder}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _ReminderEditor(reminder: reminder),
    ),
  );
}

class _ReminderEditor extends ConsumerStatefulWidget {
  const _ReminderEditor({this.reminder});
  final Reminder? reminder;

  @override
  ConsumerState<_ReminderEditor> createState() => _ReminderEditorState();
}

class _ReminderEditorState extends ConsumerState<_ReminderEditor> {
  late final TextEditingController _title;
  late final TextEditingController _notes;
  late final TextEditingController _interval;
  late DateTime _dueAt;
  late int _priority;
  late int _followups;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final reminder = widget.reminder;
    _title = TextEditingController(text: reminder?.title ?? '');
    _notes = TextEditingController(text: reminder?.notes ?? '');
    _dueAt = reminder?.dueAt ?? DateTime.now().toUtc().add(const Duration(hours: 1));
    _priority = reminder?.priority ?? 1;
    _followups = reminder?.followupCount ?? 2;
    _interval = TextEditingController(text: (reminder?.followupIntervalMin ?? 15).toString());
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    _interval.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final dates = ref.read(datesProvider);
    final local = dates.local(_dueAt);
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: local.hour, minute: local.minute),
      helpText: 'ساعت یادآوری',
    );
    if (picked == null) return;
    final j = dates.jalali(_dueAt);
    setState(() => _dueAt = dates.toUtc(j, picked.hour, picked.minute));
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('عنوان یادآور را بنویسید')));
      return;
    }
    final interval = int.tryParse(toEnDigits(_interval.text.trim())) ?? 15;
    setState(() => _saving = true);
    final service = ref.read(reminderServiceProvider);
    if (widget.reminder == null) {
      await service.create(
        title: title,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        dueAt: _dueAt,
        priority: _priority,
        followupCount: _followups,
        followupIntervalMin: interval,
      );
    } else {
      await service.update(
        id: widget.reminder!.id,
        title: title,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        dueAt: _dueAt,
        priority: _priority,
        followupCount: _followups,
        followupIntervalMin: interval,
      );
    }
    await ref.read(syncCoordinatorProvider).run(force: true);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final reminder = widget.reminder;
    if (reminder == null) return;
    await ref.read(reminderServiceProvider).delete(reminder.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final dates = ref.watch(datesProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.reminder == null ? 'یادآور جدید' : 'ویرایش یادآور',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _title,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'عنوان', hintText: 'مثلاً پرداخت قبض برق'),
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: MicButton(
                    onTranscript: (text) {
                      _title.text = text;
                      _title.selection = TextSelection.collapsed(offset: _title.text.length);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'یادداشت (اختیاری)'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: JalaliField(
                    label: 'تاریخ',
                    valueUtc: _dueAt,
                    onPicked: (j) {
                      final local = dates.local(_dueAt);
                      setState(() => _dueAt = dates.toUtc(j, local.hour, local.minute));
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: InkWell(
                    onTap: _pickTime,
                    borderRadius: BorderRadius.circular(14),
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: 'ساعت', prefixIcon: Icon(Icons.schedule)),
                      child: Text(dates.clock(_dueAt)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('اولویت', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('کم')),
                ButtonSegment(value: 1, label: Text('معمولی')),
                ButtonSegment(value: 2, label: Text('زیاد')),
              ],
              selected: {_priority},
              onSelectionChanged: (value) => setState(() => _priority = value.first),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _followups,
                    decoration: const InputDecoration(labelText: 'تعداد یادآوری دوباره'),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('بدون یادآوری')),
                      DropdownMenuItem(value: 1, child: Text('۱ بار')),
                      DropdownMenuItem(value: 2, child: Text('۲ بار')),
                    ],
                    onChanged: (value) => setState(() => _followups = value ?? 0),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _interval,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'فاصله (دقیقه)', suffixText: 'دقیقه'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('ذخیره'),
                  ),
                ),
                if (widget.reminder != null) ...[
                  const SizedBox(width: 10),
                  OutlinedButton(onPressed: _saving ? null : _delete, child: const Text('حذف')),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'تاریخ و ساعت همیشه با تقویم شمسی انتخاب می‌شود؛ گفتار فقط عنوان را پر می‌کند.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
