import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/return_code.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../player/models/local_track.dart';

class VideoToMp3Service {
  Future<File?> pickVideo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp4'],
    );
    final inputPath = result?.files.singleOrNull?.path;
    if (inputPath == null || inputPath.isEmpty) {
      return null;
    }
    return File(inputPath);
  }

  Future<LocalTrack> convert(File source) async {
    if (!await source.exists()) {
      throw StateError('无法读取所选视频文件。');
    }

    final outputDirectory = await LocalMusicLibrary.outputDirectory();
    final outputName = _outputName(source.path);
    final output = File(p.join(outputDirectory.path, outputName));
    final command = [
      '-y',
      '-i',
      source.path,
      '-vn',
      '-codec:a',
      'libmp3lame',
      '-b:a',
      '192k',
      output.path,
    ];

    try {
      final session = await FFmpegKit.executeWithArguments(command);
      final returnCode = await session.getReturnCode();
      if (!ReturnCode.isSuccess(returnCode) || !await output.exists()) {
        final outputText = await session.getOutput();
        throw StateError(
          ReturnCode.isCancel(returnCode)
              ? '转码已取消。'
              : '转码失败：${outputText?.trim() ?? '视频可能没有可用音轨'}',
        );
      }
      if (await output.length() == 0) {
        throw StateError('未生成有效的 MP3 文件。');
      }
      return LocalTrack(
        id: output.path,
        path: output.path,
        title: p.basenameWithoutExtension(source.path),
        artist: '视频音轨',
        isGenerated: true,
      );
    } catch (_) {
      if (await output.exists()) {
        await output.delete();
      }
      rethrow;
    }
  }

  String _outputName(String sourcePath) {
    final rawName = p.basenameWithoutExtension(sourcePath);
    final safeName = rawName
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return '${safeName.isEmpty ? 'video_audio' : safeName}_$timestamp.mp3';
  }
}

class LocalMusicLibrary {
  static Future<Directory> outputDirectory() async {
    final externalDirectory = await getExternalStorageDirectory();
    if (externalDirectory == null) {
      throw StateError('无法访问应用本地存储。');
    }
    final directory = Directory(
      p.join(externalDirectory.path, 'OrangePlayer', 'mp3'),
    );
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  static Future<List<LocalTrack>> loadTracks() async {
    final directory = await outputDirectory();
    final entities = await directory
        .list()
        .where(
          (entity) =>
              entity is File &&
              p.extension(entity.path).toLowerCase() == '.mp3',
        )
        .cast<File>()
        .toList();
    entities.sort(
      (first, second) =>
          second.statSync().modified.compareTo(first.statSync().modified),
    );
    return entities
        .map(
          (file) => LocalTrack(
            id: file.path,
            path: file.path,
            title: p
                .basenameWithoutExtension(file.path)
                .replaceFirst(RegExp(r'_\d{13}$'), ''),
            artist: '视频音轨',
            isGenerated: true,
          ),
        )
        .toList();
  }

  static Future<int> totalBytes() async {
    final directory = await outputDirectory();
    var bytes = 0;
    await for (final entity in directory.list()) {
      if (entity is File && p.extension(entity.path).toLowerCase() == '.mp3') {
        bytes += await entity.length();
      }
    }
    return bytes;
  }

  static Future<void> deleteTrack(LocalTrack track) async {
    if (!track.isGenerated) {
      throw ArgumentError('只能删除本应用生成的 MP3 文件。');
    }
    final file = File(track.path);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
