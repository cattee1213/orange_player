import 'package:flutter_test/flutter_test.dart';
import 'package:orange_player/features/online_library/online_catalog.dart';
import 'package:orange_player/features/online_library/online_music_library.dart';
import 'package:orange_player/features/player/models/local_track.dart';

void main() {
  test('normalizes a directory URL and keeps a manifest URL', () {
    expect(
      normalizeLibraryUrl('example.com/music').toString(),
      'https://example.com/music/',
    );
    expect(
      normalizeLibraryUrl('https://example.com/music/library.json').toString(),
      'https://example.com/music/library.json',
    );
    expect(
      () => normalizeLibraryUrl('https://user:pass@example.com/music/'),
      throwsA(isA<OnlineLibraryException>()),
    );
  });

  test('remote track round-trips through json', () {
    final track = LocalTrack.remote(
      url: 'https://example.com/a.mp3',
      title: '晚风',
      artist: '橙子',
    );

    final restored = LocalTrack.fromJson(track.toJson());

    expect(restored.isRemote, isTrue);
    expect(restored.title, '晚风');
    expect(restored.path, track.path);
    expect(LocalTrack.fromPath(r'C:\music\a.mp3').isRemote, isFalse);
  });

  test('folder label is relative to the library root', () {
    expect(
      libraryFolderLabel(
        'https://example.com/music/album/晚风.mp3',
        libraryUrl: 'https://example.com/music/',
      ),
      'album',
    );
    expect(
      libraryFolderLabel(
        'https://example.com/music/晚风.mp3',
        libraryUrl: 'https://example.com/music/',
      ),
      '根目录',
    );
    expect(
      libraryFolderLabel(
        'https://example.com/music/a/b/晚风.mp3',
        libraryUrl: 'https://example.com/music/library.json',
      ),
      'a / b',
    );
  });

  test('reads library.json titles and absolute urls', () {
    const body = '''
    {
      "tracks": [
        {"file": "晚风.mp3", "title": "晚风", "artist": "橙子"},
        {"url": "https://cdn.example.com/song.mp3", "title": "远方", "artist": "海"},
        "album/demo.flac"
      ]
    }
    ''';

    final tracks = tracksFromNodes(
      parseCatalogDocument(
        body,
        Uri.parse('https://example.com/music/library.json'),
      ),
    );

    expect(tracks.map((track) => track.title), ['晚风', '远方', 'demo']);
    expect(tracks[0].artist, '橙子');
    expect(tracks[0].path, 'https://example.com/music/%E6%99%9A%E9%A3%8E.mp3');
    expect(tracks[1].path, 'https://cdn.example.com/song.mp3');
    expect(tracks[2].artist, '在线曲库');
    expect(tracks[2].path, 'https://example.com/music/album/demo.flac');
  });

  test('splits artist and title from a file name', () {
    final tracks = tracksFromNodes(
      parseCatalogDocument(
        '["橙子 - 晚风.mp3"]',
        Uri.parse('https://example.com/music/'),
      ),
    );

    expect(tracks.single.title, '晚风');
    expect(tracks.single.artist, '橙子');
  });

  test('parses an nginx json index', () {
    const body = '''
    [
      {"name": "../", "type": "directory"},
      {"name": "album/", "type": "directory", "mtime": "2026-01-01"},
      {"name": "root.mp3", "type": "file", "size": 10},
      {"name": "cover.jpg", "type": "file", "size": 10}
    ]
    ''';

    final nodes = parseCatalogDocument(
      body,
      Uri.parse('https://example.com/music/'),
    );

    expect(
      nodes.where((node) => node.isDirectory).map((node) => node.uri.path),
      ['/music/album/'],
    );
    expect(nodes.where((node) => node.isAudio).map((node) => node.uri.path), [
      '/music/root.mp3',
    ]);
  });

  test('parses an html index and ignores sort links', () {
    const body = '''
    <html><body>
      <a href="?C=N;O=D">Name</a>
      <a href="../">parent</a>
      <a href="album/">album</a>
      <a href="late%20night.mp3">late night</a>
      <a href="https://evil.example/steal.mp3">nope</a>
      <a href="notes.txt">notes</a>
    </body></html>
    ''';

    final nodes = parseCatalogDocument(
      body,
      Uri.parse('https://example.com/music/'),
    );
    final audio = nodes.where((node) => node.isAudio).toList();

    expect(audio.map((node) => node.uri.toString()), [
      'https://example.com/music/late%20night.mp3',
      'https://evil.example/steal.mp3',
    ]);
    expect(titleFromUri(audio.first.uri), 'late night');
    expect(
      nodes.where((node) => node.isDirectory).single.uri.toString(),
      'https://example.com/music/album/',
    );
  });

  test('prefers library.json over a directory listing', () async {
    final source = _FakeSource({
      'https://example.com/music/library.json': const OnlineDocument(
        statusCode: 200,
        body: '{"tracks":[{"file":"from-manifest.mp3","title":"清单"}]}',
      ),
      'https://example.com/music/': const OnlineDocument(
        statusCode: 200,
        body: '<a href="from-folder.mp3">folder</a>',
      ),
    });

    final result = await OnlineMusicLibrary(
      source: source,
    ).load('https://example.com/music/');

    expect(result.sourceLabel, 'library.json');
    expect(result.tracks.single.title, '清单');
    expect(source.requested, ['https://example.com/music/library.json']);
  });

  test('crawls subdirectories when library.json is missing', () async {
    final source = _FakeSource({
      'https://example.com/music/library.json': const OnlineDocument(
        statusCode: 404,
        body: '',
      ),
      'https://example.com/music/': const OnlineDocument(
        statusCode: 200,
        body: '''
        <a href="../">parent</a>
        <a href="root.mp3">root</a>
        <a href="album/">album</a>
        <a href="https://evil.example/outside.mp3">outside</a>
        <a href=".secret/hidden.mp3">hidden</a>
        ''',
      ),
      'https://example.com/music/album/': const OnlineDocument(
        statusCode: 200,
        body: '<a href="橙子%20-%20晚风.mp3">song</a>',
      ),
      'https://example.com/music/.secret/': const OnlineDocument(
        statusCode: 200,
        body: '<a href="hidden.mp3">hidden</a>',
      ),
    });

    final result = await OnlineMusicLibrary(
      source: source,
    ).load('https://example.com/music');

    expect(result.sourceLabel, '目录列表');
    expect(result.tracks.map((track) => track.title), ['root', '晚风']);
    expect(result.tracks.map((track) => track.artist), ['在线曲库', '橙子']);
    expect(
      source.requested.contains('https://example.com/music/.secret/'),
      isFalse,
    );
  });

  test('keeps a directory token on playback urls', () async {
    final source = _FakeSource({
      'https://example.com/music/library.json?token=abc': const OnlineDocument(
        statusCode: 404,
        body: '',
      ),
      'https://example.com/music/?token=abc': const OnlineDocument(
        statusCode: 200,
        body: '<a href="a.mp3">a</a>',
      ),
    });

    final result = await OnlineMusicLibrary(
      source: source,
    ).load('https://example.com/music/?token=abc');

    expect(
      result.tracks.single.path,
      'https://example.com/music/a.mp3?token=abc',
    );
  });

  test('reports invalid manifest json', () async {
    final source = _FakeSource({
      'https://example.com/music/library.json': const OnlineDocument(
        statusCode: 200,
        body: '{"tracks":',
      ),
    });

    await expectLater(
      OnlineMusicLibrary(source: source).load('https://example.com/music/'),
      throwsA(
        isA<OnlineLibraryException>().having(
          (error) => error.message,
          'message',
          contains('JSON'),
        ),
      ),
    );
  });
}

class _FakeSource implements OnlineDocumentSource {
  _FakeSource(this.pages);

  final Map<String, OnlineDocument> pages;
  final List<String> requested = [];

  @override
  Future<OnlineDocument> get(Uri uri) async {
    requested.add(uri.toString());
    return pages[uri.toString()] ??
        const OnlineDocument(statusCode: 404, body: 'missing');
  }

  @override
  Future<void> close() async {}
}
