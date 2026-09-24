import 'package:rolly/src/keyed_slots.dart';
import 'package:rolly/src/line_geometry.dart';
import 'package:rolly/src/numeric_format.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const style = TextStyle(fontSize: 48, fontFamily: 'Roboto');

  /// Formats [value] and returns its glyphs, keyed as the engine will see them.
  List<KeyedSlot> slotsFor(num value, NumericTextFormat format) {
    final text = format.format(value);
    return layoutKeyedSlots(
      formatted: text,
      geometry: LineGeometry.measure(text, style, TextDirection.ltr),
      groupSeparator: format.groupSeparator,
      decimalSeparator: format.decimalSeparator,
      minusSign: format.minusSign,
      zeroDigit: format.zeroDigit,
    );
  }

  Map<String, String> keyed(num value, NumericTextFormat format) => {
    for (final slot in slotsFor(value, format)) slot.key: slot.glyph,
  };

  const integer = NumericTextFormat.integer();
  const currency = NumericTextFormat.currency();

  group('tokenization', () {
    test('classifies a grouped integer', () {
      expect(keyed(1234, integer), {
        'I0': '1',
        'G3:,': ',',
        'I1': '2',
        'I2': '3',
        'I3': '4',
      });
    });

    test('separates the fraction span from the integer span', () {
      final slots = slotsFor(1000.5, currency);
      final keys = slots.map((s) => s.key).toList();

      expect(keys, contains('DEC:.'));
      expect(keys.where((k) => k.startsWith('F')).length, 2);
      expect(keys.where((k) => k.startsWith('I')).length, 4);

      // Fraction digits, the decimal mark and trailing affixes are what a second colour tints.
      expect(isFractionKey('F0'), isTrue);
      expect(isFractionKey('DEC:.'), isTrue);
      expect(isFractionKey('I0'), isFalse);
      expect(isFractionKey('G3:,'), isFalse);
    });

    test('reads a leading minus as a sign, with digit physics', () {
      final slots = slotsFor(-1, integer);
      final sign = slots.firstWhere((s) => s.key == 'S');

      expect(sign.semanticKind, TokenKind.sign);
      // Signs deliberately move like digits so they roll with the number, not on their own clock.
      expect(sign.kind, TokenKind.digit);
    });

    test('treats a percent sign as a suffix affix', () {
      const percent = NumericTextFormat.percent(minimumFractionDigits: 1);
      final slots = slotsFor(0.125, percent);

      expect(percent.format(0.125), '12.5%');
      final suffix = slots.firstWhere((s) => s.key == 'X0');
      expect(suffix.glyph, '%');
      expect(suffix.semanticKind, TokenKind.other);
    });

    test('does not mistake an affix character for a separator', () {
      // Across most of Europe the roles swap: '.' groups and ',' is the decimal mark.
      const german = NumericTextFormat.decimal(
        groupSeparator: '.',
        decimalSeparator: ',',
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
      );
      expect(german.format(1234.5), '1.234,50');

      final byKey = keyed(1234.5, german);
      expect(byKey['G3:.'], '.', reason: 'the dot groups');
      expect(byKey['DEC:,'], ',', reason: 'the comma is the decimal mark');
    });
  });

  group('identity across a transition', () {
    test('999 -> 1,000 keeps the comma stable and births exactly one digit', () {
      final before = slotsFor(999, integer).map((s) => s.key).toSet();
      final after = slotsFor(1000, integer).map((s) => s.key).toSet();

      final born = after.difference(before);
      final died = before.difference(after);

      // The new digit column is a birth; nothing dies.
      expect(born, {'I3', 'G3:,'});
      expect(died, isEmpty);

      // And crucially, the comma that appears is keyed by its distance from the end of the
      // number, so it stays the same glyph through every later magnitude change.
      final million = slotsFor(1000000, integer).map((s) => s.key).toSet();
      expect(million, containsAll({'G3:,', 'G6:,'}));
    });

    test(r'$999 -> $1,000 keeps the same $, rather than destroying it', () {
      final beforeSymbol = slotsFor(
        999,
        currency,
      ).firstWhere((s) => s.glyph == r'$');
      final afterSymbol = slotsFor(
        1000,
        currency,
      ).firstWhere((s) => s.glyph == r'$');

      // Same key => the engine rolls it to a new x instead of killing one and birthing another.
      expect(beforeSymbol.key, 'P0');
      expect(afterSymbol.key, 'P0');

      // Slot bounds are line-local, so the leading symbol sits at 0 in both lines. It is only
      // once positions are taken relative to the alignment edge - what the engine animates - that
      // the symbol has visibly moved, because the line grew around its centre.
      double centreRelative(num value) {
        final text = currency.format(value);
        final geometry = LineGeometry.measure(text, style, TextDirection.ltr);
        final slot = slotsFor(
          value,
          currency,
        ).firstWhere((s) => s.glyph == r'$');
        return slot.center - geometry.width / 2;
      }

      expect(centreRelative(1000), lessThan(centreRelative(999) - 2));
    });

    test('a same-width change births nothing', () {
      final before = slotsFor(1242, integer).map((s) => s.key).toSet();
      final after = slotsFor(1160, integer).map((s) => s.key).toSet();

      expect(
        before,
        after,
        reason: 'same structure, so every column is a roll',
      );
    });

    test('fraction digits keep identity when the integer part grows', () {
      // Anchoring fraction digits from the decimal mark rather than the left edge is what stops
      // the cents re-rolling for no reason here.
      final before = keyed(9.75, currency);
      final after = keyed(10.75, currency);

      expect(before['F0'], '7');
      expect(after['F0'], '7');
      expect(before['F1'], '5');
      expect(after['F1'], '5');
    });
  });

  test('slots come back in screen order', () {
    final slots = slotsFor(1234.56, currency);
    for (var i = 1; i < slots.length; i++) {
      expect(slots[i].center, greaterThanOrEqualTo(slots[i - 1].center));
    }
    expect(slots.map((s) => s.glyph).join(), r'$1,234.56');
  });
}
