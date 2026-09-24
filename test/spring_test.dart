import 'dart:math' as math;

import 'package:rolly/src/spring.dart';
import 'package:rolly/src/transition_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// These tests pin the curves to the shape the transition is supposed to have. They are the
/// reason to trust that this is the iOS motion and not merely something spring-shaped: if a
/// constant drifts, the numbers here stop matching.
void main() {
  /// Samples a curve densely over [seconds] and reports where it peaks and where it first
  /// reaches 1.
  ({double peak, double tPeak, double tCross}) profile(
    SpringResponse spring, {
    double seconds = 2.0,
    int steps = 40000,
  }) {
    var peak = 0.0;
    var tPeak = 0.0;
    var tCross = double.nan;
    for (var i = 0; i <= steps; i++) {
      final t = i / steps * seconds;
      final v = spring.value(t);
      if (v > peak) {
        peak = v;
        tPeak = t;
      }
      if (tCross.isNaN && v >= 1.0) tCross = t;
    }
    return (peak: peak, tPeak: tPeak, tCross: tCross);
  }

  group('offset channel', () {
    test(
      'overshoots by the amount the closed form predicts for its damping',
      () {
        const z = 0.55;
        // Standard second-order result: peak overshoot = exp(-pi*z/sqrt(1-z^2)).
        final predicted = math.exp(-math.pi * z / math.sqrt(1 - z * z));
        final measured =
            profile(NumericTransitionModel.offsetSpring).peak - 1.0;

        expect(predicted, closeTo(0.126, 0.001));
        expect(measured, closeTo(predicted, 1e-4));
      },
    );

    test('overshoots to -0.072 glyph heights at ~135ms', () {
      final p = profile(NumericTransitionModel.offsetSpring);

      // An arriving glyph crosses its resting line ~135ms after onset.
      expect(p.tCross * 1000, closeTo(135, 15));

      // ...and overshooting to -0.072 glyph heights past it. dy = entryOffset * (1 - value), so
      // the furthest excursion past rest is entryOffset * (peak - 1).
      final overshootInGlyphHeights =
          (p.peak - 1.0) * NumericTransitionModel.entryOffset;
      expect(overshootInGlyphHeights, closeTo(0.072, 0.005));
    });

    test('has settled back by ~390ms', () {
      final spring = NumericTransitionModel.offsetSpring;
      // Past this point the glyph is at rest.
      for (var t = 0.39; t <= 1.0; t += 0.005) {
        expect((spring.value(t) - 1.0).abs(), lessThan(0.02));
      }
    });
  });

  group('scale and alpha channels', () {
    test('never overshoot', () {
      // Measured as critically damped. If either ever exceeded 1 a digit would visibly inflate
      // past its final size, or flash brighter than the text around it.
      expect(
        profile(NumericTransitionModel.scaleSpring).peak,
        lessThanOrEqualTo(1.0),
      );
      expect(
        profile(NumericTransitionModel.alphaSpring).peak,
        lessThanOrEqualTo(1.0),
      );
    });

    test('start with zero slope, giving an arriving glyph its dead zone', () {
      const spring = NumericTransitionModel.alphaSpring;
      // A critically damped step response leaves the origin flat, so a glyph stays imperceptible
      // for a beat after its onset rather than snapping into partial visibility.
      expect(spring.value(0.001), lessThan(0.001));
      expect(spring.value(0.0), 0.0);
    });
  });

  test('the crossfade is convex: departing + arriving alpha stays at 1', () {
    // Not a normalisation bolted on afterwards - it falls out of a = p and a = 1 - p sharing one
    // clock. Two overlapping blurred glyphs would otherwise read darker than one solid one.
    const spring = NumericTransitionModel.alphaSpring;
    for (var i = 0; i <= 2000; i++) {
      final t = i / 2000 * 1.5;
      final arriving = spring.value(t);
      final departing = 1.0 - spring.value(t);
      expect(arriving + departing, closeTo(1.0, 1e-9));
    }
  });

  group('SpringResponse', () {
    test('is zero at and before onset', () {
      const spring = NumericTransitionModel.offsetSpring;
      expect(spring.value(0), 0.0);
      expect(spring.value(-1), 0.0);
    });

    test('converges to 1 on every damping branch', () {
      const cases = {
        'underdamped': SpringResponse(0.3, 0.55),
        'critical': SpringResponse(0.3, 1.0),
        'overdamped': SpringResponse(0.3, 2.5),
      };
      cases.forEach((name, spring) {
        expect(spring.value(5.0), closeTo(1.0, 1e-6), reason: name);
      });
    });

    test('the overdamped branch rises monotonically', () {
      const spring = SpringResponse(0.3, 2.5);
      var previous = -1.0;
      for (var i = 0; i <= 5000; i++) {
        final v = spring.value(i / 5000 * 3.0);
        expect(v, greaterThanOrEqualTo(previous - 1e-12));
        previous = v;
      }
    });

    test('settleTime is an upper bound on every branch', () {
      const cases = [
        SpringResponse(0.353, 0.55),
        SpringResponse(0.278, 1.0),
        SpringResponse(0.398, 0.91),
        SpringResponse(0.3, 2.5),
      ];
      for (final spring in cases) {
        final settle = spring.settleTime();
        // Past the reported settle time the curve must stay put.
        for (var t = settle; t < settle + 1.0; t += 0.01) {
          expect(
            (spring.value(t) - 1.0).abs(),
            lessThan(0.005),
            reason: 'response=${spring.response} zeta=${spring.dampingRatio}',
          );
        }
      }
    });

    test('scaled() stretches time without changing shape', () {
      const base = NumericTransitionModel.offsetSpring;
      final slow = base.scaled(2.0);
      for (var i = 0; i <= 500; i++) {
        final t = i / 500 * 1.0;
        expect(slow.value(t * 2), closeTo(base.value(t), 1e-12));
      }
    });
  });
}
