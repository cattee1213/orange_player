import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:orange_player/features/online_library/online_catalog.dart';
import 'package:orange_player/features/online_library/online_library_cache.dart';
import 'package:orange_player/features/player/models/local_track.dart';

void main() {
  test('catalog round-trips on disk', () async {
    final root = await Directory.systemTemp.createTemp('orange_catalog');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    final cache = OnlineLibraryCache(root: root);
    final snapshot = OnlineLibrarySnapshot(
      url: 'https://example.com/music/',
      sourceLabel: 'library.json',
      truncated: false,
      fetchedAt: DateTime.utc(2026, 11, 21, 8),
      tracks: [
        LocalTrack.remote(
          url: 'https://example.com/music/a.mp3',
          title: '晚风',
          artist: '橙子',
        ),
      ],
    );

    await cache.writeCatalog(snapshot);
    final restored = await cache.readCatalog();

    expect(restored?.url, snapshot.url);
    expect(restored?.sourceLabel, 'library.json');
    expect(restored?.tracks.single.title, '晚风');
    expect(restored?.tracks.single.artist, '橙子');
    expect(restored?.tracks.single.isRemote, isTrue);

    final audio = await cache.targetAudioFile(snapshot.tracks.single.path);
    await audio.parent.create(recursive: true);
    await audio.writeAsBytes(const [1, 2, 3]);

    await cache.clear();
    expect(await cache.readCatalog(), isNull);
    expect(await cache.isAudioCached(snapshot.tracks.single.path), isFalse);
    expect(await cache.audioBytes(), 0);
  });

  test('an existing audio file is not downloaded again', () async {
    final root = await Directory.systemTemp.createTemp('orange_audio');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    var requests = 0;
    final cache = OnlineLibraryCache(
      root: root,
      client: MockClient((request) async {
        requests += 1;
        return http.Response.bytes(const [1, 2, 3, 4], 200);
      }),
    );
    const url = 'https://example.com/files/song.data';
    final file = await cache.targetAudioFile(url);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(const [9, 8, 7]);

    await cache.downloadAudio(url);

    expect(requests, 0);
    expect(await cache.isAudioCached(url), isTrue);
    expect(await cache.audioBytes(), 3);

    await cache.clearAudio();
    expect(await cache.isAudioCached(url), isFalse);
    expect(await cache.audioBytes(), 0);
  });

  test('a failed download does not create an audio file', () async {
    final root = await Directory.systemTemp.createTemp('orange_audio_fail');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    final cache = OnlineLibraryCache(
      root: root,
      client: MockClient((request) async {
        return http.Response.bytes(const [], 404);
      }),
    );
    const url = 'https://example.com/missing.mp3';

    await expectLater(cache.downloadAudio(url), throwsA(isA<Exception>()));
    expect(await cache.isAudioCached(url), isFalse);
    expect(await _partials(root), isEmpty);
  });

  test(
    'a download is streamed to disk and the partial file is removed',
    () async {
      final root = await Directory.systemTemp.createTemp('orange_audio_stream');
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });

      final cache = OnlineLibraryCache(
        root: root,
        client: _ChunkClient([
          [1, 2],
          [3, 4],
        ]),
      );
      const url = 'https://example.com/album/song.mp3';
      final progress = <int>[];

      await cache.downloadAudio(
        url,
        onProgress: (received, total) => progress.add(received),
      );

      final file = await cache.cachedAudio(url);
      expect(await file?.readAsBytes(), [1, 2, 3, 4]);
      expect(progress, [2, 4]);
      expect(await _partials(root), isEmpty);
    },
  );

  test('a short download is rejected and leaves no partial file', () async {
    final root = await Directory.systemTemp.createTemp('orange_audio_short');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    final cache = OnlineLibraryCache(
      root: root,
      client: _ChunkClient([
        [1, 2, 3],
      ], contentLength: 8),
    );

    await expectLater(
      cache.downloadAudio('https://example.com/short.mp3'),
      throwsA(isA<OnlineLibraryException>()),
    );
    expect(await cache.isAudioCached('https://example.com/short.mp3'), isFalse);
    expect(await _partials(root), isEmpty);
  });

  test('cancelling a download removes the partial file', () async {
    final root = await Directory.systemTemp.createTemp('orange_audio_cancel');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    final cache = OnlineLibraryCache(
      root: root,
      client: _ChunkClient([
        [1, 2],
        [3, 4],
      ]),
    );
    var chunks = 0;

    await expectLater(
      cache.downloadAudio(
        'https://example.com/cancel.mp3',
        isCancelled: () => chunks > 0,
        onProgress: (received, total) => chunks += 1,
      ),
      throwsA(isA<DownloadCancelled>()),
    );
    expect(
      await cache.isAudioCached('https://example.com/cancel.mp3'),
      isFalse,
    );
    expect(await _partials(root), isEmpty);
  });
}

class _ChunkClient extends http.BaseClient {
  _ChunkClient(this.chunks, {this.contentLength});

  final List<List<int>> chunks;
  final int? contentLength;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final length = chunks.fold<int>(0, (sum, chunk) => sum + chunk.length);
    return http.StreamedResponse(
      Stream<List<int>>.fromIterable(chunks),
      200,
      contentLength: contentLength ?? length,
    );
  }
}

Future<List<FileSystemEntity>> _partials(Directory root) async {
  final directory = Directory('${root.path}${Platform.pathSeparator}audio');
  if (!await directory.exists()) {
    return const [];
  }
  final entities = await directory.list().toList();
  return entities.where((entity) => entity.path.endsWith('.part')).toList();
}
