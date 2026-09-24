import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import 'roll_engine.dart';
import 'transition_model.dart';

/// One animated unit — a character, or a whole word — laid out once and reused for every frame it
/// appears in.
class CachedGlyph {
  CachedGlyph(this.painter, this.ascent, this.descent);

  final TextPainter painter;
  final double ascent;
  final double descent;

  double get width => painter.width;

  /// The glyph's vertical middle, measured from the baseline. Negative, since more of a digit
  /// sits above the baseline than below it. Scaling about this point rather than about the
  /// baseline is what keeps a shrinking glyph looking like it is receding rather than sinking.
  double get opticalCenter => (descent - ascent) / 2;
}

/// Lays out and caches the individual units the line is animated in.
///
/// The transition never re-lays-out text: a value change re-keys which glyph goes where, but the
/// glyphs themselves are drawn from here. Ten digits, a few separators and two colours is the
/// whole working set for a number, so after the first second of use this never misses.
///
/// Laying a unit out on its own is what makes the animation possible at all, and it is also the
/// constraint the splitting has to respect: a unit is shaped without its neighbours, so whatever
/// is handed here must be something that stands alone. That is why `text_slots.dart` will not cut
/// a run of joining script into letters — the pieces would come back in their isolated forms.
class GlyphCache {
  final _glyphs = <(String, Color), CachedGlyph>{};
  TextStyle? _style;
  TextDirection _textDirection = TextDirection.ltr;

  /// Discards everything if the style changed, since every cached layout belongs to the old one.
  void retune(TextStyle style, TextDirection textDirection) {
    if (_style == style && _textDirection == textDirection) return;
    _style = style;
    _textDirection = textDirection;
    for (final glyph in _glyphs.values) {
      glyph.painter.dispose();
    }
    _glyphs.clear();
  }

  CachedGlyph of(String glyph, Color color) =>
      _glyphs.putIfAbsent((glyph, color), () {
        final painter = TextPainter(
          text: TextSpan(
            text: glyph,
            style: _style!.copyWith(color: color),
          ),
          textDirection: _textDirection,
          maxLines: 1,
        )..layout();

        final metrics = painter.computeLineMetrics();
        final ascent = metrics.isEmpty
            ? painter.computeDistanceToActualBaseline(TextBaseline.alphabetic)
            : metrics.first.ascent;
        final descent = metrics.isEmpty ? 0.0 : metrics.first.descent;

        return CachedGlyph(painter, ascent, descent);
      });

  void dispose() {
    for (final glyph in _glyphs.values) {
      glyph.painter.dispose();
    }
    _glyphs.clear();
  }
}

/// Draws one frame of the transition.
///
/// Repaints are driven by [samples], a notifier the ticker updates, so a frame of animation costs
/// a paint and nothing else - no widget rebuild, no layout, no element tree walk.
class NumericTextPainter extends CustomPainter {
  NumericTextPainter({
    required this.samples,
    required this.cache,
    required this.color,
    required this.fractionColor,
    required this.lineHeight,
    required this.baseline,
    required this.alignFraction,
    required this.edgeFade,
  }) : super(repaint: samples);

  final ValueListenable<List<GlyphSample>> samples;
  final GlyphCache cache;
  final Color color;
  final Color? fractionColor;
  final double lineHeight;

  /// Distance from the top of the box down to the alphabetic baseline.
  final double baseline;

  /// 0 for left-aligned, 0.5 for centred, 1 for right-aligned. Glyph positions arrive relative to
  /// this edge, so the line stays pinned to it while its width changes.
  final double alignFraction;

  /// Whether to dissolve glyphs that stray far above or below the line.
  final bool edgeFade;

  @override
  void paint(Canvas canvas, Size size) {
    final glyphs = samples.value;
    if (glyphs.isEmpty) return;

    final anchorX = size.width * alignFraction;

    // Glyphs roll in and out of the line, so they legitimately paint outside the box the widget
    // occupies - exactly as SwiftUI's transition does. The fade below only softens the far edge
    // of that excursion; it is not a clip.
    final overflow = lineHeight * 1.1;
    final bounds = Rect.fromLTRB(
      -lineHeight,
      -overflow,
      size.width + lineHeight,
      size.height + overflow,
    );

    if (edgeFade) canvas.saveLayer(bounds, Paint());

    for (final sample in glyphs) {
      _paintGlyph(canvas, sample, anchorX);
    }

    if (edgeFade) {
      _applyEdgeFade(canvas, bounds);
      canvas.restore();
    }
  }

  void _paintGlyph(Canvas canvas, GlyphSample sample, double anchorX) {
    final tint = sample.isFraction ? (fractionColor ?? color) : color;
    final glyph = cache.of(sample.glyph, tint);

    canvas.save();
    canvas.translate(anchorX + sample.x, baseline + sample.dy);

    // Opacity and blur both belong to the composite, not to the text, so one layer carries both.
    // Doing it this way rather than through a MaskFilter on the text style keeps the glyph
    // layouts immutable and shareable, and keeps blur on the path Impeller handles best.
    final needsLayer =
        sample.sigma > 0 ||
        sample.alpha < 1 - NumericTransitionModel.renderAlphaEpsilon;

    if (needsLayer) {
      // The layer clips before the filter is composited, so this has to cover the blur's whole
      // reach, not just the glyph. A Gaussian is still meaningfully non-zero at 3 sigma - budget
      // that exactly and the blurred glyph gets sliced off square at the edges, which reads as a
      // hard-edged box flickering around the digit mid-roll.
      final pad = sample.sigma * 4 + 4;
      final layerBounds = Rect.fromLTRB(
        -glyph.width / 2 - pad,
        -glyph.ascent - pad,
        glyph.width / 2 + pad,
        glyph.descent + pad,
      );

      final paint = Paint()..color = Color.fromRGBO(0, 0, 0, sample.alpha);
      if (sample.sigma > 0) {
        paint.imageFilter = ui.ImageFilter.blur(
          sigmaX: sample.sigma,
          sigmaY: sample.sigma,
          // Decal, so a blurred glyph fades into nothing at its edges instead of smearing the
          // surrounding pixels outward.
          tileMode: TileMode.decal,
        );
      }
      canvas.saveLayer(layerBounds, paint);
    }

    // Scale about the glyph's optical centre.
    final centre = glyph.opticalCenter;
    canvas
      ..translate(0, centre)
      ..scale(sample.scale)
      ..translate(0, -centre);

    glyph.painter.paint(canvas, Offset(-glyph.width / 2, -glyph.ascent));

    if (needsLayer) canvas.restore();
    canvas.restore();
  }

  /// Dissolves the top and bottom of the painted region.
  ///
  /// A glyph is nearly transparent by the time it gets this far out, so this mostly guards one
  /// case: a value changing again while the previous glyphs are still travelling, which sends
  /// them further than a single transition ever would.
  void _applyEdgeFade(Canvas canvas, Rect bounds) {
    final fade = lineHeight * 0.55;
    final span = bounds.height;
    if (span <= 0) return;

    final shader = ui.Gradient.linear(
      Offset(0, bounds.top),
      Offset(0, bounds.bottom),
      const [
        Color(0x00000000),
        Color(0xFF000000),
        Color(0xFF000000),
        Color(0x00000000),
      ],
      [
        0.0,
        (fade / span).clamp(0.0, 0.5),
        1 - (fade / span).clamp(0.0, 0.5),
        1.0,
      ],
    );

    canvas.drawRect(
      bounds,
      Paint()
        ..shader = shader
        ..blendMode = BlendMode.dstIn,
    );
  }

  @override
  bool shouldRepaint(NumericTextPainter old) =>
      old.color != color ||
      old.fractionColor != fractionColor ||
      old.lineHeight != lineHeight ||
      old.baseline != baseline ||
      old.alignFraction != alignFraction ||
      old.edgeFade != edgeFade ||
      old.samples != samples;
}
