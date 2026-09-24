import 'package:flutter/material.dart';

/// The playground's colours, kept as a theme extension so every surface resolves through
/// `Theme.of(context)` and follows the platform between light and dark.
@immutable
class Palette extends ThemeExtension<Palette> {
  const Palette({
    required this.canvas,
    required this.surface,
    required this.hairline,
    required this.muted,
    required this.accent,
    required this.accentSoft,
    required this.strong,
  });

  /// Page background, a shade behind [surface].
  final Color canvas;

  /// Cards, buttons and chips at rest.
  final Color surface;

  /// The one-pixel border that separates a surface from the canvas.
  final Color hairline;

  /// Secondary text: labels, captions, the tinted fraction digits.
  final Color muted;

  /// The selection colour.
  final Color accent;

  /// A low-alpha [accent], for the fill behind a selected control.
  final Color accentSoft;

  /// Primary text, and the number itself.
  final Color strong;

  static const dark = Palette(
    canvas: Color(0xFF07080A),
    surface: Color(0xFF101318),
    hairline: Color(0xFF1E2229),
    muted: Color(0xFF7C8698),
    accent: Color(0xFF6AA6FF),
    accentSoft: Color(0x336AA6FF),
    strong: Color(0xFFF7F9FC),
  );

  static const light = Palette(
    canvas: Color(0xFFF5F7FA),
    surface: Color(0xFFFFFFFF),
    hairline: Color(0xFFE3E8EF),
    muted: Color(0xFF69738A),
    accent: Color(0xFF2F6BE4),
    accentSoft: Color(0x1F2F6BE4),
    strong: Color(0xFF0B0D12),
  );

  static Palette of(BuildContext context) =>
      Theme.of(context).extension<Palette>() ?? dark;

  @override
  Palette copyWith({
    Color? canvas,
    Color? surface,
    Color? hairline,
    Color? muted,
    Color? accent,
    Color? accentSoft,
    Color? strong,
  }) {
    return Palette(
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      hairline: hairline ?? this.hairline,
      muted: muted ?? this.muted,
      accent: accent ?? this.accent,
      accentSoft: accentSoft ?? this.accentSoft,
      strong: strong ?? this.strong,
    );
  }

  @override
  Palette lerp(covariant Palette? other, double t) {
    if (other == null) return this;
    return Palette(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      strong: Color.lerp(strong, other.strong, t)!,
    );
  }
}
