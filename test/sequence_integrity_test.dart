import 'dart:math' as math;

import 'package:rolly/rolly.dart';
import 'package:rolly/src/keyed_slots.dart';
import 'package:rolly/src/line_geometry.dart';
import 'package:rolly/src/roll_engine.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// Drives the engine the way the widget does - a value change, then frames at 60Hz until the next
/// change - over a stress script, and checks after every step that what is on screen is exactly
/// what was asked for.
///
/// This is the test that catches glyphs left behind: a column that keeps a stale digit, a corpse
/// that never fades, or a duplicate that lands on top of its replacement.

/// One value, held for a while before the next.
class SequenceStep {
  const SequenceStep(this.value, this.holdMs);
  final num value;
  final int holdMs;
}

/// The script the example app plays, and the one the engine is stressed against here. Every
/// phase targets something the model has to get right, and the ordering matters:
///
///  * `1992 -> 1993 -> 1994` - isolated single-digit rolls, slow enough to read.
///  * `99 -> 100 -> 1` - structural changes in both directions: a digit born, then three dying.
///  * `0 -> -1 -> ... -> -4` - crossing zero. The critical probe: the units digit goes 0 -> 1, a
///    numeric *increase*, while the number decreases. It must roll with everything else.
///  * `1000 -> 999 -> 1000` at ~360ms - a structural change re-triggered before it finished.
///  * `+123` tightening from 360ms to 60ms - a simulated press-and-hold. The column degrades into
///    a soft pair and must recover, not stutter or snap.
///  * a decelerating rollback to 1992 - reversal while still in flight.
const showcaseSequence = <SequenceStep>[
  SequenceStep(1992, 460),
  SequenceStep(1993, 450),
  SequenceStep(1994, 450),

  SequenceStep(99, 800),
  SequenceStep(100, 800),
  SequenceStep(1, 800),

  SequenceStep(0, 650),
  SequenceStep(-1, 550),
  SequenceStep(-2, 450),
  SequenceStep(-3, 350),
  SequenceStep(-4, 300),

  SequenceStep(1000, 400),
  SequenceStep(999, 360),
  SequenceStep(1000, 360),

  SequenceStep(1123, 360),
  SequenceStep(1246, 300),
  SequenceStep(1369, 240),
  SequenceStep(1492, 180),
  SequenceStep(1615, 150),
  SequenceStep(1738, 120),
  SequenceStep(1861, 100),
  SequenceStep(1984, 80),
  SequenceStep(2107, 60),
  SequenceStep(2230, 60),
  SequenceStep(2353, 60),
  SequenceStep(2476, 60),

  SequenceStep(2353, 120),
  SequenceStep(2230, 140),
  SequenceStep(2107, 180),
  SequenceStep(1992, 660),
];

/// Picks a magnitude first, then a value inside it.
///
/// Drawing uniformly from one big range would land in the top decade almost every time, so nearly
/// every jump would have the same digit count and never exercise a structural change. Choosing the
/// number of digits first makes `7 -> 4,918,204 -> 62` as likely as anything else, which is the
/// interesting case: whole columns born and dying at once.
double _randomMagnitude(
  math.Random random, {
  required int maxDigits,
  int decimals = 0,
}) {
  final digits = 1 + random.nextInt(maxDigits);
  final value = random.nextDouble() * math.pow(10, digits);
  // A quarter of them negative, so the sign column gets born and destroyed too.
  final signed = random.nextInt(4) == 0 ? -value : value;
  return double.parse(signed.toStringAsFixed(decimals));
}

/// One shape of number, plus a source of values of deliberately unpredictable magnitude.
class FormatPreset {
  const FormatPreset(this.label, this.format, this.randomValue);
  final String label;
  final NumericTextFormat format;
  final double Function(math.Random random) randomValue;
}

/// The same formats the example app offers, each exercising a different part of the model.
final formatPresets = <FormatPreset>[
  FormatPreset(
    'Integer',
    const NumericTextFormat.integer(),
    (r) => _randomMagnitude(r, maxDigits: 7),
  ),
  FormatPreset(
    'Currency',
    const NumericTextFormat.currency(),
    (r) => _randomMagnitude(r, maxDigits: 6, decimals: 2),
  ),
  FormatPreset(
    'Percent',
    const NumericTextFormat.percent(minimumFractionDigits: 1),
    (r) => _randomMagnitude(r, maxDigits: 4, decimals: 3) / 100,
  ),
  FormatPreset(
    'Decimal',
    const NumericTextFormat.decimal(
      minimumFractionDigits: 3,
      maximumFractionDigits: 3,
    ),
    (r) => _randomMagnitude(r, maxDigits: 4, decimals: 3),
  ),
  FormatPreset(
    'European',
    const NumericTextFormat.decimal(
      groupSeparator: '.',
      decimalSeparator: ',',
      minimumFractionDigits: 2,
      maximumFractionDigits: 2,
    ),
    (r) => _randomMagnitude(r, maxDigits: 6, decimals: 2),
  ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const style = TextStyle(fontSize: 48, fontFamily: 'Roboto');

  ({List<KeyedSlot> slots, double width, double height}) lineFor(
    num value,
    NumericTextFormat format,
  ) {
    final text = format.format(value);
    final geometry = LineGeometry.measure(text, style, TextDirection.ltr);
    return (
      slots: layoutKeyedSlots(
        formatted: text,
        geometry: geometry,
        groupSeparator: format.groupSeparator,
        decimalSeparator: format.decimalSeparator,
        minusSign: format.minusSign,
        zeroDigit: format.zeroDigit,
      ),
      width: geometry.width,
      height: geometry.lineHeight,
    );
  }

  /// What the engine would actually draw, in screen order.
  String rendered(NumericRollEngine engine, double now) {
    final samples = engine.sample(now)..sort((a, b) => a.x.compareTo(b.x));
    return samples.map((s) => s.glyph).join();
  }

  /// Runs [steps] against [format], holding each value for its own duration, and returns any
  /// place where the settled output disagreed with the value it was given.
  List<String> runSequence(
    List<SequenceStep> steps,
    NumericTextFormat format, {
    required bool settleBetween,
  }) {
    final problems = <String>[];
    final first = lineFor(steps.first.value, format);
    final engine = NumericRollEngine()
      ..reset(
        slots: first.slots,
        lineWidth: first.width,
        lineHeight: first.height,
        alignFraction: 0.5,
      );

    var now = 0.0;
    num previous = steps.first.value;

    for (final step in steps.skip(1)) {
      final line = lineFor(step.value, format);
      engine.setTarget(
        slots: line.slots,
        countsDown: step.value < previous,
        now: now,
        lineWidth: line.width,
        lineHeight: line.height,
        alignFraction: 0.5,
      );
      previous = step.value;

      // Frames at 60Hz for as long as this value is held, exactly as the widget would.
      final hold = step.holdMs / 1000.0;
      final end = now + hold;
      while (now < end) {
        now += 1 / 60;
        engine.sample(now);
      }

      if (settleBetween) {
        // Let it finish, then check what is on screen.
        while (engine.isRunning(now)) {
          now += 1 / 60;
          engine.sample(now);
        }
        final shown = rendered(engine, now);
        final expected = format.format(step.value);
        if (shown != expected) {
          problems.add(
            'after ${step.value}: showed "$shown", expected "$expected"',
          );
        }
      }
    }

    // However the sequence ended, once everything settles the number must be exactly right.
    while (engine.isRunning(now)) {
      now += 1 / 60;
      engine.sample(now);
    }
    final shown = rendered(engine, now);
    final expected = format.format(previous);
    if (shown != expected) {
      problems.add('at rest: showed "$shown", expected "$expected"');
    }

    return problems;
  }

  test('the showcase sequence settles correctly at every step', () {
    final problems = runSequence(
      showcaseSequence,
      const NumericTextFormat.integer(),
      settleBetween: true,
    );
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  test('the showcase sequence survives being run at its own cadence', () {
    // No settling between steps, so the fast section genuinely interrupts itself.
    final problems = runSequence(
      showcaseSequence,
      const NumericTextFormat.integer(),
      settleBetween: false,
    );
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  test('every demo format settles correctly through a structural crossing', () {
    final cases = <String, (NumericTextFormat, List<num>)>{
      'currency': (
        const NumericTextFormat.currency(),
        [998.5, 999.5, 1000.5, 1001.5, 1000.5, 999.5, 998.5],
      ),
      'percent': (
        const NumericTextFormat.percent(minimumFractionDigits: 1),
        [0.978, 0.988, 0.998, 1.008, 0.998, 0.988],
      ),
      'decimal': (
        const NumericTextFormat.decimal(
          minimumFractionDigits: 3,
          maximumFractionDigits: 3,
        ),
        [9.996, 9.997, 9.998, 9.999, 10.0, 10.001, 9.999],
      ),
      'european separators': (
        const NumericTextFormat.decimal(
          groupSeparator: '.',
          decimalSeparator: ',',
          minimumFractionDigits: 2,
          maximumFractionDigits: 2,
        ),
        [998.5, 999.5, 1000.5, 999.5],
      ),
      'sign crossing': (
        const NumericTextFormat.integer(),
        [2, 1, 0, -1, -2, -1, 0, 1],
      ),
    };

    cases.forEach((name, testCase) {
      final (format, values) = testCase;
      final steps = [for (final value in values) SequenceStep(value, 420)];
      final problems = runSequence(steps, format, settleBetween: true);
      expect(problems, isEmpty, reason: '$name:\n${problems.join('\n')}');
    });
  });

  group('large gaps', () {
    // Seeded, so a failure is reproducible rather than a story about a flaky test.
    List<SequenceStep> randomSteps(FormatPreset preset, int count, int holdMs) {
      final random = math.Random(20260921);
      return [
        for (var i = 0; i < count; i++)
          SequenceStep(preset.randomValue(random), holdMs),
      ];
    }

    test('every preset survives 200 random jumps', () {
      for (final preset in formatPresets) {
        final problems = runSequence(
          randomSteps(preset, 200, 420),
          preset.format,
          settleBetween: true,
        );
        expect(
          problems,
          isEmpty,
          reason: '${preset.label}:\n${problems.take(5).join('\n')}',
        );
      }
    });

    test('random jumps interrupting each other still land correctly', () {
      for (final preset in formatPresets) {
        final problems = runSequence(
          randomSteps(preset, 120, 40),
          preset.format,
          settleBetween: false,
        );
        expect(
          problems,
          isEmpty,
          reason: '${preset.label}:\n${problems.take(5).join('\n')}',
        );
      }
    });

    test('a jump of any size enters from the same fixed distance', () {
      // The model's least intuitive claim: an arriving glyph's entry amplitude is fixed and does
      // not depend on how far the number moved. So a huge jump does not make any single column
      // roll further - it just gives more columns to be born. That is what a random jump is
      // demonstrating, and it is the property that fitting the offset as inter-digit spacing
      // (the natural guess) would get wrong.
      final format = const NumericTextFormat.integer();

      /// Samples the transition `from -> to` just after onset, once glyphs are perceptible.
      List<GlyphSample> arrivingGlyphs(num from, num to) {
        final before = lineFor(from, format);
        final engine = NumericRollEngine()
          ..reset(
            slots: before.slots,
            lineWidth: before.width,
            lineHeight: before.height,
            alignFraction: 0.5,
          );
        final after = lineFor(to, format);
        engine.setTarget(
          slots: after.slots,
          countsDown: to < from,
          now: 0,
          lineWidth: after.width,
          lineHeight: after.height,
          alignFraction: 0.5,
        );

        // A structural change commits every column together, and a single-column change has no
        // stagger either, so both cases can be read at the same instant.
        final incoming = {for (final slot in after.slots) slot.key: slot.glyph};
        return engine
            .sample(0.03)
            .where((s) => incoming[s.key] == s.glyph)
            .toList();
      }

      // Integer digits are keyed from the left, so I0 is the leading column - the one that
      // survives in both of these.
      double leadOffset(List<GlyphSample> samples) =>
          samples.firstWhere((s) => s.key == 'I0').dy;

      final small = arrivingGlyphs(7, 8);
      final huge = arrivingGlyphs(7, 4918204);

      expect(
        leadOffset(huge),
        closeTo(leadOffset(small), 0.001),
        reason:
            'a jump of 4,918,197 must enter from exactly as far as a jump of 1',
      );

      // And the six columns the big jump added are births, which have no vertical entry at all.
      final born = huge.where((s) => s.key != 'I0' && s.key.startsWith('I'));
      expect(born, hasLength(6));
      expect(born.every((s) => s.dy.abs() < 0.001), isTrue);
    });
  });

  test('a fast burst still lands on the right number', () {
    // Every step interrupts the previous one well before it resolves.
    final steps = [for (var i = 0; i < 60; i++) SequenceStep(990 + i, 30)];
    final problems = runSequence(
      steps,
      const NumericTextFormat.integer(),
      settleBetween: false,
    );
    expect(problems, isEmpty, reason: problems.join('\n'));
  });
}
