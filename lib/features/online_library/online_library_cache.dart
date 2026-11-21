import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../player/models/local_track.dart';
import 'online_catalog.dart';

class DownloadCancelled implements Exception {
  const DownloadCancelled();
}

class OnlineLibrarySnapshot {
  const OnlineLibrarySnapshot({
    required this.url,
    required this.sourceLabel,
    required this.truncated,
    required this.fetchedAt,
    required this.tracks,
  });

  final String url;
  final String sourceLabel;
  final bool truncated;
  final DateTime fetchedAt;
  final List<LocalTrack> tracks;

  Map<String, dynamic> toJson() {
    return {
      'url': url,
      'sourceLabel': sourceLabel,
      'truncated': truncated,
      'fetchedAt': fetchedAt.toUtc().toIso8601String(),
      'tracks': tracks.map((track) => track.toJson()).toList(),
    };
  }

  factory OnlineLibrarySnapshot.fromJson(Map<String, dynamic> json) {
    final tracks = (json['tracks'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((item) => LocalTrack.fromJson(Map<String, dynamic>.from(item)))
        .toList();
    return OnlineLibrarySnapshot(
      url: json['url'] as String? ?? '',
      sourceLabel: json['sourceLabel'] as String? ?? '缓存',
      truncated: json['truncated'] as bool? ?? false,
      fetchedAt:
          DateTime.tryParse(json['fetchedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      tracks: tracks,
    );
  }
}

class OnlineLibraryCache {
  OnlineLibraryCache({Directory? root, http.Client? client})
    : _rootOverride = root,
      _client = client;

  static final instance = OnlineLibraryCache();

  final Directory? _rootOverride;
  final http.Client? _client;
  final Map<String, Future<void>> _downloads = {};

  Future<OnlineLibrarySnapshot?> readCatalog() async {
    final file = File(p.join((await _root()).path, 'catalog.json'));
    if (!await file.exists()) {
      return null;
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        return null;
      }
      final snapshot = OnlineLibrarySnapshot.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      if (snapshot.url.isEmpty) {
        return null;
      }
      return snapshot;
    } catch (_) {
      return null;
    }
  }

  Future<void> writeCatalog(OnlineLibrarySnapshot snapshot) async {
    final root = await _root();
    final file = File(p.join(root.path, 'catalog.json'));
    await file.writeAsString(jsonEncode(snapshot.toJson()));
  }

  Future<File> targetAudioFile(String url) => _audioFile(url);

  Future<bool> isAudioCached(String url) async {
    final file = await _audioFile(url);
    return _isComplete(file);
  }

  Future<File?> cachedAudio(String url) async {
    final file = await _audioFile(url);
    if (!await _isComplete(file)) {
      return null;
    }
    return file;
  }

  Future<Set<String>> cachedUrls(Iterable<String> urls) async {
    final cached = <String>{};
    for (final url in urls) {
      if (await isAudioCached(url)) {
        cached.add(url);
      }
    }
    return cached;
  }

  Future<int> audioBytes() async {
    final directory = await _audioDirectory();
    if (!await directory.exists()) {
      return 0;
    }
    var total = 0;
    await for (final entity in directory.list()) {
      if (entity is! File || entity.path.endsWith('.part')) {
        continue;
      }
      total += await entity.length();
    }
    return total;
  }

  Future<void> clearAudio() async {
    final directory = await _audioDirectory();
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  Future<void> downloadAudio(
    String url, {
    void Function(int received, int? total)? onProgress,
    bool Function()? isCancelled,
  }) {
    final pending = _downloads[url];
    if (pending != null) {
      return pending;
    }
    final task = _writeAudio(
      url,
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
    _downloads[url] = task;
    return task.whenComplete(() {
      if (identical(_downloads[url], task)) {
        _downloads.remove(url);
      }
    });
  }

  Future<void> _writeAudio(
    String url, {
    void Function(int received, int? total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (isCancelled?.call() == true) {
      throw const DownloadCancelled();
    }
    final target = await _audioFile(url);
    if (await _isComplete(target)) {
      return;
    }
    await target.parent.create(recursive: true);
    final partial = File('${target.path}.part');
    await _deleteIfExists(partial);

    final client = _client ?? http.Client();
    final ownsClient = _client == null;
    var received = 0;
    IOSink? sink;
    try {
      final request = http.Request('GET', Uri.parse(url));
      request.headers['User-Agent'] = 'OrangePlayer';
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        await response.stream.drain<void>();
        throw OnlineLibraryException('下载失败（${response.statusCode}）');
      }

      final total = response.contentLength;
      sink = partial.openWrite();
      await sink.addStream(
        response.stream
            .map((chunk) {
              if (isCancelled?.call() == true) {
                throw const DownloadCancelled();
              }
              received += chunk.length;
              onProgress?.call(received, total);
              return chunk;
            })
            .timeout(const Duration(seconds: 30)),
      );
      await sink.flush();
      await sink.close();
      sink = null;

      if (isCancelled?.call() == true) {
        throw const DownloadCancelled();
      }
      if (received == 0 || (total != null && received != total)) {
        throw const OnlineLibraryException('音频下载不完整');
      }
      if (await target.exists()) {
        await target.delete();
      }
      await partial.rename(target.path);
    } on DownloadCancelled {
      rethrow;
    } on OnlineLibraryException {
      rethrow;
    } on TimeoutException {
      throw const OnlineLibraryException('下载超时');
    } catch (_) {
      throw const OnlineLibraryException('音频下载失败');
    } finally {
      final openSink = sink;
      if (openSink != null) {
        try {
          await openSink.close();
        } catch (_) {}
      }
      if (!await _isComplete(target)) {
        await _deleteIfExists(partial);
      }
      if (ownsClient) {
        client.close();
      }
    }
  }

  Future<Directory> _root() async {
    final override = _rootOverride;
    if (override != null) {
      if (!await override.exists()) {
        await override.create(recursive: true);
      }
      return override;
    }
    final support = await getApplicationSupportDirectory();
    final directory = Directory(p.join(support.path, 'online_library'));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<Directory> _audioDirectory() async {
    return Directory(p.join((await _root()).path, 'audio'));
  }

  Future<File> _audioFile(String url) async {
    final directory = await _audioDirectory();
    final hash = sha256.convert(utf8.encode(url)).toString();
    return File(p.join(directory.path, '$hash${_audioExtension(url)}'));
  }

  Future<bool> _isComplete(File file) async {
    return await file.exists() && await file.length() > 0;
  }
}

Future<void> _deleteIfExists(File file) async {
  if (await file.exists()) {
    await file.delete();
  }
}

String _audioExtension(String url) {
  final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
  const extensions = [
    '.mp3',
    '.m4a',
    '.aac',
    '.flac',
    '.wav',
    '.ogg',
    '.opus',
    '.wma',
  ];
  for (final extension in extensions) {
    if (path.endsWith(extension)) {
      return extension;
    }
  }
  return '.audio';
}

String formatByteSize(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
