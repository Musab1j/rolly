import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'keyed_slots.dart';
import 'spring.dart';
import 'transition_model.dart';

/// One glyph, as it should be drawn on one frame.
@immutable
class GlyphSample {
  const GlyphSample({
    required this.key,
    required this.glyph,
    required this.x,
    required this.dy,
    required this.alpha,
    required this.scale,
    required this.sigma,
    required this.isFraction,
  });

  final String key;

  /// The text to draw. A single character in a number; possibly a whole word in arbitrary text.
  final String glyph;

  /// Horizontal centre, relative to the widget's alignment edge.
  final double x;

  /// Vertical displacement from the baseline, in logical pixels. Negative is up.
  final double dy;

  final double alpha;
  final double scale;

  /// Gaussian blur sigma in logical pixels. Zero means draw it sharp.
  final double sigma;

  /// Whether this glyph belongs to the fraction span, and so takes the second colour.
  final bool isFraction;
}

/// The four channel springs, stretched to whatever duration the caller asked for.
class _Clocks {
  _Clocks(this.scale)
    : offset = NumericTransitionModel.offsetSpring.scaled(scale),
      glyphScale = NumericTransitionModel.scaleSpring.scaled(scale),
      alpha = NumericTransitionModel.alphaSpring.scaled(scale),
      blur = NumericTransitionModel.blurSpring.scaled(scale),
      reflow = NumericTransitionModel.reflowSpring.scaled(scale);

  final double scale;
  final SpringResponse offset;
  final SpringResponse glyphScale;
  final SpringResponse alpha;
  final SpringResponse blur;
  final SpringResponse reflow;

  /// The slowest channel decides when a glyph is finished.
  late final double settleTime = [
    offset.settleTime(),
    glyphScale.settleTime(),
    alpha.settleTime(),
    blur.settleTime(),
    reflow.settleTime(),
  ].reduce(math.max);
}

/// One glyph's entire motion state.
///
/// There is deliberately no velocity here, and nothing that a frame updates. An entry is its
/// starting conditions plus the instant it began; everything else is a function of the current
/// time. That is what makes the interruption model work: a transition is never cancelled or
/// retargeted, so a glyph that gets superseded halfway through simply keeps evaluating the curves
/// it was already on while a new entry starts its own. Three or four of them can be alive in one
/// column during a fast burst, each unaware of the others.
class _Entry {
  _Entry({
    required this.glyph,
    required this.role,
    required this.onset,
    required this.axis,
    required this.entryOffset,
    this.fromAlpha = 0,
    this.fromScale = NumericTransitionModel.bornScale,
    this.fromSigma = NumericTransitionModel.maxBlurSigma,
  });

  final String glyph;
  GlyphRole role;

  /// Engine-clock seconds at which this glyph's curves start. May be in the future: that is how
  /// the cascade is expressed.
  double onset;

  /// Which way this glyph rolls: +1 when the number went down, -1 when it went up. Stored per
  /// entry rather than per column, because a burst can reverse direction while older glyphs from
  /// the previous direction are still on screen, and those must finish the way they started.
  double axis;

  /// Entry amplitude in glyph heights. Zero for a structural birth or death, which is the entire
  /// difference between appearing in place and rolling in from off-screen.
  double entryOffset;

  /// Where the glyph was on each channel when its current phase began. For a glyph that was
  /// settled these are the obvious values and the curves reduce to their plain form; for one
  /// superseded mid-flight they are whatever it had reached, so it continues smoothly instead of
  /// snapping back to full opacity to start fading again.
  double fromOffset = 0;
  double fromAlpha;
  double fromScale;
  double fromSigma;

  /// Set when the glyph's column is going away: it fades where it stands instead of riding the
  /// line's reflow. Letting corpses follow a contracting layout slides them all toward the centre
  /// and piles them into an unreadable smear on a big shrink.
  double? frozenX;

  bool get isLeaving =>
      role == GlyphRole.departing || role == GlyphRole.exitingStructural;
}

/// One horizontal position in the line, holding every glyph currently alive there.
class _Column {
  _Column(this.key, this.isFraction);

  final String key;
  bool isFraction;
  final entries = <_Entry>[];

  /// Horizontal reflow, in the same analytic style as everything else.
  double xFrom = 0;
  double xTo = 0;
  double xOnset = double.negativeInfinity;

  double xAt(double now, SpringResponse reflow) {
    if (xFrom == xTo) return xTo;
    return xFrom + (xTo - xFrom) * reflow.value(now - xOnset);
  }
}

/// Drives the numericText transition for one line of glyphs.
///
/// Owns no clock of its own: the caller supplies `now` in seconds, and every query is a pure
/// function of it. Feeding it the same timestamp twice produces the same frame.
class NumericRollEngine {
  final _columns = <String, _Column>{};
  _Clocks _clocks = _Clocks(1.0);

  double _lineHeight = 1;
  double _targetWidth = 0;
  double _previousWidth = 0;

  /// Engine-clock second by which every glyph will have finished.
  double _settleDeadline = double.negativeInfinity;

  List<KeyedSlot> _targetSlots = const [];

  /// The line currently being animated towards.
  List<KeyedSlot> get targetSlots => _targetSlots;

  /// Width to reserve for the number right now.
  ///
  /// While a transition runs this is the wider of the two lines, so the box never shrinks out from
  /// under glyphs that are still leaving. Once settled it collapses to the real width, so a number
  /// sitting in a layout takes exactly the space a [Text] would.
  double contentWidth(double now) =>
      isRunning(now) ? math.max(_targetWidth, _previousWidth) : _targetWidth;

  bool isRunning(double now) => now < _settleDeadline;

  void setDurationScale(double scale) {
    if ((scale - _clocks.scale).abs() > 1e-9) _clocks = _Clocks(scale);
  }

  /// Horizontal centre of [slot] relative to the alignment edge.
  double _xRel(KeyedSlot slot, double lineWidth, double alignFraction) =>
      slot.center - lineWidth * alignFraction;

  /// Drops every glyph and installs [slots] as settled, with no animation.
  ///
  /// Used for the first value, and whenever reduced motion is in force.
  void reset({
    required List<KeyedSlot> slots,
    required double lineWidth,
    required double lineHeight,
    required double alignFraction,
  }) {
    _columns.clear();
    _targetSlots = slots;
    _lineHeight = math.max(1, lineHeight);
    _targetWidth = lineWidth;
    _previousWidth = lineWidth;
    _settleDeadline = double.negativeInfinity;

    for (final slot in slots) {
      final column = _Column(slot.key, isFractionKey(slot.key))
        ..xFrom = _xRel(slot, lineWidth, alignFraction)
        ..xOnset = double.negativeInfinity;
      column.xTo = column.xFrom;

      // A settled glyph is just an arriving one whose onset is long past; every channel has
      // already converged, so it needs no special case anywhere downstream.
      column.entries.add(
        _Entry(
          glyph: slot.glyph,
          role: GlyphRole.arriving,
          onset: double.negativeInfinity,
          axis: -1,
          entryOffset: 0,
          fromAlpha: 1,
          fromScale: 1,
          fromSigma: 0,
        ),
      );

      _columns[slot.key] = column;
    }
  }

  /// Begins a transition to [slots].
  ///
  /// [countsDown] is global to the transition, decided by whether the number grew or shrank —
  /// never per digit. This is not a simplification: in `0 -> -1` the units digit goes 0 -> 1, a
  /// numeric *increase*, and it still rolls in the decrement direction along with everything else.
  void setTarget({
    required List<KeyedSlot> slots,
    required bool countsDown,
    required double now,
    required double lineWidth,
    required double lineHeight,
    required double alignFraction,
  }) {
    _lineHeight = math.max(1, lineHeight);
    _previousWidth = _targetWidth;
    _targetWidth = lineWidth;

    final axis = countsDown ? 1.0 : -1.0;
    final incoming = {for (final slot in slots) slot.key: slot};
    final previous = {for (final slot in _targetSlots) slot.key: slot};

    /// Whether this column currently shows a glyph. A column whose key survives but whose glyphs
    /// have all been retired - possible when a value shrinks and grows again inside one
    /// transition - has to be treated as a birth, not as a roll from nothing.
    bool hasLiveGlyph(String key) =>
        _columns[key]?.entries.lastWhereOrNull((e) => !e.isLeaving) != null;

    // A column is born or dies when its key appears or disappears. Keying this on structure
    // rather than on rendered width is deliberate: fonts and locales change a line's width
    // without changing its structure, and a width-based test would fire spuriously on those.
    final born = incoming.keys.where((k) => !hasLiveGlyph(k)).toSet();
    final died = _columns.keys
        .where((k) => !incoming.containsKey(k) && hasLiveGlyph(k))
        .toSet();

    // Which columns have something to animate. Separators are excluded from the cascade: only
    // digits and the affixes that move with them take part in the wave.
    final changing = <KeyedSlot>[];
    for (final slot in slots) {
      if (slot.kind != TokenKind.digit) continue;
      final live = _columns[slot.key]?.entries.lastWhereOrNull(
        (e) => !e.isLeaving,
      );
      if (live == null || live.glyph != slot.glyph) changing.add(slot);
    }

    // A structural change does not cascade. Everything commits together, because the horizontal
    // re-layout is not part of the wave and staggering against it reads as a stumble.
    final structural =
        born.any((k) => incoming[k]?.kind == TokenKind.digit) ||
        died.any((k) => previous[k]?.kind == TokenKind.digit);

    final order = [...changing]..sort((a, b) => a.center.compareTo(b.center));
    final gap = (!structural && order.length > 1)
        ? NumericTransitionModel.cascadeTotalSeconds / (order.length - 1)
        : 0.0;
    final delays = <String, double>{
      for (var i = 0; i < order.length; i++) order[i].key: gap * i,
    };

    var latestOnset = now;

    // --- columns that survive, whether or not their glyph changes -------------------------------
    for (final slot in slots) {
      final isBorn = born.contains(slot.key);
      final column = _columns.putIfAbsent(
        slot.key,
        () => _Column(slot.key, isFractionKey(slot.key)),
      )..isFraction = isFractionKey(slot.key);

      final targetX = _xRel(slot, lineWidth, alignFraction);
      // A born column appears already at its final x; only a column that was on screen has a
      // position to slide from.
      if (!isBorn && column.entries.isNotEmpty) {
        // Start the slide from wherever the column is right now, so a retarget mid-reflow
        // continues from the visible position rather than jumping back.
        column.xFrom = column.xAt(now, _clocks.reflow);
        column.xTo = targetX;
        column.xOnset = now;
      } else {
        column.xFrom = targetX;
        column.xTo = targetX;
        column.xOnset = double.negativeInfinity;
      }

      final live = column.entries.lastWhereOrNull((e) => !e.isLeaving);
      if (!isBorn && live != null && live.glyph == slot.glyph) {
        continue; // Unchanged glyph: it only reflows.
      }

      final onset = now + (delays[slot.key] ?? 0.0);
      latestOnset = math.max(latestOnset, onset);

      // Supersede whatever was here. Note this does not stop it - it hands it the exit curves
      // starting from exactly where it had got to.
      for (final entry in column.entries) {
        if (!entry.isLeaving) _supersede(entry, now, axis, GlyphRole.departing);
      }

      column.entries.add(
        _Entry(
          glyph: slot.glyph,
          role: isBorn ? GlyphRole.enteringStructural : GlyphRole.arriving,
          onset: onset,
          axis: axis,
          // A structural birth appears in place at its final position, small and blurred, and
          // grows. It has no vertical entry at all - that is what distinguishes it from a roll.
          entryOffset: isBorn ? 0.0 : NumericTransitionModel.entryOffset,
        ),
      );
    }

    // --- columns that are going away ------------------------------------------------------------
    for (final key in died) {
      final column = _columns[key]!;
      final frozenX = column.xAt(now, _clocks.reflow);
      for (final entry in column.entries) {
        if (entry.isLeaving) continue;
        _supersede(entry, now, axis, GlyphRole.exitingStructural);
        entry.frozenX = frozenX;
      }
    }

    _targetSlots = slots;
    _settleDeadline = latestOnset + _clocks.settleTime;
  }

  /// Hands [entry] the exit curves, starting from the exact state it currently shows.
  void _supersede(_Entry entry, double now, double axis, GlyphRole role) {
    final state = _evaluate(entry, now);
    entry
      ..role = role
      ..onset = now
      ..axis = axis
      ..fromOffset = state.offset
      ..fromAlpha = state.alpha
      ..fromScale = state.scale
      ..fromSigma = state.sigma
      // A structural death collapses in place; an ordinary departing glyph rolls out of the way.
      ..entryOffset = role == GlyphRole.exitingStructural
          ? 0.0
          : NumericTransitionModel.entryOffset;
  }

  /// The four channels for one glyph at one instant, in normalised units.
  ({double offset, double alpha, double scale, double sigma}) _evaluate(
    _Entry entry,
    double now,
  ) {
    final t = now - entry.onset;

    if (entry.isLeaving) {
      // Every channel eases from where the glyph was to where a dead glyph ends up. When the
      // glyph was settled these reduce exactly to the plain departing curves
      // (dy = -axis*0.59375*p, a = 1-p, s = 1-0.6016*p, sigma = 0.125*p).
      final targetOffset = -entry.axis * entry.entryOffset;
      return (
        offset: _lerp(entry.fromOffset, targetOffset, _clocks.offset.value(t)),
        alpha: _lerp(entry.fromAlpha, 0, _clocks.alpha.value(t)),
        scale: _lerp(
          entry.fromScale,
          NumericTransitionModel.bornScale,
          _clocks.glyphScale.value(t),
        ),
        sigma: _lerp(
          entry.fromSigma,
          NumericTransitionModel.maxBlurSigma,
          _clocks.blur.value(t),
        ),
      );
    }

    // Arriving. The offset spring overshoots, so this genuinely crosses its resting line and
    // eases back - do not clamp it.
    final startOffset = entry.axis * entry.entryOffset;
    return (
      offset: _lerp(startOffset, 0, _clocks.offset.value(t)),
      alpha: _lerp(entry.fromAlpha, 1, _clocks.alpha.value(t)),
      scale: _lerp(entry.fromScale, 1, _clocks.glyphScale.value(t)),
      sigma: _lerp(entry.fromSigma, 0, _clocks.blur.value(t)),
    );
  }

  static double _lerp(double from, double to, double p) =>
      from + (to - from) * p;

  /// Every glyph to draw this frame.
  ///
  /// Also culls glyphs that have faded out and retires emptied columns, so calling this once per
  /// frame is what keeps the stack from growing without bound under sustained input.
  List<GlyphSample> sample(double now) {
    final samples = <GlyphSample>[];
    final emptied = <String>[];

    for (final column in _columns.values) {
      column.entries.removeWhere(
        (entry) =>
            entry.isLeaving &&
            now > entry.onset &&
            _evaluate(entry, now).alpha < NumericTransitionModel.cullAlpha,
      );

      if (column.entries.isEmpty) {
        emptied.add(column.key);
        continue;
      }

      final states = [
        for (final entry in column.entries) _evaluate(entry, now),
      ];

      // The crossfade is convex: the alphas in a column sum to 1. It falls out of the curves on
      // an isolated change, but a burst can stack three or four glyphs whose alphas would
      // otherwise add up to more than one and read as a dark smudge. Normalising only when the
      // sum exceeds 1 preserves the ordinary case exactly.
      final total = states.fold<double>(
        0,
        (sum, s) => sum + math.max(0, s.alpha),
      );
      final norm = total > 1 ? 1 / total : 1.0;

      final columnX = column.xAt(now, _clocks.reflow);

      for (var i = 0; i < column.entries.length; i++) {
        final entry = column.entries[i];
        final state = states[i];
        final alpha = math.max(0.0, state.alpha) * norm;
        if (alpha <= NumericTransitionModel.renderAlphaEpsilon) continue;

        final sigma = state.sigma * _lineHeight;

        samples.add(
          GlyphSample(
            key: column.key,
            glyph: entry.glyph,
            x: entry.frozenX ?? columnX,
            dy: state.offset * _lineHeight,
            alpha: alpha.clamp(0.0, 1.0),
            scale: state.scale.clamp(0.0, 4.0),
            sigma: sigma < NumericTransitionModel.minRenderSigma ? 0 : sigma,
            isFraction: column.isFraction,
          ),
        );
      }
    }

    for (final key in emptied) {
      _columns.remove(key);
    }

    return samples;
  }
}

extension<T> on List<T> {
  T? lastWhereOrNull(bool Function(T) test) {
    for (var i = length - 1; i >= 0; i--) {
      if (test(this[i])) return this[i];
    }
    return null;
  }
}
