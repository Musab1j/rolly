import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'keyed_slots.dart';
import 'line_geometry.dart';
import 'numeric_text_painter.dart';
import 'roll_engine.dart';
import 'slot_keying.dart';
import 'transition_model.dart';

/// One line of glyphs, animated between strings by [NumericRollEngine].
///
/// This is the whole widget: the engine, the clock, the caches and the painter. What it is
/// *showing* it does not know — it is handed a string and a [SlotKeying], and everything that
/// separates animating a number from animating a sentence lives in the keying. `NumericText` and
/// `RollingText` are both thin wrappers that decide those two arguments.
class RollingLine extends StatefulWidget {
  const RollingLine({
    required this.text,
    required this.keying,
    required this.countsDown,
    super.key,
    this.style,
    this.fractionColor,
    this.duration = const Duration(milliseconds: 320),
    this.reduceMotion = NumericReduceMotion.system,
    this.textAlign = TextAlign.center,
    this.textDirection,
    this.edgeFade = true,
  });

  /// The string to show. Changing it starts a transition.
  final String text;

  /// How the glyphs of [text] are identified across a change. Compared with `==`, so an equal
  /// keying built on every rebuild costs nothing and preserves whatever history the live keyer
  /// holds.
  final SlotKeying keying;

  /// Which way the glyphs roll on the next change. Decided by the caller, because what counts as
  /// "down" depends on what the string means: a smaller number for `NumericText`, an earlier
  /// string for `RollingText`.
  final bool countsDown;

  /// Merged over [DefaultTextStyle], as [Text] does.
  final TextStyle? style;

  /// A second colour for the fraction span of a formatted number. Meaningless for arbitrary text,
  /// whose keys never fall in that span.
  final Color? fractionColor;

  final Duration duration;
  final NumericReduceMotion reduceMotion;

  /// Which edge the line is pinned to while its width changes.
  final TextAlign textAlign;

  /// Defaults to the ambient [Directionality].
  final TextDirection? textDirection;

  /// Softens the far top and bottom of the rolling area.
  final bool edgeFade;

  @override
  State<RollingLine> createState() => _RollingLineState();
}

class _RollingLineState extends State<RollingLine>
    with SingleTickerProviderStateMixin {
  final _engine = NumericRollEngine();
  final _geometryCache = LineGeometryCache();
  final _glyphCache = GlyphCache();
  final _samples = ValueNotifier<List<GlyphSample>>(const []);

  late Ticker _ticker;
  late SlotKeyer _keyer = widget.keying.createKeyer();

  /// The engine's clock, in seconds. Every onset the engine is given is stamped with this, and
  /// every sample is taken at it, so it has to advance monotonically for the widget's whole life.
  ///
  /// It cannot simply be the ticker's elapsed time. [Ticker.stop] clears the ticker's start
  /// stamp, so the next [Ticker.start] begins counting from zero again - while onsets handed to
  /// the engine keep climbing. The engine would then be asked for a frame at a time *before* the
  /// onsets it was just given, and would correctly answer that nothing has happened yet: the
  /// number sits frozen until the clock catches up, and the freeze grows by one transition's
  /// length every time the ticker stops.
  double _now = 0;

  /// The value of [_now] when the ticker was last started, so elapsed time resumes from there
  /// rather than restarting.
  double _tickerEpoch = 0;

  TextStyle _style = const TextStyle();
  TextDirection _textDirection = TextDirection.ltr;
  bool _initialized = false;
  String _text = '';
  double _lineWidth = 0;
  double _lineHeight = 0;
  double _baseline = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _engine.setDurationScale(
      widget.duration.inMilliseconds /
          NumericTransitionModel.referenceDurationMs,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // This fires for any inherited change, and this widget depends on several: DefaultTextStyle,
    // Directionality, MediaQuery (for reduced motion) and Localizations (for a default format).
    // Snapping unconditionally would abandon a transition mid-flight every time an unrelated one
    // of those moved - a rotation, a keyboard, a theme tween - which reads as the line glitching.
    // Only the first call has to install a value; after that, only a real restyle matters.
    _resolveStyle(snap: !_initialized);
    _initialized = true;
  }

  @override
  void didUpdateWidget(RollingLine old) {
    super.didUpdateWidget(old);

    // The keyer carries the history the next diff is taken against, so it survives every rebuild
    // that describes the same keying and is rebuilt - from nothing - by any that does not.
    final rekeyed = widget.keying != old.keying;
    if (rekeyed) _keyer = widget.keying.createKeyer();

    // Anything that changes how the line is measured invalidates every cached layout and the
    // engine's positions with it, so those restart rather than animating from stale geometry.
    final restyled =
        rekeyed ||
        widget.style != old.style ||
        widget.textAlign != old.textAlign ||
        widget.textDirection != old.textDirection;

    _engine.setDurationScale(
      widget.duration.inMilliseconds /
          NumericTransitionModel.referenceDurationMs,
    );

    if (restyled) {
      _resolveStyle(snap: true);
      return;
    }

    _advance();
  }

  double get _alignFraction => switch (widget.textAlign) {
    TextAlign.left => 0.0,
    TextAlign.right => 1.0,
    TextAlign.start => _textDirection == TextDirection.rtl ? 1.0 : 0.0,
    TextAlign.end => _textDirection == TextDirection.rtl ? 0.0 : 1.0,
    _ => 0.5,
  };

  bool get _reduceMotion => switch (widget.reduceMotion) {
    NumericReduceMotion.always => true,
    NumericReduceMotion.never => false,
    NumericReduceMotion.system =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false,
  };

  /// Recomputes the text style and direction from the ambient defaults and re-measures the line.
  void _resolveStyle({required bool snap}) {
    final resolved = DefaultTextStyle.of(context).style.merge(widget.style);
    final direction =
        widget.textDirection ??
        Directionality.maybeOf(context) ??
        TextDirection.ltr;

    // The first call counts as a change whatever it resolves to: the caches have never been told
    // anything, and a bare tree really can resolve to the same empty style this state starts with.
    final changed =
        !_initialized || resolved != _style || direction != _textDirection;

    if (changed) {
      _style = resolved;
      _textDirection = direction;
      _glyphCache.retune(resolved, direction);
      _geometryCache.clear();
    }

    // A restyle invalidates every measurement the engine's positions were built from, so there is
    // no coherent state to animate out of and it has to restart.
    if (snap || changed) {
      _snap();
    } else {
      _advance();
    }
  }

  /// Measures [widget.text] and keys the line it produces.
  ({List<KeyedSlot> slots, double width, double height, double baseline})
  _measure() {
    final geometry = _geometryCache.measure(
      widget.text,
      _style,
      _textDirection,
    );

    return (
      slots: _keyer.assign(widget.text, geometry),
      width: geometry.width,
      height: geometry.lineHeight,
      baseline: geometry.baseline,
    );
  }

  /// Installs the current text with no animation.
  void _snap() {
    // Nothing that was on screen survives this, so the keyer must not go on matching against it.
    _keyer.reset();
    final line = _measure();

    _engine.reset(
      slots: line.slots,
      lineWidth: line.width,
      lineHeight: line.height,
      alignFraction: _alignFraction,
    );

    _text = widget.text;
    _lineWidth = line.width;
    _lineHeight = line.height;
    _baseline = line.baseline;

    // Nothing is in flight any more, so the clock can go back to zero - but only because the
    // epoch goes with it. Moving one without the other is what reintroduces the drift.
    _ticker.stop();
    _now = 0;
    _tickerEpoch = 0;

    _samples.value = _engine.sample(_now);

    if (mounted) setState(() {});
  }

  /// Begins a transition to the current text.
  void _advance() {
    // Two different values can render to the same string - 1.004 and 1.0 at two decimal places.
    // Nothing moved, so nothing should animate; starting a transition here would make a rounded
    // display twitch on every insignificant update.
    if (widget.text == _text) return;

    if (_reduceMotion) {
      _snap();
      return;
    }

    final line = _measure();

    _engine.setTarget(
      slots: line.slots,
      countsDown: widget.countsDown,
      now: _now,
      lineWidth: line.width,
      lineHeight: line.height,
      alignFraction: _alignFraction,
    );

    _text = widget.text;
    _lineWidth = line.width;
    _lineHeight = line.height;
    _baseline = line.baseline;

    _samples.value = _engine.sample(_now);
    _startTicker();
    setState(() {});
  }

  /// Starts the ticker, resuming the clock rather than restarting it.
  void _startTicker() {
    if (_ticker.isActive) return;
    _tickerEpoch = _now;
    _ticker.start();
  }

  void _onTick(Duration elapsed) {
    _now =
        _tickerEpoch + elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    _samples.value = _engine.sample(_now);

    if (!_engine.isRunning(_now)) {
      _ticker.stop();
      // The box can now collapse from the transition's widest extent to the settled width.
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _samples.dispose();
    _geometryCache.clear();
    _glyphCache.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = _engine.isRunning(_now)
        ? _engine.contentWidth(_now)
        : _lineWidth;

    // The painter draws glyphs, not text, so nothing reaches assistive technology unless it is
    // said here. The label is the string being settled on rather than anything mid-flight: a
    // screen reader should announce the value, never a frame of the animation. Not a container,
    // so - like Text - it merges into an enclosing button or list tile's label.
    return Semantics(
      label: widget.text,
      textDirection: _textDirection,
      child: CustomPaint(
        size: Size(width, _lineHeight),
        isComplex: true,
        painter: NumericTextPainter(
          samples: _samples,
          cache: _glyphCache,
          color: _style.color ?? const Color(0xFF000000),
          fractionColor: widget.fractionColor,
          lineHeight: _lineHeight,
          baseline: _baseline,
          alignFraction: _alignFraction,
          edgeFade: widget.edgeFade,
        ),
      ),
    );
  }
}
