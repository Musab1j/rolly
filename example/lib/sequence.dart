import 'dart:async';

import 'package:flutter/foundation.dart';

/// One value, held for a while before the next.
@immutable
class SequenceStep {
  const SequenceStep(this.value, this.holdMs);
  final num value;
  final int holdMs;
}

/// A stress script. Every phase targets something the model has to get right, and the ordering
/// matters:
///
///  * `1992 -> 1993 -> 1994` — isolated single-digit rolls, slow enough to read.
///  * `99 -> 100 -> 1` — structural changes in both directions: a digit born, then three dying.
///  * `0 -> -1 -> … -> -4` — crossing zero. The critical probe: the units digit goes 0 -> 1, a
///    numeric *increase*, while the number decreases. It must roll with everything else.
///  * `1000 -> 999 -> 1000` at ~360 ms — a structural change re-triggered before it finished.
///  * `+123` tightening from 360 ms to 60 ms — a simulated press-and-hold. The column degrades
///    into a soft pair and must recover, not stutter or snap.
///  * a decelerating rollback to 1992 — reversal while still in flight.
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

/// Walks a list of [SequenceStep]s, emitting each value in turn.
class SequencePlayer {
  SequencePlayer({required this.onValue, required this.onDone});

  final ValueChanged<num> onValue;
  final VoidCallback onDone;

  Timer? _timer;
  int _index = 0;

  bool get isPlaying => _timer != null;

  void start([List<SequenceStep> steps = showcaseSequence]) {
    stop();
    _index = 0;
    _step(steps);
  }

  void _step(List<SequenceStep> steps) {
    if (_index >= steps.length) {
      _timer = null;
      onDone();
      return;
    }

    final step = steps[_index++];
    onValue(step.value);
    _timer = Timer(Duration(milliseconds: step.holdMs), () => _step(steps));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() => stop();
}
