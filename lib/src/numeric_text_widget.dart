import 'package:flutter/widgets.dart';

import 'numeric_format.dart';
import 'rolling_line.dart';
import 'slot_keying.dart';
import 'transition_model.dart';

/// A number that animates between values the way SwiftUI's `.contentTransition(.numericText())`
/// does: digits roll, the line reflows around them, and glyphs that appear or disappear are born
/// and die in place.
///
/// Behaves like a [Text] in layout — it takes the width of the number it is showing, widening
/// only for as long as a transition needs the extra room. Glyphs deliberately paint slightly
/// outside that box while rolling, as they do on iOS, so give it a little vertical room in a
/// tight layout.
///
/// ```dart
/// NumericText(
///   value: total,
///   format: const NumericTextFormat.currency(symbol: r'$'),
///   style: const TextStyle(fontSize: 64, fontWeight: FontWeight.w700),
/// )
/// ```
///
/// For anything that is not a number, see `RollingText`, which runs the same transition over a
/// string.
class NumericText extends StatefulWidget {
  /// Creates a number that animates between the values it is given.
  const NumericText({
    required this.value,
    super.key,
    this.format,
    this.style,
    this.fractionColor,
    this.direction = NumericDirection.automatic,
    this.duration = const Duration(milliseconds: 320),
    this.reduceMotion = NumericReduceMotion.system,
    this.textAlign = TextAlign.center,
    this.textDirection,
    this.edgeFade = true,
  });

  /// The number on screen. Changing it starts a transition to the new value.
  final num value;

  /// How [value] is turned into text. Defaults to a grouped decimal: `1,234.5`.
  final NumericTextFormat? format;

  /// Merged over [DefaultTextStyle], as [Text] does.
  final TextStyle? style;

  /// A second colour for the fraction span — the decimal mark, the digits after it, and any
  /// trailing symbol. Useful for de-emphasising cents. The span still rolls with the rest of the
  /// number rather than transitioning on its own.
  final Color? fractionColor;

  /// Which way glyphs roll. [NumericDirection.automatic] takes it from whether the value grew or
  /// shrank, as the SwiftUI transition does.
  final NumericDirection direction;

  /// How long the transition takes. 320ms reproduces the measured timing; other values stretch
  /// every channel by the same factor, so the character of the motion survives.
  final Duration duration;

  /// Whether the platform's reduced-motion setting suppresses the transition.
  final NumericReduceMotion reduceMotion;

  /// Which edge the number is pinned to while its width changes. Only start, center and end are
  /// meaningful here.
  final TextAlign textAlign;

  /// The base direction the line is laid out in. Defaults to the ambient [Directionality], and
  /// decides where a neutral glyph — a currency symbol, a bracket — sits in a line that mixes
  /// scripts.
  final TextDirection? textDirection;

  /// Softens the far top and bottom of the rolling area. Turn off if the number sits on a busy
  /// background where the extra layer is not worth it.
  final bool edgeFade;

  @override
  State<NumericText> createState() => _NumericTextState();
}

class _NumericTextState extends State<NumericText> {
  static const _fallbackFormat = NumericTextFormat.decimal();

  /// Decided here rather than downstream because it is a fact about the *numbers*, and by the time
  /// the line reaches [RollingLine] it is a pair of strings: `9` to `10` grew, and `9` to `10`
  /// read as text did not.
  bool _countsDown = false;

  NumericTextFormat get _format => widget.format ?? _fallbackFormat;

  @override
  void didUpdateWidget(NumericText old) {
    super.didUpdateWidget(old);

    // Left alone when the value did not move, so that a rebuild cannot flip the direction of a
    // transition that is already under way.
    if (widget.value != old.value) {
      _countsDown = switch (widget.direction) {
        NumericDirection.up => false,
        NumericDirection.down => true,
        NumericDirection.automatic => widget.value < old.value,
      };
    }
  }

  @override
  Widget build(BuildContext context) {
    final format = _format;

    return RollingLine(
      text: format.format(widget.value),
      keying: NumericKeying(format),
      countsDown: _countsDown,
      style: widget.style,
      fractionColor: widget.fractionColor,
      duration: widget.duration,
      reduceMotion: widget.reduceMotion,
      textAlign: widget.textAlign,
      textDirection: widget.textDirection,
      edgeFade: widget.edgeFade,
    );
  }
}
