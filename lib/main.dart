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
        if (snapshot.hasData) {
          return PlayerApp(controller: snapshot.requireData);
        }

        if (snapshot.hasError) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              backgroundColor: const Color(0xFFFFF9F5),
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        size: 52,
                        color: Color(0xFFFF7A22),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '聆听橙子启动失败',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${snapshot.error}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(height: 1.5),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        return MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            backgroundColor: const Color(0xFFFFF9F5),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DecoratedBox(
                    decoration: const BoxDecoration(
                      borderRadius: BorderRadius.all(Radius.circular(30)),
                      gradient: LinearGradient(
                        colors: [Color(0xFFFF9E57), Color(0xFFFF7A22)],
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.all(Radius.circular(22)),
                        child: Image.asset(
                          'assets/images/app_logo_cropped.png',
                          width: 72,
                          height: 72,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 18),
                  Text(
                    '聆听橙子',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                  ),
                  SizedBox(height: 8),
                  Text('正在加载'),
                  SizedBox(height: 16),
                  SizedBox(
                    width: 180,
                    child: LinearProgressIndicator(minHeight: 5),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
