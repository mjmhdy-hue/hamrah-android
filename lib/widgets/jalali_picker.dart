import 'package:flutter/material.dart';
import 'package:shamsi_date/shamsi_date.dart';

import '../core/formatting.dart';

Future<Jalali?> pickJalaliDate(
  BuildContext context, {
  required Jalali initial,
  Jalali? min,
  Jalali? max,
}) {
  return showDialog<Jalali>(
    context: context,
    builder: (context) => _JalaliPickerDialog(initial: initial, min: min, max: max),
  );
}

class _JalaliPickerDialog extends StatefulWidget {
  const _JalaliPickerDialog({required this.initial, this.min, this.max});
  final Jalali initial;
  final Jalali? min;
  final Jalali? max;

  @override
  State<_JalaliPickerDialog> createState() => _JalaliPickerDialogState();
}

class _JalaliPickerDialogState extends State<_JalaliPickerDialog> {
  late Jalali _month;
  late Jalali _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initial;
    _month = Jalali(widget.initial.year, widget.initial.month, 1);
  }

  bool _enabled(int day) {
    final candidate = Jalali(_month.year, _month.month, day);
    if (widget.min != null && candidate.compareTo(widget.min!) < 0) return false;
    if (widget.max != null && candidate.compareTo(widget.max!) > 0) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final days = _month.monthLength;
    final firstGregorian = _month.toGregorian();
    final weekday = DateTime(firstGregorian.year, firstGregorian.month, firstGregorian.day).weekday;
    final leading = (weekday + 1) % 7;
    final theme = Theme.of(context);
    return AlertDialog(
      title: Row(
        children: [
          IconButton(
            onPressed: () => setState(() => _month = JalaliMath.addMonths(_month, -1)),
            icon: const Icon(Icons.chevron_right),
            tooltip: 'ماه قبل',
          ),
          Expanded(
            child: Center(child: Text(JalaliMath.monthLabel(_month.year, _month.month))),
          ),
          IconButton(
            onPressed: () => setState(() => _month = JalaliMath.addMonths(_month, 1)),
            icon: const Icon(Icons.chevron_left),
            tooltip: 'ماه بعد',
          ),
        ],
      ),
      content: SizedBox(
        width: 330,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                for (final label in const ['ش', 'ی', 'د', 'س', 'چ', 'پ', 'ج'])
                  Expanded(
                    child: Center(
                      child: Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            GridView.count(
              crossAxisCount: 7,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              children: [
                for (var i = 0; i < leading; i++) const SizedBox.shrink(),
                for (var day = 1; day <= days; day++)
                  InkWell(
                    customBorder: const CircleBorder(),
                    onTap: !_enabled(day)
                        ? null
                        : () {
                            setState(() => _selected = Jalali(_month.year, _month.month, day));
                          },
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isSelected(day)
                            ? theme.colorScheme.primary
                            : (_isToday(day) ? theme.colorScheme.primary.withValues(alpha: 0.12) : null),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        faDigits(day.toString()),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: _isSelected(day)
                              ? theme.colorScheme.onPrimary
                              : (!_enabled(day) ? theme.disabledColor : null),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _selected),
          child: const Text('تأیید'),
        ),
      ],
    );
  }

  bool _isSelected(int day) =>
      _selected.year == _month.year && _selected.month == _month.month && _selected.day == day;

  bool _isToday(int day) {
    final now = DateTime.now();
    final j = Jalali.fromDateTime(now);
    return j.year == _month.year && j.month == _month.month && j.day == day;
  }
}

class JalaliField extends StatelessWidget {
  const JalaliField({
    super.key,
    required this.label,
    required this.valueUtc,
    required this.onPicked,
    this.icon = Icons.event_outlined,
  });

  final String label;
  final DateTime valueUtc;
  final ValueChanged<Jalali> onPicked;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final dates = Dates();
    return InkWell(
      onTap: () async {
        final picked = await pickJalaliDate(context, initial: dates.jalali(valueUtc));
        if (picked != null) onPicked(picked);
      },
      borderRadius: BorderRadius.circular(14),
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
        child: Text(dates.longDate(valueUtc)),
      ),
    );
  }
}
