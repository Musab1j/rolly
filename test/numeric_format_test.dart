import 'package:flutter_test/flutter_test.dart';
import 'package:rolly/rolly.dart';

/// The formatter is small, but everything downstream reads the line it produces, and the
/// tokenizer classifies glyphs by comparing them against the separators declared alongside it.
/// A wrong separator does not look wrong - it animates wrong.
void main() {
  group('decimal', () {
    test('groups the integer part in threes', () {
      const format = NumericTextFormat.decimal();
      expect(format.format(1), '1');
      expect(format.format(999), '999');
      expect(format.format(1000), '1,000');
      expect(format.format(1234567), '1,234,567');
      expect(format.format(12345), '12,345');
    });

    test('trims trailing zeros down to the minimum, and no further', () {
      const format = NumericTextFormat.decimal(
        minimumFractionDigits: 2,
        maximumFractionDigits: 4,
      );
      expect(format.format(1.5), '1.50');
      expect(format.format(1.5678), '1.5678');
      expect(
        format.format(1.56789),
        '1.5679',
        reason: 'rounded to the maximum',
      );
      expect(format.format(2), '2.00');
    });

    test('grouping can be turned off', () {
      const format = NumericTextFormat.decimal(useGrouping: false);
      expect(format.format(1234567), '1234567');
    });

    test('takes its separators from the format, not from a locale', () {
      const european = NumericTextFormat.decimal(
        groupSeparator: '.',
        decimalSeparator: ',',
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
      );
      expect(european.format(1234.5), '1.234,50');
    });
  });

  group('sign', () {
    test('is written outside the prefix, so the symbol does not move', () {
      const money = NumericTextFormat.currency();
      expect(money.format(1234.5), r'$1,234.50');
      expect(money.format(-1234.5), r'-$1,234.50');
    });

    test('is whatever the format says it is', () {
      const minus = NumericTextFormat.integer(minusSign: '−');
      expect(minus.format(-7), '−7');
    });

    test('is absent from a value that rounds to zero', () {
      const format = NumericTextFormat.decimal(maximumFractionDigits: 2);
      expect(format.format(0), '0');
      expect(format.format(-0.0), '0');
    });
  });

  group('percent', () {
    test('scales by a hundred and suffixes', () {
      const format = NumericTextFormat.percent(minimumFractionDigits: 1);
      expect(format.format(0.125), '12.5%');
      expect(format.format(1), '100.0%');
    });
  });

  group('currency', () {
    test('can carry its symbol on the right', () {
      const format = NumericTextFormat.currency(
        symbol: ' kr',
        symbolOnRight: true,
        groupSeparator: ' ',
        decimalSeparator: ',',
      );
      expect(format.format(1234.5), '1 234,50 kr');
    });
  });

  group('digits', () {
    test('can be written in another Unicode block', () {
      const arabic = NumericTextFormat.integer(zeroDigit: '٠');
      expect(arabic.format(2026), '٢,٠٢٦');
    });
  });

  group('the awkward values', () {
    test('survive rather than throwing', () {
      const format = NumericTextFormat.decimal();
      expect(format.format(double.nan), 'NaN');
      expect(format.format(double.infinity), 'Infinity');
      // Past 1e21 `toStringAsFixed` gives exponent notation, which has nothing to group.
      expect(format.format(1e22), contains('e'));
      expect(() => format.format(-1e22), returnsNormally);
    });
  });

  group('custom', () {
    test('hands formatting over entirely', () {
      final compact = NumericTextFormat.custom(
        (value) => '${(value / 1000).round()}K',
      );
      expect(compact.format(12400), '12K');
    });
  });

  group('equality', () {
    test('two formats built the same way are the same format', () {
      // The widget leans on this to tell a real format change from a rebuild that happened to
      // construct a new instance.
      expect(
        const NumericTextFormat.currency(),
        const NumericTextFormat.currency(),
      );
      expect(
        const NumericTextFormat.currency().hashCode,
        const NumericTextFormat.currency().hashCode,
      );
      expect(
        const NumericTextFormat.currency(decimalDigits: 2),
        isNot(const NumericTextFormat.currency(decimalDigits: 0)),
      );
      expect(
        const NumericTextFormat.integer(),
        isNot(const NumericTextFormat.decimal()),
      );
    });
  });
}
