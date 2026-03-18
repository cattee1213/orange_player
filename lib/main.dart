import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'app/app.dart';
import 'features/player/player_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _BootstrapApp());
}

class _BootstrapApp extends StatefulWidget {
  const _BootstrapApp();

  @override
  State<_BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<_BootstrapApp> {
  late final Future<PlayerController> _controllerFuture = _bootstrap();

  Widget _bootstrapShell({required Widget child, required Color background}) {
    return Scaffold(
      backgroundColor: background,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [background, background.withValues(alpha: 0.96)],
          ),
        ),
        child: child,
      ),
    );
  }

  Future<PlayerController> _bootstrap() async {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.orange_player.channel.audio',
      androidNotificationChannelName: '聆听橙子播放控制',
      androidNotificationOngoing: true,
    );
    return PlayerController.bootstrap();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PlayerController>(
      future: _controllerFuture,
      builder: (context, snapshot) {
        final content = switch ((snapshot.hasData, snapshot.hasError)) {
          (true, _) => PlayerApp(controller: snapshot.requireData),
          (_, true) => _bootstrapShell(
            background: const Color(0xFFF7F4F1),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF7A22).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: const Icon(
                        Icons.error_outline_rounded,
                        size: 42,
                        color: Color(0xFFFF7A22),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      '聆听橙子启动失败',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        height: 1.5,
                        color: Color(0xFF6B625D),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _ => _bootstrapShell(
            background: const Color(0xFFF7F4F1),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 112,
                    height: 112,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(34),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFFFB57A), Color(0xFFFF7A22)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF7A22).withValues(alpha: 0.2),
                          blurRadius: 24,
                          offset: const Offset(0, 16),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: Image.asset(
                          'assets/images/app_logo_cropped.png',
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    '聆听橙子',
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '正在建立你的音乐空间',
                    style: TextStyle(color: Color(0xFF6B625D)),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: 220,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: const LinearProgressIndicator(minHeight: 4),
                    ),
                  ),
                ],
              ),
            ),
          ),
        };

        return OrangeAppShell(home: content);
      },
    );
  }
}
