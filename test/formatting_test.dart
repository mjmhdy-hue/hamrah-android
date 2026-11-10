import 'package:flutter_test/flutter_test.dart';
import 'package:shamsi_date/shamsi_date.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import 'package:hamrah/core/formatting.dart';

void main() {
  setUpAll(tzdata.initializeTimeZones);

  group('money', () {
    test('toman hides a zero remainder', () {
      expect(formatMoney(2404048, unit: 'toman'), '۲۴۰٬۴۰۴.۸ تومان');
    });

    test('toman without decimal when divisible by ten', () {
      expect(formatMoney(2600000, unit: 'toman'), '۲۶۰٬۰۰۰ تومان');
    });

    test('rial mode keeps rial', () {
      expect(formatMoney(2404048, unit: 'rial'), '۲٬۴۰۴٬۰۴۸ ریال');
    });

    test('grouping of millions', () {
      expect(faDigits(grouped(410764899)), '۴۱۰٬۷۶۴٬۸۹۹');
    });

    test('persian digits round trip', () {
      expect(toEnDigits(faDigits('1405/08/18')), '1405/08/18');
    });
  });

  group('jalali vectors', () {
    const vectors = {
      '1405-08-01': '2026-10-23',
      '1405-08-04': '2026-10-26',
      '1405-08-09': '2026-10-31',
      '1405-08-15': '2026-11-06',
      '1405-08-16': '2026-11-07',
      '1405-08-18': '2026-11-09',
    };
    vectors.forEach((jalali, gregorian) {
      test('$jalali -> $gregorian', () {
        final parts = jalali.split('-').map(int.parse).toList();
        final g = Jalali(parts[0], parts[1], parts[2]).toGregorian();
        final text = '${g.year.toString().padLeft(4, '0')}-'
            '${g.month.toString().padLeft(2, '0')}-'
            '${g.day.toString().padLeft(2, '0')}';
        expect(text, gregorian);
      });
    });
  });

  group('tehran times', () {
    test('B1 body time is 08:35 UTC', () {
      final dates = Dates();
      final g = Jalali(1405, 8, 15).toGregorian();
      final utc = dates.toUtc(Jalali(1405, 8, 15), 12, 5);
      expect(utc.toIso8601String(), '2026-11-06T08:35:00.000Z');
      expect(dates.clock(utc), '۱۲:۰۵');
      expect(dates.date(utc), '۱۴۰۵/۰۸/۱۵');
      expect(g.year, 2026);
    });
  });
}
