import 'package:flutter/material.dart';

import '../features/player/player_controller.dart';
import '../features/player/player_page.dart';

class PlayerApp extends StatefulWidget {
  const PlayerApp({super.key, required this.controller});

  final PlayerController controller;

  @override
  State<PlayerApp> createState() => _PlayerAppState();
}

class _PlayerAppState extends State<PlayerApp> {
  ThemeData _buildTheme(ColorScheme scheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      navigationBarTheme: NavigationBarThemeData(
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w700),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(fontWeight: FontWeight.w800),
        titleLarge: TextStyle(fontWeight: FontWeight.w700),
        titleMedium: TextStyle(fontWeight: FontWeight.w700),
        bodyLarge: TextStyle(height: 1.4),
      ),
    );
  }

  @override
  void dispose() {
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const lightSeed = Color(0xFFFF7A22);
    final lightScheme = ColorScheme.fromSeed(
      seedColor: lightSeed,
      brightness: Brightness.light,
      primary: lightSeed,
      secondary: const Color(0xFFE4A26A),
      surface: const Color(0xFFFFF9F5),
    );

    const darkSeed = Color(0xFFFF8C42);
    final darkScheme = ColorScheme.fromSeed(
      seedColor: darkSeed,
      brightness: Brightness.dark,
      primary: darkSeed,
      secondary: const Color(0xFFC98557),
      surface: const Color(0xFF161616),
    );

    return MaterialApp(
      title: '聆听橙子',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: _buildTheme(lightScheme),
      darkTheme: _buildTheme(darkScheme),
      home: PlayerPage(controller: widget.controller),
    );
  }
}
