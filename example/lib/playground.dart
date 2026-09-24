import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:rolly/rolly.dart';

import 'components.dart';
import 'formats.dart';
import 'sequence.dart';
import 'theme.dart';

/// Every part of the transition, on one screen: formats, a stepper that accelerates, a scripted
/// stress run, arbitrary text, and the knobs that change how it all moves.
class PlaygroundPage extends StatefulWidget {
  const PlaygroundPage({super.key});

  @override
  State<PlaygroundPage> createState() => _PlaygroundPageState();
}

class _PlaygroundPageState extends State<PlaygroundPage> {
  late FormatPreset _preset = formatPresets.first;
  late double _value = _preset.initial;

  var _durationMs = 320.0;
  var _fontSize = 62.0;
  var _direction = NumericDirection.automatic;
  var _reduceMotion = NumericReduceMotion.system;
  var _edgeFade = true;
  var _showPlain = true;

  var _phrase = 0;
  var _split = TextSplit.character;

  final _random = math.Random();

  late final SequencePlayer _player = SequencePlayer(
    onValue: (value) => setState(() => _value = value.toDouble()),
    onDone: () => setState(() {}),
  );

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Duration get _duration => Duration(milliseconds: _durationMs.round());

  void _bump(int sign) {
    _player.stop();
    setState(() {
      _value += sign * _preset.step;
      // Keeps floating point from turning 0.978 into 0.9780000000000001, which formats the same
      // but churns the value on every press.
      _value = double.parse(_value.toStringAsFixed(6));
    });
  }

  /// Jumps to an unrelated value, usually with a different number of digits.
  ///
  /// The thing to watch is that the roll looks the same as a `+1`: each surviving column enters
  /// from one fixed distance no matter how far the number moved, so a big jump reads through the
  /// columns being born and dying, not through any digit spinning further.
  void _randomize() {
    _player.stop();
    setState(() {
      final current = _preset.format.format(_value);
      // A jump that renders identically would waste the press, and with the small-magnitude
      // presets that happens often enough to notice.
      for (var attempt = 0; attempt < 8; attempt++) {
        final next = _preset.randomValue(_random);
        if (_preset.format.format(next) != current) {
          _value = next;
          return;
        }
      }
    });
  }

  void _selectPreset(FormatPreset preset) {
    _player.stop();
    setState(() {
      _preset = preset;
      _value = preset.initial;
    });
  }

  void _toggleSequence() {
    if (_player.isPlaying) {
      _player.stop();
      setState(() {});
      return;
    }
    setState(() {
      // The script is written in whole numbers, so it runs in the integer preset.
      _preset = formatPresets.first;
      _player.start();
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = Palette.of(context);
    return Scaffold(
      backgroundColor: palette.canvas,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 48),
              children: [
                const _Masthead(),
                const SizedBox(height: 26),
                _stage(palette),
                const SizedBox(height: 14),
                _stepper(),
                const SizedBox(height: 10),
                ActionButton(
                  label: 'Random jump',
                  icon: Icons.shuffle_rounded,
                  onPressed: _randomize,
                ),
                const SizedBox(height: 34),
                Section(
                  title: 'Format',
                  note: _preset.note,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _presetChips(),
                  ),
                ),
                const SizedBox(height: 32),
                Section(
                  title: 'Stress run',
                  note:
                      'Structural changes both ways, a sign crossing, a 60 ms burst, '
                      'and a reversal mid-flight.',
                  child: ActionButton(
                    label: _player.isPlaying ? 'Stop' : 'Play sequence',
                    icon: _player.isPlaying
                        ? Icons.stop_rounded
                        : Icons.play_arrow_rounded,
                    active: _player.isPlaying,
                    onPressed: _toggleSequence,
                  ),
                ),
                const SizedBox(height: 32),
                Section(
                  title: 'Text',
                  note:
                      'The same transition over a string. Each new line is diffed against the '
                      'one on screen: what survives reflows, what stands in a replaced column '
                      'rolls, the rest is born or dies.',
                  child: _textShowcase(palette),
                ),
                const SizedBox(height: 32),
                Section(title: 'Transition', child: _knobs(palette)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The number itself, with room above and below for glyphs that are rolling in or out.
  Widget _stage(Palette palette) {
    final style = TextStyle(
      fontSize: _fontSize,
      fontWeight: FontWeight.w700,
      color: palette.strong,
      height: 1.0,
      letterSpacing: -1,
      // Without this a settled "1" is narrower than a settled "8", and the whole line twitches
      // sideways every time a digit changes.
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Panel(
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 16),
      child: Column(
        children: [
          // Glyphs paint a little outside the widget's box while rolling, as they do on iOS.
          SizedBox(
            height: _fontSize * 1.9,
            child: Center(
              child: NumericText(
                value: _value,
                format: _preset.format,
                style: style,
                fractionColor: _preset.tintFraction ? palette.muted : null,
                direction: _direction,
                duration: _duration,
                reduceMotion: _reduceMotion,
                edgeFade: _edgeFade,
              ),
            ),
          ),
          if (_showPlain) ...[
            Divider(color: palette.hairline, height: 26),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'plain Text',
                  style: TextStyle(
                    color: palette.muted,
                    fontSize: 11,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  _preset.format.format(_value),
                  style: TextStyle(
                    color: palette.muted,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _stepper() {
    return Row(
      children: [
        Expanded(
          child: HoldRepeatButton(
            onFire: () => _bump(-1),
            icon: Icons.remove_rounded,
            label: 'hold to run down',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: HoldRepeatButton(
            onFire: () => _bump(1),
            icon: Icons.add_rounded,
            label: 'hold to run up',
          ),
        ),
      ],
    );
  }

  List<Widget> _presetChips() => [
    for (final preset in formatPresets)
      SelectChip(
        label: preset.label,
        selected: preset.label == _preset.label,
        onTap: () => _selectPreset(preset),
      ),
  ];

  /// Phrases chosen for what each step exercises, in order: a shared prefix reflowing, a short
  /// replacement rolling in place (`ON` -> `OFF`), a digit changing inside a sentence, a long
  /// shrink, and an Arabic pair — where the first word rolls into its replacement while the second
  /// only reflows, because a joining run is never cut into letters.
  static const _phrases = [
    'Idle',
    'Connecting…',
    'Connected',
    'ON',
    'OFF',
    'Uploading 3 files',
    'Uploading 12 files',
    'Done',
    'جاري التحميل',
    'تم التحميل',
  ];

  Widget _textShowcase(Palette palette) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Panel(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          // Room above and below for glyphs that are rolling in or out.
          child: SizedBox(
            height: 72,
            child: Center(
              child: RollingText(
                _phrases[_phrase],
                split: _split,
                style: TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.w600,
                  color: palette.strong,
                  height: 1.0,
                ),
                duration: _duration,
                reduceMotion: _reduceMotion,
                edgeFade: _edgeFade,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        ActionButton(
          label: 'Next phrase',
          icon: Icons.skip_next_rounded,
          onPressed: () =>
              setState(() => _phrase = (_phrase + 1) % _phrases.length),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            for (final split in TextSplit.values)
              SelectChip(
                label: switch (split) {
                  TextSplit.character => 'By character',
                  TextSplit.word => 'By word',
                },
                selected: _split == split,
                onTap: () => setState(() => _split = split),
              ),
          ],
        ),
      ],
    );
  }

  Widget _knobs(Palette palette) {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LabelledSlider(
            label: 'Duration',
            value: _durationMs,
            min: 80,
            max: 1200,
            // 320 ms is the timing the transition was designed at; the rest of the range
            // stretches every channel together.
            display:
                '${_durationMs.round()} ms'
                '${(_durationMs - 320).abs() < 1 ? '  ·  default' : ''}',
            onChanged: (v) => setState(() => _durationMs = v),
          ),
          const SizedBox(height: 10),
          LabelledSlider(
            label: 'Size',
            value: _fontSize,
            min: 28,
            max: 96,
            display: '${_fontSize.round()} pt',
            onChanged: (v) => setState(() => _fontSize = v),
          ),
          const SizedBox(height: 18),
          _knobLabel(palette, 'Direction'),
          Wrap(
            spacing: 8,
            children: [
              for (final direction in NumericDirection.values)
                SelectChip(
                  label: switch (direction) {
                    NumericDirection.automatic => 'Automatic',
                    NumericDirection.up => 'Force up',
                    NumericDirection.down => 'Force down',
                  },
                  selected: _direction == direction,
                  onTap: () => setState(() => _direction = direction),
                ),
            ],
          ),
          const SizedBox(height: 18),
          _knobLabel(palette, 'Reduced motion'),
          Wrap(
            spacing: 8,
            children: [
              for (final mode in NumericReduceMotion.values)
                SelectChip(
                  label: switch (mode) {
                    NumericReduceMotion.system => 'Follow system',
                    NumericReduceMotion.always => 'Snap',
                    NumericReduceMotion.never => 'Always animate',
                  },
                  selected: _reduceMotion == mode,
                  onTap: () => setState(() => _reduceMotion = mode),
                ),
            ],
          ),
          const SizedBox(height: 4),
          _switch(
            palette,
            label: 'Edge fade',
            value: _edgeFade,
            onChanged: (v) => setState(() => _edgeFade = v),
          ),
          _switch(
            palette,
            label: 'Show the same value as plain Text',
            value: _showPlain,
            onChanged: (v) => setState(() => _showPlain = v),
          ),
        ],
      ),
    );
  }

  Widget _knobLabel(Palette palette, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text,
      style: TextStyle(
        color: palette.muted,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Widget _switch(
    Palette palette, {
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile.adaptive(
      value: value,
      onChanged: onChanged,
      contentPadding: EdgeInsets.zero,
      dense: true,
      activeThumbColor: palette.accent,
      title: Text(
        label,
        style: TextStyle(color: palette.strong, fontSize: 13.5),
      ),
    );
  }
}

class _Masthead extends StatelessWidget {
  const _Masthead();

  @override
  Widget build(BuildContext context) {
    final palette = Palette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'rolly',
          style: TextStyle(
            color: palette.strong,
            fontSize: 30,
            fontWeight: FontWeight.w700,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Numbers and text that animate the way they do on iOS.',
          style: TextStyle(color: palette.muted, fontSize: 13.5, height: 1.45),
        ),
      ],
    );
  }
}
