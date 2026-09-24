import 'package:rolly/src/keyed_slots.dart';
import 'package:rolly/src/line_geometry.dart';
import 'package:rolly/src/text_slots.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const style = TextStyle(fontSize: 48, fontFamily: 'Roboto');

  group('alignUnits', () {
    test('an unchanged line keeps every identity', () {
      expect(alignUnits(['a', 'b', 'c'], ['a', 'b', 'c']), [0, 1, 2]);
    });

    test('an insertion is the only thing without an identity', () {
      // The `b` keeps its own even though it moved along one place, so it slides rather than
      // being rebuilt where it lands.
      expect(alignUnits(['a', 'b'], ['a', 'x', 'b']), [0, -1, 1]);
    });

    test('a deletion leaves its neighbours alone', () {
      expect(alignUnits(['a', 'b', 'c'], ['a', 'c']), [0, 2]);
    });

    test('a replaced run is paired off in place, and the overflow is born', () {
      // ON -> OFF. The F that stands where the N stood takes its column and rolls into it;
      // only the second F is new.
      expect(alignUnits(['O', 'N'], ['O', 'F', 'F']), [0, 1, -1]);
    });

    test('a replacement of equal length rolls every column', () {
      expect(alignUnits(['c', 'a', 't'], ['c', 'o', 't']), [0, 1, 2]);
    });

    test('a line arriving from nothing is entirely new', () {
      expect(alignUnits(const [], ['a', 'b']), [-1, -1]);
    });

    test('a line emptying takes nothing with it', () {
      expect(alignUnits(['a', 'b'], const []), isEmpty);
    });

    test(
      'pairs positionally rather than going quadratic on a very long line',
      () {
        final long = List.filled(400, 'a');
        final other = List.filled(400, 'b');

        // Past the guard the diff is abandoned, so every column simply rolls into the one that
        // stands where it stood.
        expect(alignUnits(long, other), List.generate(400, (i) => i));
      },
    );
  });

  group('TextSlotKeyer', () {
    /// Keys [text] as the engine will see it, threading the keyer's history through.
    List<KeyedSlot> line(TextSlotKeyer keyer, String text) => keyer.assign(
      text,
      LineGeometry.measure(text, style, TextDirection.ltr),
    );

    Map<String, String> keyed(TextSlotKeyer keyer, String text) => {
      for (final slot in line(keyer, text)) slot.key: slot.glyph,
    };

    /// The units of [text] in reading order. Slots come back in *screen* order, which for a
    /// right-to-left line is the reverse of this.
    List<String> units(TextSlotKeyer keyer, String text) =>
        ([...line(keyer, text)]
              ..sort((a, b) => a.utf16Start.compareTo(b.utf16Start)))
            .map((slot) => slot.glyph)
            .toList();

    test(
      'a character that survives keeps its key, so it reflows instead of being rebuilt',
      () {
        final keyer = TextSlotKeyer(TextSplit.character);

        expect(keyed(keyer, 'Saved'), {
          't0': 'S',
          't1': 'a',
          't2': 'v',
          't3': 'e',
          't4': 'd',
        });

        // `Sav` is untouched and merely reflows. `e` and `d` hand their columns to `i` and `n`,
        // which is what makes those two roll; only the `g` on the end is genuinely new.
        expect(keyed(keyer, 'Saving'), {
          't0': 'S',
          't1': 'a',
          't2': 'v',
          't3': 'i',
          't4': 'n',
          't5': 'g',
        });
      },
    );

    test('a replaced character reuses its column, so the engine rolls it', () {
      final keyer = TextSlotKeyer(TextSplit.character);

      final before = keyed(keyer, 'cat');
      final after = keyed(keyer, 'cot');

      expect(before.values.join(), 'cat');
      expect(after.values.join(), 'cot');
      // Same three columns, one of them now showing something else.
      expect(after.keys, before.keys);
    });

    test('keys never collide with the numeric namespace', () {
      final keyer = TextSlotKeyer(TextSplit.character);
      final slots = keyer.assign(
        '1.50',
        LineGeometry.measure('1.50', style, TextDirection.ltr),
      );

      // A text key that looked like a fraction key would take the fraction colour, and worse,
      // could collide with a column a NumericText had left behind.
      expect(slots.every((slot) => !isFractionKey(slot.key)), isTrue);
    });

    test('a fresh key is never one that a dying column might still hold', () {
      final keyer = TextSlotKeyer(TextSplit.character);

      final first = keyed(keyer, 'a');
      keyed(keyer, 'b'); // the `a` column is reused...
      final third = keyed(
        keyer,
        'ab',
      ); // ...and a second column is born beside it.

      expect(third.keys, containsAll(first.keys));
      expect(third.length, 2);
    });

    test('word splitting animates whole words', () {
      final keyer = TextSlotKeyer(TextSplit.word);

      final before = keyed(keyer, 'now loading');
      expect(before.values, ['now', 'loading']);

      final after = keyed(keyer, 'now done');
      expect(after.values, ['now', 'done']);
      // `now` survives; `loading` is replaced in its own column rather than letter by letter.
      expect(after.keys, before.keys);
    });

    test('word splitting ignores the space between words', () {
      final keyer = TextSlotKeyer(TextSplit.word);
      expect(keyed(keyer, '  two  words  ').values, ['two', 'words']);
    });

    test('character splitting keeps a run of joining script whole', () {
      final keyer = TextSlotKeyer(TextSplit.character);

      // Every unit is laid out on its own, so cutting between two Arabic letters would render
      // both in their isolated forms at positions measured for their joined ones - the word comes
      // apart and stops reading as what it says.
      expect(units(keyer, 'جاري التحميل'), ['جاري', ' ', 'التحميل']);
    });

    test(
      'a joining run is laid out where the eye sees it, not where the string has it',
      () {
        final keyer = TextSlotKeyer(TextSplit.character);

        // Screen order, so the cascade runs left to right on screen. For a right-to-left line that
        // is the reverse of reading order, and the two genuinely differ.
        expect(keyed(keyer, 'جاري التحميل').values, ['التحميل', ' ', 'جاري']);
      },
    );

    test('a joining run does not swallow what sits beside it', () {
      final keyer = TextSlotKeyer(TextSplit.character);

      // Latin either side still animates letter by letter, and the digit keeps a column of its
      // own - a numeral glued to the word beside it could never roll on its own.
      expect(units(keyer, 'Up 3 ملفات'), ['U', 'p', ' ', '3', ' ', 'ملفات']);
    });

    test('Arabic punctuation and numerals do not join', () {
      final keyer = TextSlotKeyer(TextSplit.character);

      // U+060C is a comma and U+0661..U+0663 are Arabic-Indic digits; none of them join, so
      // gluing them to the letters would cost animation boundaries for nothing.
      expect(units(keyer, 'ملف، ١٢٣'), ['ملف', '،', ' ', '١', '٢', '٣']);
    });

    test('a joining run still rolls into its replacement', () {
      final keyer = TextSlotKeyer(TextSplit.character);

      final before = keyed(keyer, 'جاري التحميل');
      final after = keyed(keyer, 'تم التحميل');

      // The space and the second word survive; the first word hands its column over, so it rolls
      // rather than dissolving and popping. (Screen order again, so the replaced word is last.)
      expect(after.values, ['التحميل', ' ', 'تم']);
      expect(after.keys, before.keys);
    });

    test('character splitting keeps a grapheme cluster whole', () {
      final keyer = TextSlotKeyer(TextSplit.character);
      // A family emoji is several code points and one character; splitting it would animate the
      // pieces apart.
      expect(keyed(keyer, 'a👨‍👩‍👧b').values, ['a', '👨‍👩‍👧', 'b']);
    });

    test('resetting forgets the line on screen', () {
      final keyer = TextSlotKeyer(TextSplit.character);

      final before = keyed(keyer, 'abc');
      keyer.reset();
      final after = keyed(keyer, 'abc');

      // Nothing on screen survives a snap, so nothing may be matched against it either.
      expect(after.keys.toSet().intersection(before.keys.toSet()), isEmpty);
    });
  });
}
