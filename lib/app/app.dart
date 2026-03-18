import 'package:flutter/material.dart';

import '../features/player/player_controller.dart';
import '../features/player/player_page.dart';

class OrangeAppShell extends StatelessWidget {
  const OrangeAppShell({super.key, required this.home});

  final Widget home;

  ThemeData _buildTheme(ColorScheme scheme) {
    final baseTheme = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return scheme.primary.withValues(alpha: 0.16);
            }
            return scheme.surfaceContainerHighest.withValues(alpha: 0.3);
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return scheme.primary;
            }
            return scheme.onSurfaceVariant;
          }),
          side: WidgetStateProperty.resolveWith(
            (states) => BorderSide(
              color: states.contains(WidgetState.selected)
                  ? scheme.primary.withValues(alpha: 0.28)
                  : scheme.outlineVariant.withValues(alpha: 0.28),
            ),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          ),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          elevation: 0,
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
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      dividerColor: scheme.outlineVariant.withValues(alpha: 0.18),
    );

    return baseTheme.copyWith(
      textTheme: baseTheme.textTheme.copyWith(
        displaySmall: baseTheme.textTheme.displaySmall?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -1,
        ),
        headlineMedium: baseTheme.textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.6,
        ),
        titleLarge: baseTheme.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        titleMedium: baseTheme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: baseTheme.textTheme.bodyLarge?.copyWith(height: 1.4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const lightScheme = ColorScheme(
      brightness: Brightness.light,
      primary: Color(0xFFFF7A22),
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFFFD8BC),
      onPrimaryContainer: Color(0xFF4B2100),
      secondary: Color(0xFFFFA14A),
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFFFFE7D4),
      onSecondaryContainer: Color(0xFF5A2D00),
      tertiary: Color(0xFFFFB86C),
      onTertiary: Color(0xFF492100),
      tertiaryContainer: Color(0xFFFFE7C9),
      onTertiaryContainer: Color(0xFF4C2500),
      error: Color(0xFFBA1A1A),
      onError: Colors.white,
      errorContainer: Color(0xFFFFDAD6),
      onErrorContainer: Color(0xFF410002),
      surface: Color(0xFFF7F4F1),
      onSurface: Color(0xFF181513),
      surfaceContainerHighest: Color(0xFFFFFFFF),
      onSurfaceVariant: Color(0xFF6B625D),
      outline: Color(0xFFD8C8BC),
      outlineVariant: Color(0xFFE7DDD6),
      shadow: Color(0x22000000),
      scrim: Color(0x66000000),
      inverseSurface: Color(0xFF2A2522),
      onInverseSurface: Color(0xFFF7EFEA),
      inversePrimary: Color(0xFFFFB684),
      surfaceTint: Color(0xFFFF7A22),
    );

    const darkScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFFFF8B3D),
      onPrimary: Color(0xFF301300),
      primaryContainer: Color(0xFF5B2500),
      onPrimaryContainer: Color(0xFFFFDCC4),
      secondary: Color(0xFFFFB56F),
      onSecondary: Color(0xFF391A00),
      secondaryContainer: Color(0xFF553000),
      onSecondaryContainer: Color(0xFFFFDDBE),
      tertiary: Color(0xFFFFC98D),
      onTertiary: Color(0xFF402000),
      tertiaryContainer: Color(0xFF5B3100),
      onTertiaryContainer: Color(0xFFFFE0BD),
      error: Color(0xFFFFB4AB),
      onError: Color(0xFF690005),
      errorContainer: Color(0xFF93000A),
      onErrorContainer: Color(0xFFFFDAD6),
      surface: Color(0xFF0C0C0E),
      onSurface: Color(0xFFF4EEEA),
      surfaceContainerHighest: Color(0xFF1A1A1E),
      onSurfaceVariant: Color(0xFFAEA39B),
      outline: Color(0xFF4E4742),
      outlineVariant: Color(0xFF2E2A27),
      shadow: Color(0x99000000),
      scrim: Color(0x99000000),
      inverseSurface: Color(0xFFF4EEEA),
      onInverseSurface: Color(0xFF1C1B1F),
      inversePrimary: Color(0xFF8B4500),
      surfaceTint: Color(0xFFFF8B3D),
    );

    return MaterialApp(
      title: '聆听橙子',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: _buildTheme(lightScheme),
      darkTheme: _buildTheme(darkScheme),
      home: home,
    );
  }
}

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
    return PlayerPage(controller: widget.controller);
  }
}
