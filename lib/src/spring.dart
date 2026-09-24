import 'dart:math' as math;

/// The step response of a second-order system, evaluated in closed form.
///
/// Every channel of the transition — vertical offset, scale, alpha, blur — is one of these,
/// differing only in [response] and [dampingRatio]. See `doc/animation_model.md` for the
/// parameters each channel runs at.
///
/// This is deliberately analytic rather than an integrated simulation. A spring stepped by `dt`
/// each frame gives slightly different results at 60 Hz, 120 Hz, and across a dropped frame;
/// `value(t)` does not. It also means a glyph needs no motion state at all — only the instant it
/// started — which is what makes the interruption model (a stack of independent transitions, none
/// of them ever cancelled or retargeted) fall out almost for free.
class SpringResponse {
  /// [response] is the period of the undamped oscillation, in seconds — the same parameterisation
  /// SwiftUI's `Animation.spring(response:dampingFraction:)` uses, so fitted values transfer
  /// directly. [dampingRatio] is ζ: below 1 overshoots, 1 is critically damped, above 1 crawls in
  /// without ever crossing.
  const SpringResponse(this.response, this.dampingRatio)
    : assert(response > 0),
      assert(dampingRatio > 0);

  final double response;
  final double dampingRatio;

  /// Undamped natural frequency, rad/s.
  double get _omega0 => 2 * math.pi / response;

  /// The response rescaled by [scale]: a scale of 2 makes the same curve take twice as long.
  ///
  /// Used for the `duration` property, which stretches all four channels together so their
  /// relative timing — the whole character of the transition — survives.
  SpringResponse scaled(double scale) =>
      SpringResponse(response * scale, dampingRatio);

  /// The step response at [t] seconds after onset: 0 at t=0, converging to 1.
  ///
  /// May exceed 1 while settling when [dampingRatio] < 1. That overshoot is not an artifact to be
  /// clamped away — for the offset channel it *is* the measured behaviour, the ~12% bounce past
  /// rest that makes an arriving digit look like it landed rather than slid to a halt.
  double value(double t) {
    if (t <= 0) return 0;

    // A glyph that has been settled since before the widget existed carries an onset of negative
    // infinity, which lands here as t = +infinity. Every branch below would then evaluate
    // `exp(-inf) * (1 + inf)` - a zero times an infinity, which is NaN, and a NaN alpha silently
    // defeats both the crossfade normalisation and the culling downstream. Such a glyph is simply
    // finished.
    if (!t.isFinite) return t.isNaN ? 0 : 1;

    final w0 = _omega0;
    final z = dampingRatio;

    if (z < 1 - 1e-6) {
      // Underdamped: decaying oscillation about the target.
      final wd = w0 * math.sqrt(1 - z * z);
      final decay = math.exp(-z * w0 * t);
      return 1 - decay * (math.cos(wd * t) + (z * w0 / wd) * math.sin(wd * t));
    }

    if (z <= 1 + 1e-6) {
      // Critically damped: the fastest approach that never crosses the target.
      return 1 - math.exp(-w0 * t) * (1 + w0 * t);
    }

    // Overdamped: two real roots, the slower one dominating the tail.
    final rt = math.sqrt(z * z - 1);
    final r1 = -w0 * (z - rt);
    final r2 = -w0 * (z + rt);
    // Coefficients chosen so value(0) == 0 and value'(0) == 0.
    final c1 = r2 / (r2 - r1);
    final c2 = -r1 / (r2 - r1);
    return 1 - (c1 * math.exp(r1 * t) + c2 * math.exp(r2 * t));
  }

  /// Seconds after onset beyond which the response stays within [epsilon] of 1 for good.
  ///
  /// Used to decide when a glyph has finished and the ticker can stop. A bound that errs long
  /// costs a few idle frames; one that errs short would freeze a glyph mid-flight, so each branch
  /// is bounded by its own slowest term rather than by one shared approximation.
  double settleTime({double epsilon = 0.001}) {
    final w0 = _omega0;
    final z = dampingRatio;

    if (z < 1 - 1e-6) {
      // The underdamped residual is bounded by its envelope, `e^(−ζω₀t)/√(1−ζ²)`.
      final amplitude = 1 / math.sqrt(1 - z * z);
      return math.log(amplitude / epsilon) / (z * w0);
    }

    if (z <= 1 + 1e-6) {
      // The critical residual is `e^(−x)(1+x)` in `x = ω₀t`. Since `(1+x) < e^(x/2)` for x ≥ 3,
      // that is below `e^(−x/2)`, so `x = 2·ln(1/ε)` is a safe inversion.
      return math.max(3.0, 2 * math.log(1 / epsilon)) / w0;
    }

    // Overdamped: two real poles, and the tail belongs entirely to the slower one — which is far
    // slower than `ζω₀`, so bounding by that would cut the animation off early.
    final rt = math.sqrt(z * z - 1);
    final slowestRate = w0 * (z - rt);
    final amplitude = (z + rt) / (2 * rt);
    return math.log(amplitude / epsilon) / slowestRate;
  }
}
