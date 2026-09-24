import 'package:rolly/src/keyed_slots.dart';
import 'package:rolly/src/line_geometry.dart';
import 'package:rolly/src/numeric_format.dart';
import 'package:rolly/src/roll_engine.dart';
import 'package:rolly/src/transition_model.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// These exercise the behaviours that distinguish this transition from a generic animated
/// counter: one global roll direction, a left-to-right cascade on a fixed budget, structural
/// changes that appear in place instead of rolling, and interruption that never cancels anything.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const style = TextStyle(fontSize: 48, fontFamily: 'Roboto');
  const format = NumericTextFormat.integer();

  ({List<KeyedSlot> slots, double width, double lineHeight}) lineFor(
    num value,
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
      lineHeight: geometry.lineHeight,
    );
  }

  /// An engine settled on [from], then told to go to [to] at t=0.
  NumericRollEngine transition(num from, num to) {
    final before = lineFor(from);
    final after = lineFor(to);
    final engine = NumericRollEngine()
      ..reset(
        slots: before.slots,
        lineWidth: before.width,
        lineHeight: before.lineHeight,
        alignFraction: 0.5,
      )
      ..setTarget(
        slots: after.slots,
        countsDown: to < from,
        now: 0,
        lineWidth: after.width,
        lineHeight: after.lineHeight,
        alignFraction: 0.5,
      );
    return engine;
  }

  /// The first instant each column's glyph for [char] becomes perceptible - which is that
  /// column's place in the cascade.
  Map<String, double> onsets(
    NumericRollEngine engine,
    Map<String, String> wanted,
  ) {
    final found = <String, double>{};
    for (var step = 0; step <= 600; step++) {
      final t = step / 1000.0;
      for (final sample in engine.sample(t)) {
        final want = wanted[sample.key];
        if (want == null || found.containsKey(sample.key)) continue;
        if (sample.glyph == want && sample.alpha > 0.02) found[sample.key] = t;
      }
    }
    return found;
  }

  /// The dy each arriving glyph shows on the first frame it is visible.
  ///
  /// Sampling at t=0 would only catch the cascade's leader - the others have not started yet, and
  /// correctly render nothing - so each column is observed at its own onset.
  Map<String, double> arrivalOffsets(
    NumericRollEngine engine,
    Map<String, String> arriving,
  ) {
    final found = <String, double>{};
    for (var step = 0; step <= 400; step++) {
      for (final sample in engine.sample(step / 1000.0)) {
        if (found.containsKey(sample.key)) continue;
        if (arriving[sample.key] == sample.glyph && sample.alpha > 0.02) {
          found[sample.key] = sample.dy;
        }
      }
    }
    return found;
  }

  group('direction is global to the transition', () {
    test(
      'every arriving glyph rolls the same way, even one whose digit increases',
      () {
        // 1,242 -> 1,160 is the case that rules out per-digit direction: the number goes down, but
        // the third digit goes 4 -> 6, which is up. It must still roll downward with the rest.
        final dys = arrivalOffsets(transition(1242, 1160), {
          'I1': '1',
          'I2': '6',
          'I3': '0',
        });

        expect(dys.keys, hasLength(3));
        // Counting down: arriving glyphs start below the line and rise into place.
        expect(
          dys.values.every((dy) => dy > 0),
          isTrue,
          reason: 'all should arrive from below: $dys',
        );
      },
    );

    test('0 -> -1 rolls down although the units digit goes 0 -> 1', () {
      final dys = arrivalOffsets(transition(0, -1), {'I0': '1'});

      expect(dys['I0'], isNotNull);
      expect(dys['I0']!, greaterThan(0));
    });

    test('counting up mirrors it', () {
      final dys = arrivalOffsets(transition(1160, 1242), {
        'I1': '2',
        'I2': '4',
        'I3': '2',
      });

      expect(dys.keys, hasLength(3));
      expect(
        dys.values.every((dy) => dy < 0),
        isTrue,
        reason: 'all should arrive from above: $dys',
      );
    });
  });

  group('the cascade', () {
    test(
      'spreads changing columns over a fixed 0.15s budget, leftmost first',
      () {
        final engine = transition(1242, 1160);
        final found = onsets(engine, {'I1': '1', 'I2': '6', 'I3': '0'});

        expect(found.keys, hasLength(3));

        // Three changing columns => gap of 0.15 / 2 = 75ms.
        final gap = NumericTransitionModel.cascadeTotalSeconds / 2;
        expect(found['I2']! - found['I1']!, closeTo(gap, 0.012));
        expect(found['I3']! - found['I2']!, closeTo(gap, 0.012));

        // Most significant leads.
        expect(found['I1']!, lessThan(found['I2']!));
        expect(found['I2']!, lessThan(found['I3']!));
      },
    );

    test(
      'is a budget, not a per-column delay: more columns means tighter spacing',
      () {
        final two = onsets(transition(11, 22), {'I0': '2', 'I1': '2'});
        final four = onsets(transition(1111, 2222), {
          'I0': '2',
          'I1': '2',
          'I2': '2',
          'I3': '2',
        });

        final twoSpan = two['I1']! - two['I0']!;
        final fourSpan = four['I3']! - four['I0']!;

        // Both span the same total, so a long number does not take proportionally longer.
        expect(
          twoSpan,
          closeTo(NumericTransitionModel.cascadeTotalSeconds, 0.015),
        );
        expect(
          fourSpan,
          closeTo(NumericTransitionModel.cascadeTotalSeconds, 0.015),
        );
      },
    );

    test('a single changing column starts immediately', () {
      final found = onsets(transition(1242, 1243), {'I3': '3'});
      expect(found['I3']!, lessThan(0.06));
    });

    test(
      'a structural change does not stagger - everything commits together',
      () {
        // 999 -> 1,000 re-lays-out the whole line; staggering against that reads as a stumble.
        final engine = transition(999, 1000);
        final found = onsets(engine, {
          'I0': '1',
          'I1': '0',
          'I2': '0',
          'I3': '0',
        });

        expect(found.keys, hasLength(4));
        final spread =
            found.values.reduce((a, b) => a > b ? a : b) -
            found.values.reduce((a, b) => a < b ? a : b);
        expect(spread, lessThan(0.03), reason: 'onsets: $found');
      },
    );
  });

  group('structural changes', () {
    test('a born digit appears in place, with no vertical entry', () {
      final engine = transition(999, 1000);

      // I3 is the new fourth column. A rolling glyph would start 0.59 glyph heights away; a
      // structural birth starts exactly where it will end up.
      for (var step = 0; step <= 60; step++) {
        final born = engine
            .sample(step / 100.0)
            .where((s) => s.key == 'I3')
            .toList();
        for (final sample in born) {
          expect(
            sample.dy.abs(),
            lessThan(0.001),
            reason: 'at t=${step / 100}',
          );
        }
      }
    });

    test('a born digit grows from the measured birth scale', () {
      final engine = transition(999, 1000);
      final first = engine.sample(0.0).where((s) => s.key == 'I3');

      // It may still be under the render threshold on the very first frame; if visible, it must
      // be at birth scale.
      for (final sample in first) {
        expect(sample.scale, closeTo(NumericTransitionModel.bornScale, 0.02));
      }

      final settled = engine.sample(2.0).firstWhere((s) => s.key == 'I3');
      expect(settled.scale, closeTo(1.0, 0.01));
      expect(settled.alpha, closeTo(1.0, 0.01));
    });

    test('a dying column fades where it stands rather than riding the reflow', () {
      // 1,000 -> 999 loses a digit and a comma, and the line contracts around its centre.
      final engine = transition(1000, 999);

      final xs = <double>[];
      for (var step = 0; step <= 40; step++) {
        final dying = engine.sample(step / 100.0).where((s) => s.key == 'I3');
        for (final sample in dying) {
          xs.add(sample.x);
        }
      }

      expect(xs, isNotEmpty);
      // Frozen: every observation is at the same x. Letting corpses follow the contraction slides
      // them all toward the centre and piles them into a smear.
      expect(xs.every((x) => (x - xs.first).abs() < 0.001), isTrue);
    });

    test('surviving glyphs do slide to their new positions', () {
      final engine = transition(999, 1000);
      final firstX = engine.sample(0.0).firstWhere((s) => s.key == 'I0').x;
      final lastX = engine.sample(2.0).firstWhere((s) => s.key == 'I0').x;

      expect(lastX, isNot(closeTo(firstX, 1.0)), reason: 'the line got wider');
    });
  });

  group('interruption', () {
    test(
      'a retarget mid-flight adds a glyph without removing the one in flight',
      () {
        final before = lineFor(5);
        final engine = NumericRollEngine()
          ..reset(
            slots: before.slots,
            lineWidth: before.width,
            lineHeight: before.lineHeight,
            alignFraction: 0.5,
          );

        void go(num value, double now) {
          final line = lineFor(value);
          engine.setTarget(
            slots: line.slots,
            countsDown: false,
            now: now,
            lineWidth: line.width,
            lineHeight: line.lineHeight,
            alignFraction: 0.5,
          );
        }

        go(6, 0.0);
        go(7, 0.04); // 40ms later, well inside the first transition

        final live = engine.sample(0.06).where((s) => s.key == 'I0').toList();
        expect(
          live.length,
          greaterThanOrEqualTo(3),
          reason: 'saw ${live.map((s) => s.glyph)}',
        );
        expect(live.map((s) => s.glyph), containsAll(['5', '6', '7']));
      },
    );

    /// Runs [changes] value changes [cadence] apart and reports the busiest frame seen.
    ({int live, int perceptible, List<double> finalAlphas}) burst({
      required double cadence,
      required int changes,
    }) {
      final before = lineFor(0);
      final engine = NumericRollEngine()
        ..reset(
          slots: before.slots,
          lineWidth: before.width,
          lineHeight: before.lineHeight,
          alignFraction: 0.5,
        );

      var now = 0.0;
      var live = 0;
      var perceptible = 0;
      var last = <double>[];

      for (var i = 1; i <= changes; i++) {
        now += cadence;
        final line = lineFor(i % 10);
        engine.setTarget(
          slots: line.slots,
          countsDown: false,
          now: now,
          lineWidth: line.width,
          lineHeight: line.lineHeight,
          alignFraction: 0.5,
        );

        // Look across the gap, not only at the instant of the commit.
        for (var step = 0; step < 4; step++) {
          final alphas = [
            for (final sample in engine.sample(now + step * cadence / 4))
              if (sample.key == 'I0') sample.alpha,
          ];
          live = alphas.length > live ? alphas.length : live;
          final visible = alphas.where((a) => a >= 0.1).length;
          perceptible = visible > perceptible ? visible : perceptible;
          last = alphas;
        }
      }

      return (live: live, perceptible: perceptible, finalAlphas: last);
    }

    test('a burst leaves only a few perceptible glyphs, not a pile', () {
      // A ~30ms burst leaves 3 (sometimes 4) glyphs meaningfully alive, against 2 for an
      // isolated change. The rest are present but far below the perceptual floor, which is what
      // "degrades into a soft pair" means.
      final fast = burst(cadence: 0.03, changes: 40);
      expect(fast.perceptible, inInclusiveRange(2, 4));

      final tap = burst(cadence: 0.22, changes: 10);
      expect(tap.perceptible, inInclusiveRange(1, 2));
    });

    test('the stack stays bounded however long the burst runs', () {
      // Nothing is ever cancelled, so the only thing stopping unbounded growth is that faded
      // glyphs get culled. A press-and-hold lasting 4 seconds must cost no more than a short one.
      final short = burst(cadence: 0.03, changes: 20);
      final long = burst(cadence: 0.03, changes: 140);

      expect(long.live, lessThanOrEqualTo(short.live + 1));
      expect(long.live, lessThan(12));
    });

    test('recovers to a single sharp glyph once the changes stop', () {
      final before = lineFor(0);
      final engine = NumericRollEngine()
        ..reset(
          slots: before.slots,
          lineWidth: before.width,
          lineHeight: before.lineHeight,
          alignFraction: 0.5,
        );

      var now = 0.0;
      for (var i = 1; i <= 30; i++) {
        now += 0.03;
        final line = lineFor(i % 10);
        engine.setTarget(
          slots: line.slots,
          countsDown: false,
          now: now,
          lineWidth: line.width,
          lineHeight: line.lineHeight,
          alignFraction: 0.5,
        );
        engine.sample(now);
      }

      final settled = engine.sample(now + 3.0);
      expect(settled, hasLength(1));
      expect(settled.single.alpha, closeTo(1.0, 0.01));
      expect(settled.single.sigma, 0);
    });

    test('the crossfade stays convex: alphas in a column never exceed 1', () {
      final before = lineFor(0);
      final engine = NumericRollEngine()
        ..reset(
          slots: before.slots,
          lineWidth: before.width,
          lineHeight: before.lineHeight,
          alignFraction: 0.5,
        );

      var now = 0.0;
      for (var i = 1; i <= 20; i++) {
        now += 0.05;
        final line = lineFor(i % 10);
        engine.setTarget(
          slots: line.slots,
          countsDown: false,
          now: now,
          lineWidth: line.width,
          lineHeight: line.lineHeight,
          alignFraction: 0.5,
        );

        for (var step = 0; step < 5; step++) {
          final byColumn = <String, double>{};
          for (final sample in engine.sample(now + step * 0.01)) {
            byColumn[sample.key] = (byColumn[sample.key] ?? 0) + sample.alpha;
          }
          for (final entry in byColumn.entries) {
            expect(
              entry.value,
              lessThanOrEqualTo(1.001),
              reason: 'column ${entry.key} summed to ${entry.value}',
            );
          }
        }
      }
    });
  });

  group('settling', () {
    test('stops running once every glyph has arrived', () {
      final engine = transition(999, 1000);

      expect(engine.isRunning(0.1), isTrue);
      expect(engine.isRunning(5.0), isFalse);
    });

    test('ends with exactly the target glyphs, sharp and opaque', () {
      final engine = transition(1242, 1160);
      final settled = engine.sample(3.0);

      expect(settled.map((s) => s.glyph).join(), '1,160');
      for (final sample in settled) {
        expect(sample.alpha, closeTo(1.0, 0.01));
        expect(sample.scale, closeTo(1.0, 0.01));
        expect(sample.sigma, 0);
        expect(sample.dy.abs(), lessThan(0.05));
      }
    });

    test('duration scaling stretches the whole transition together', () {
      final before = lineFor(1242);
      final after = lineFor(1160);

      double settleTimeAt(double scale) {
        final engine = NumericRollEngine()..setDurationScale(scale);
        engine
          ..reset(
            slots: before.slots,
            lineWidth: before.width,
            lineHeight: before.lineHeight,
            alignFraction: 0.5,
          )
          ..setTarget(
            slots: after.slots,
            countsDown: true,
            now: 0,
            lineWidth: after.width,
            lineHeight: after.lineHeight,
            alignFraction: 0.5,
          );
        var t = 0.0;
        while (engine.isRunning(t) && t < 30) {
          t += 0.01;
        }
        return t;
      }

      final fast = settleTimeAt(0.5);
      final slow = settleTimeAt(2.0);
      // The cascade budget is fixed, so the ratio is not exactly 4x - but it must scale.
      expect(slow, greaterThan(fast * 2.5));
    });
  });
}
