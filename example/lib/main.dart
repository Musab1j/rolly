import 'package:flutter/material.dart';

import 'playground.dart';
import 'theme.dart';

void main() => runApp(const RollyApp());

/// The rolly playground: every part of the transition on one screen.
class RollyApp extends StatelessWidget {
  const RollyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'rolly',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: _theme(Brightness.light, Palette.light),
      darkTheme: _theme(Brightness.dark, Palette.dark),
      home: const PlaygroundPage(),
    );
  }

  static ThemeData _theme(Brightness brightness, Palette palette) {
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: palette.accent,
        brightness: brightness,
      ),
      scaffoldBackgroundColor: palette.canvas,
      extensions: [palette],
    );
  }
}
