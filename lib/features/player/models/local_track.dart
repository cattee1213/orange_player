import 'package:audio_service/audio_service.dart';
import 'package:path/path.dart' as p;

class LocalTrack {
  const LocalTrack({
    required this.id,
    required this.path,
    required this.title,
    required this.artist,
  });

  final String id;
  final String path;
  final String title;
  final String artist;

  factory LocalTrack.fromPath(
    String filePath, {
    String? title,
    String? artist,
  }) {
    final normalizedTitle = title == null || title.isEmpty
        ? p.basenameWithoutExtension(filePath)
        : p.basenameWithoutExtension(title);

    return LocalTrack(
      id: filePath,
      path: filePath,
      title: normalizedTitle,
      artist: artist == null || artist.isEmpty ? '本地音乐' : artist,
    );
  }

  factory LocalTrack.fromJson(Map<String, dynamic> json) {
    return LocalTrack(
      id: json['id'] as String,
      path: json['path'] as String,
      title: json['title'] as String,
      artist: json['artist'] as String? ?? '本地音乐',
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'path': path, 'title': title, 'artist': artist};
  }

  MediaItem get mediaItem =>
      MediaItem(id: id, title: title, artist: artist, album: '聆听橙子');
}
