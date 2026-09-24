import 'dart:async';

import 'package:flutter/material.dart';

import 'theme.dart';

/// A titled block of the page. The title is a small upright label rather than a heading, so the
/// numbers stay the loudest thing on screen.
class Section extends StatelessWidget {
  const Section({
    required this.title,
    required this.child,
    this.note,
    super.key,
  });

  final String title;
  final String? note;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = Palette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title.toUpperCase(),
          style: TextStyle(
            color: palette.muted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        if (note != null) ...[
          const SizedBox(height: 6),
          Text(
            note!,
            style: TextStyle(
              color: palette.muted,
              fontSize: 12.5,
              height: 1.45,
            ),
          ),
        ],
        const SizedBox(height: 14),
        child,
      ],
    );
  }
}

/// A hairline-bordered surface. Every panel on the page is one of these.
class Panel extends StatelessWidget {
  const Panel({required this.child, this.padding, super.key});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final palette = Palette.of(context);
    return Material(
      color: palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: palette.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: padding ?? const EdgeInsets.all(18),
        child: child,
      ),
    );
  }
}

/// A selectable pill.
class SelectChip extends StatelessWidget {
  const SelectChip({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = Palette.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? palette.accentSoft : palette.surface,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: selected ? palette.accent : palette.hairline,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? palette.accent : palette.muted,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// A full-width button on the same hairline surface as everything else.
class ActionButton extends StatelessWidget {
  const ActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.active = false,
    super.key,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  /// Tints the button, for a control that is currently doing something.
  final bool active;

  @override
  Widget build(BuildContext context) {
    final palette = Palette.of(context);
    return SizedBox(
      width: double.infinity,
      child: TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: TextButton.styleFrom(
          foregroundColor: active ? palette.accent : palette.strong,
          backgroundColor: active ? palette.accentSoft : palette.surface,
          padding: const EdgeInsets.symmetric(vertical: 14),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: active ? palette.accent : palette.hairline),
          ),
        ),
      ),
    );
  }
}

/// A labelled slider with its current value read out beside the label.
class LabelledSlider extends StatelessWidget {
  const LabelledSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.display,
    required this.onChanged,
    super.key,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String display;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = Palette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                color: palette.muted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              display,
              style: TextStyle(color: palette.strong, fontSize: 12),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            activeTrackColor: palette.accent,
            inactiveTrackColor: palette.hairline,
            thumbColor: palette.strong,
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
          ),
          child: Slider(value: value, min: min, max: max, onChanged: onChanged),
        ),
      ],
    );
  }
}

/// A stepper button that keeps firing, faster and faster, while it is held.
///
/// The acceleration is the point. A press-and-hold walks the cadence from "one isolated change"
/// down to "faster than the transition can finish", which is where the interruption model shows
/// itself: columns degrade into a soft pair and recover, and never show a digit that was not a
/// real value.
class HoldRepeatButton extends StatefulWidget {
  const HoldRepeatButton({
    required this.onFire,
    required this.icon,
    required this.label,
    super.key,
  });

  final VoidCallback onFire;
  final IconData icon;
  final String label;

  @override
  State<HoldRepeatButton> createState() => _HoldRepeatButtonState();
}

class _HoldRepeatButtonState extends State<HoldRepeatButton> {
  Timer? _timer;
  var _intervalMs = 320;
  var _pressed = false;

  void _start() {
    setState(() => _pressed = true);
    widget.onFire();
    _intervalMs = 320;
    _schedule();
  }

  void _schedule() {
    _timer = Timer(Duration(milliseconds: _intervalMs), () {
      widget.onFire();
      // Ramps 320 -> 230 -> 166 -> 119 -> 86 -> 62 -> 55 ms.
      _intervalMs = (_intervalMs * 0.72).round().clamp(55, 320);
      _schedule();
    });
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    if (mounted) setState(() => _pressed = false);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = Palette.of(context);
    return GestureDetector(
      onTapDown: (_) => _start(),
      onTapUp: (_) => _stop(),
      onTapCancel: _stop,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          color: _pressed ? palette.accentSoft : palette.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _pressed ? palette.accent : palette.hairline,
          ),
        ),
        child: Column(
          children: [
            Icon(
              widget.icon,
              color: _pressed ? palette.accent : palette.strong,
              size: 24,
            ),
            const SizedBox(height: 3),
            Text(
              widget.label,
              style: TextStyle(color: palette.muted, fontSize: 10.5),
            ),
          ],
        ),
      ),
    );
  }
}
