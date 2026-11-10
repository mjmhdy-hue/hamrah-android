import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/formatting.dart';
import '../core/theme.dart';
import '../providers.dart';

const _icons = <String, IconData>{
  'restaurant': Icons.restaurant_outlined,
  'directions_bus': Icons.directions_bus_outlined,
  'receipt': Icons.receipt_long_outlined,
  'wifi': Icons.wifi_outlined,
  'shopping_bag': Icons.shopping_bag_outlined,
  'health_and_safety': Icons.health_and_safety_outlined,
  'celebration': Icons.celebration_outlined,
  'more_horiz': Icons.more_horiz,
  'payments': Icons.payments_outlined,
  'add_card': Icons.add_card_outlined,
  'swap_horiz': Icons.swap_horiz,
  'category': Icons.category_outlined,
  'bank': Icons.account_balance_outlined,
  'wallet': Icons.account_balance_wallet_outlined,
};

IconData iconFor(String? name) => _icons[name] ?? Icons.category_outlined;

String unitFrom(Map<String, String>? settings) => settings?['display_unit'] ?? 'toman';

class UnitScope extends ConsumerWidget {
  const UnitScope({super.key, required this.builder});
  final Widget Function(BuildContext context, String unit) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unit = unitFrom(ref.watch(settingsStreamProvider).asData?.value);
    return builder(context, unit);
  }
}

class AmountText extends ConsumerWidget {
  const AmountText({
    super.key,
    required this.rial,
    required this.direction,
    this.style,
    this.showSign = true,
    this.large = false,
  });

  final int rial;
  final String direction;
  final TextStyle? style;
  final bool showSign;
  final bool large;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unit = unitFrom(ref.watch(settingsStreamProvider).asData?.value);
    final hide = ref.watch(settingsStreamProvider).asData?.value?['hide_amounts_always'] == '1';
    final theme = Theme.of(context);
    final color = direction == 'in' ? HamrahColors.income : HamrahColors.expense;
    final base = style ?? (large ? theme.textTheme.headlineSmall : theme.textTheme.titleMedium);
    if (hide) {
      return Text('•••••', style: base?.copyWith(color: color, fontWeight: FontWeight.w700));
    }
    final sign = showSign ? (direction == 'in' ? '+' : '−') : '';
    return Text(
      '$sign${formatMoney(rial, unit: unit)}',
      textDirection: TextDirection.rtl,
      style: base?.copyWith(color: color, fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()]),
    );
  }
}

class AmountPlain extends ConsumerWidget {
  const AmountPlain({super.key, required this.rial, this.style, this.color});
  final int rial;
  final TextStyle? style;
  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unit = unitFrom(ref.watch(settingsStreamProvider).asData?.value);
    return Text(
      formatMoney(rial, unit: unit),
      style: (style ?? Theme.of(context).textTheme.titleMedium)?.copyWith(color: color),
    );
  }
}

class CategoryAvatar extends StatelessWidget {
  const CategoryAvatar({super.key, this.icon, this.color, this.size = 42});
  final String? icon;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size / 3),
      ),
      child: Icon(iconFor(icon), size: size * 0.5, color: tint),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.trailing, this.subtitle});
  final String title;
  final Widget? trailing;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
                  ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class HamrahCard extends StatelessWidget {
  const HamrahCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap});
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.title, this.message, this.icon = Icons.inbox_outlined, this.action});
  final String title;
  final String? message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(message!, style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.center),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

class InfoRow extends StatelessWidget {
  const InfoRow({super.key, required this.label, required this.value, this.trailing, this.icon});
  final String label;
  final String value;
  final Widget? trailing;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
          Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.left,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class PersianDigitsText extends StatelessWidget {
  const PersianDigitsText(this.text, {super.key, this.style});
  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Text(faDigits(text), style: style);
}
