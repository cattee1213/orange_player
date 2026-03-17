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
  @override
  void dispose() {
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFFFF6B00);
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
      primary: seed,
      secondary: const Color(0xFFFF9E57),
      surface: const Color(0xFFFFF7F2),
    );

    return MaterialApp(
      title: '聆听橙子',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xFFFFF7F2),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
        ),
        textTheme: const TextTheme(
          headlineMedium: TextStyle(fontWeight: FontWeight.w800),
          titleLarge: TextStyle(fontWeight: FontWeight.w700),
          titleMedium: TextStyle(fontWeight: FontWeight.w700),
          bodyLarge: TextStyle(height: 1.4),
        ),
      ),
      home: PlayerPage(controller: widget.controller),
    );
  }
}
