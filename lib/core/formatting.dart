import 'package:shamsi_date/shamsi_date.dart';
import 'package:timezone/timezone.dart' as tz;

const _faDigits = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];
const _months = [
  'فروردین', 'اردیبهشت', 'خرداد', 'تیر', 'مرداد', 'شهریور',
  'مهر', 'آبان', 'آذر', 'دی', 'بهمن', 'اسفند'
];
const _weekdays = ['شنبه', 'یک‌شنبه', 'دوشنبه', 'سه‌شنبه', 'چهارشنبه', 'پنج‌شنبه', 'جمعه'];

String faDigits(String input) {
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    if (rune >= 0x30 && rune <= 0x39) {
      buffer.write(_faDigits[rune - 0x30]);
    } else {
      buffer.write(String.fromCharCode(rune));
    }
  }
  return buffer.toString();
}

String toEnDigits(String input) {
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    final index = _faDigits.indexOf(String.fromCharCode(rune));
    buffer.write(index >= 0 ? index.toString() : String.fromCharCode(rune));
  }
  return buffer.toString();
}

String grouped(int value) {
  final raw = value.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < raw.length; i++) {
    if (i > 0 && (raw.length - i) % 3 == 0) buffer.write('٬');
    buffer.write(raw[i]);
  }
  return (value < 0 ? '−' : '') + buffer.toString();
}

/// Default display is Toman (Rial / 10) with one decimal digit only when needed.
String formatMoney(int rial, {required String unit}) {
  if (unit == 'rial') return '${faDigits(grouped(rial))} ریال';
  final toman = rial ~/ 10;
  final remainder = rial % 10;
  if (remainder == 0) return '${faDigits(grouped(toman))} تومان';
  return '${faDigits(grouped(toman))}.${faDigits(remainder.toString())} تومان';
}

String formatAmount(int rial, {required String unit}) {
  if (unit == 'rial') return faDigits(grouped(rial));
  final toman = rial / 10;
  final text = toman == toman.roundToDouble() ? grouped(toman.round()) : toman.toStringAsFixed(1).replaceAll('.', '٫');
  return faDigits(text);
}

/// Formatting of UTC timestamps in Asia/Tehran, with Jalali dates.
class Dates {
  Dates() : _tehran = tz.getLocation('Asia/Tehran');

  final tz.Location _tehran;

  tz.TZDateTime local(DateTime utc) => tz.TZDateTime.from(utc, _tehran);

  Jalali jalali(DateTime utc) {
    final l = local(utc);
    return Jalali.fromDateTime(DateTime(l.year, l.month, l.day));
  }

  String clock(DateTime utc) {
    final l = local(utc);
    return faDigits('${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}');
  }

  String date(DateTime utc) {
    final j = jalali(utc);
    return faDigits('${j.year}/${j.month.toString().padLeft(2, '0')}/${j.day.toString().padLeft(2, '0')}');
  }

  String longDate(DateTime utc) {
    final j = jalali(utc);
    return '${faDigits(j.day.toString())} ${_months[j.month - 1]} ${faDigits(j.year.toString())}';
  }

  String dateWithWeekday(DateTime utc) {
    final l = local(utc);
    final weekdayIndex = (l.weekday + 1) % 7; // DateTime.monday == 1 -> دوشنبه
    return '${_weekdays[weekdayIndex]} ${longDate(utc)}';
  }

  String monthLabel(int year, int month) => '${_months[month - 1]} ${faDigits(year.toString())}';

  String dayKey(DateTime utc) => date(utc);

  String startOfJalaliDay(Jalali j) {
    final g = j.toGregorian();
    return faDigits('${g.year}/${g.month.toString().padLeft(2, '0')}/${g.day.toString().padLeft(2, '0')}');
  }

  DateTime toUtc(Jalali j, int hour, int minute) {
    final g = j.toGregorian();
    final l = tz.TZDateTime(_tehran, g.year, g.month, g.day, hour, minute);
    return l.toUtc();
  }

  DateTime startOfTodayUtc() {
    final now = tz.TZDateTime.now(_tehran);
    return tz.TZDateTime(_tehran, now.year, now.month, now.day).toUtc();
  }

  bool isToday(DateTime utc) {
    final j = jalali(utc);
    final n = jalali(DateTime.now().toUtc());
    return j.year == n.year && j.month == n.month && j.day == n.day;
  }

  bool isTomorrow(DateTime utc) {
    final tomorrow = tz.TZDateTime.now(_tehran).add(const Duration(days: 1));
    final g = Jalali(tomorrow.year, tomorrow.month, tomorrow.day);
    final j = jalali(utc);
    return j.year == g.year && j.month == g.month && j.day == g.day;
  }
}

class JalaliMath {
  static int daysInMonth(int year, int month) => Jalali(year, month, 1).monthLength;

  static Jalali addMonths(Jalali value, int delta) {
    var year = value.year;
    var month = value.month + delta;
    while (month > 12) {
      month -= 12;
      year += 1;
    }
    while (month < 1) {
      month += 12;
      year -= 1;
    }
    final day = value.day.clamp(1, daysInMonth(year, month));
    return Jalali(year, month, day);
  }

  static const monthNames = _months;
  static const weekdayNames = _weekdays;
}
