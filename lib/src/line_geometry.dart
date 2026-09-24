import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// Where every glyph of one line sits, measured from the line typeset as a whole.
///
/// The "as a whole" is the point. It would be simpler to lay out each character on its own and
/// add up the advances, but that discards kerning and any shaping the font applies across
/// characters, so the animated glyphs would sit at subtly different positions than the same
/// string rendered by a plain [Text]. Laying out the real line once and then asking it where each
/// character landed keeps the settled state pixel-identical to ordinary text — which is what lets
/// a line sit in a layout without the transition being visible as a seam.
class LineGeometry {
  LineGeometry._(this._painter, this.text, this.lineHeight, this.baseline);

  /// Lays out [text] in [style] and captures its geometry.
  ///
  /// [textDirection] is the paragraph's base direction, and it is not cosmetic: it decides where a
  /// neutral character — a space, a bracket, a currency symbol — lands in a line that mixes
  /// scripts. Measuring an Arabic line as though it were left-to-right puts those in the wrong
  /// place, and every slot position downstream inherits the error.
  factory LineGeometry.measure(
    String text,
    TextStyle style,
    TextDirection textDirection,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: textDirection,
      maxLines: 1,
    )..layout();

    // Font ascent + descent, not TextPainter.height, which can carry extra leading. The
    // transition's offsets and blur radii are expressed in glyph heights, so this figure scales
    // the whole animation; taking it from the font metrics keeps it stable no matter which
    // characters the current value happens to contain (a line of "111" is not shorter than "888").
    final metrics = painter.computeLineMetrics();
    final lineHeight = metrics.isEmpty
        ? painter.height
        : metrics.first.ascent + metrics.first.descent;
    final baseline = metrics.isEmpty
        ? painter.computeDistanceToActualBaseline(TextBaseline.alphabetic)
        : metrics.first.ascent;

    return LineGeometry._(painter, text, lineHeight, baseline);
  }

  final TextPainter _painter;
  final String text;

  /// Ascent + descent of the font at this size, in logical pixels.
  final double lineHeight;

  /// Distance from the top of the laid-out line down to the alphabetic baseline.
  final double baseline;

  double get width => _painter.width;

  /// Horizontal bounds of the characters in `[utf16Start, utf16End)`, measured from the line's
  /// left edge.
  (double left, double right) boundsFor(int utf16Start, int utf16End) {
    final boxes = _painter.getBoxesForSelection(
      TextSelection(baseOffset: utf16Start, extentOffset: utf16End),
    );

    if (boxes.isEmpty) {
      // Zero-width content - a directional mark, or a character the font renders as nothing.
      // Give it the caret position so it still sorts into the right place among its neighbours.
      final caret = _painter.getOffsetForCaret(
        TextPosition(offset: utf16Start),
        ui.Rect.zero,
      );
      return (caret.dx, caret.dx);
    }

    var left = boxes.first.left;
    var right = boxes.first.right;
    for (final box in boxes.skip(1)) {
      if (box.left < left) left = box.left;
      if (box.right > right) right = box.right;
    }
    return (left, right);
  }

  void dispose() => _painter.dispose();
}

/// Caches [LineGeometry] by the text and style it was measured with.
///
/// A press-and-hold stepper walks back and forth over a small set of values, and a transition
/// needs the geometry of both the line it is leaving and the one it is arriving at on every
/// frame. Re-laying-out text at 120 Hz is the one thing in this widget expensive enough to show
/// up in a frame budget, so it is done once per distinct string and then never again.
class LineGeometryCache {
  LineGeometryCache({this.capacity = 48});

  final int capacity;
  final _entries = <(String, TextStyle, TextDirection), LineGeometry>{};

  LineGeometry measure(
    String text,
    TextStyle style,
    TextDirection textDirection,
  ) {
    final key = (text, style, textDirection);

    final hit = _entries.remove(key);
    if (hit != null) {
      // Reinsert to mark as most recently used.
      _entries[key] = hit;
      return hit;
    }

    final geometry = LineGeometry.measure(text, style, textDirection);
    _entries[key] = geometry;

    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first)?.dispose();
    }

    return geometry;
  }

  void clear() {
    for (final geometry in _entries.values) {
      geometry.dispose();
    }
    _entries.clear();
  }
}
