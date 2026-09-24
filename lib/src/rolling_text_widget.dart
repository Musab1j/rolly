import 'package:flutter/widgets.dart';

import 'rolling_line.dart';
import 'text_slots.dart';
import 'transition_model.dart';

/// Arbitrary text, animated with the numericText transition.
///
/// The same four channels, the same cascade, the same births and deaths as `NumericText` — only
/// what counts as "the same glyph" differs. A number carries its own structure, so its digits can
/// be identified from one line alone; text has none, so each new string is diffed against the one
/// on screen. Characters the diff matches keep their identity and merely slide into place;
/// a stretch that was replaced rolls in the column it replaced; the rest is born or dies.
///
/// ```dart
/// RollingText(
///   status,                       // 'Connecting…' -> 'Connected'
///   style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w600),
/// )
/// ```
///
/// One line only, as `NumericText` is: there is no wrapping, and a `\n` will not break the string.
///
/// Each unit is laid out on its own, which is what makes it movable and is also the one thing the
/// split has to respect: a cursive script cannot be cut between letters, because a letter typeset
/// alone takes its isolated form. [TextSplit.character] therefore keeps a run of joining script —
/// Arabic and the rest — whole, and splits everything around it as usual. Nothing is required of
/// the caller; [TextSplit.word] is a choice about prose, not a workaround.
class RollingText extends StatefulWidget {
  /// Creates a line of text that animates between the strings it is given.
  const RollingText(
    this.text, {
    super.key,
    this.split = TextSplit.character,
    this.style,
    this.direction = NumericDirection.automatic,
    this.duration = const Duration(milliseconds: 320),
    this.reduceMotion = NumericReduceMotion.system,
    this.textAlign = TextAlign.center,
    this.textDirection,
    this.edgeFade = true,
  });

  /// The line on screen. Changing it starts a transition to the new string.
  final String text;

  /// The granularity the line animates at.
  final TextSplit split;

  /// Merged over [DefaultTextStyle], as [Text] does.
  final TextStyle? style;

  /// Which way glyphs roll.
  ///
  /// [NumericDirection.automatic] compares the two strings, so a change and its reverse roll
  /// opposite ways — which is what makes a value that toggles read as a toggle rather than as a
  /// treadmill. There is no meaning in the ordering itself; force a direction when the text has
  /// one, as a countdown label does.
  final NumericDirection direction;

  /// How long the transition takes. 320ms reproduces the measured timing; other values stretch
  /// every channel by the same factor, so the character of the motion survives.
  final Duration duration;

  /// Whether the platform's reduced-motion setting suppresses the transition.
  final NumericReduceMotion reduceMotion;

  /// Which edge the line is pinned to while its width changes. Only start, center and end are
  /// meaningful here.
  final TextAlign textAlign;

  /// The base direction the line is laid out in. Defaults to the ambient [Directionality].
  final TextDirection? textDirection;

  /// Softens the far top and bottom of the rolling area.
  final bool edgeFade;

  @override
  State<RollingText> createState() => _RollingTextState();
}

class _RollingTextState extends State<RollingText> {
  bool _countsDown = false;

  @override
  void didUpdateWidget(RollingText old) {
    super.didUpdateWidget(old);

    if (widget.text != old.text) {
      _countsDown = switch (widget.direction) {
        NumericDirection.up => false,
        NumericDirection.down => true,
        NumericDirection.automatic => widget.text.compareTo(old.text) < 0,
      };
    }
  }

  @override
  Widget build(BuildContext context) {
    return RollingLine(
      text: widget.text,
      keying: TextKeying(widget.split),
      countsDown: _countsDown,
      style: widget.style,
      duration: widget.duration,
      reduceMotion: widget.reduceMotion,
      textAlign: widget.textAlign,
      textDirection: widget.textDirection,
      edgeFade: widget.edgeFade,
    );
  }
}
