import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../player/models/local_track.dart';
import 'online_catalog.dart';

class OnlineDocument {
  const OnlineDocument({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}

abstract class OnlineDocumentSource {
  Future<OnlineDocument> get(Uri uri);

  Future<void> close() async {}
}

class HttpOnlineDocumentSource implements OnlineDocumentSource {
  HttpOnlineDocumentSource({http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;

  static const _headers = {
    'User-Agent': 'OrangePlayer',
    'Accept': 'application/json, text/html, text/plain, */*',
  };

  @override
  Future<OnlineDocument> get(Uri uri) async {
    try {
      final response = await _client
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 20));
      return OnlineDocument(
        statusCode: response.statusCode,
        body: utf8.decode(response.bodyBytes, allowMalformed: true),
      );
    } on TimeoutException {
      throw const OnlineLibraryException('连接超时，请检查服务器是否可访问');
    } on SocketException catch (error) {
      throw OnlineLibraryException('无法连接服务器：${error.message}');
    } on HandshakeException {
      throw const OnlineLibraryException('SSL 证书校验失败，请确认域名证书有效');
    } on http.ClientException catch (error) {
      throw _clientException(error);
    } on TlsException {
      throw const OnlineLibraryException('SSL 证书校验失败，请确认域名证书有效');
    }
  }

  @override
  Future<void> close() async {
    if (_ownsClient) {
      _client.close();
    }
  }
}

class OnlineMusicLibrary {
  OnlineMusicLibrary({OnlineDocumentSource? source})
    : _source = source ?? HttpOnlineDocumentSource(),
      _closeSource = source == null;

  static const maxDirectoryDepth = 3;
  static const maxRequests = 40;
  static const maxTracks = 2000;

  final OnlineDocumentSource _source;
  final bool _closeSource;

  Future<OnlineLibraryResult> load(String rawUrl) async {
    try {
      final base = normalizeLibraryUrl(rawUrl);
      if (isManifestUrl(base)) {
        final document = await _source.get(base);
        if (document.statusCode != 200) {
          throw OnlineLibraryException(statusMessage(document.statusCode));
        }
        final tracks = tracksFromNodes(
          parseCatalogDocument(document.body, base),
          authBase: base,
        );
        return OnlineLibraryResult(
          tracks: tracks,
          sourceLabel: _manifestLabel(base),
          truncated: false,
        );
      }

      final manifest = await _source.get(
        applyBaseQuery(base, base.resolve('library.json')),
      );
      if (manifest.statusCode == 200 && _looksLikeJson(manifest.body)) {
        final tracks = tracksFromNodes(
          parseCatalogDocument(manifest.body, base.resolve('library.json')),
          authBase: base,
        );
        return OnlineLibraryResult(
          tracks: tracks,
          sourceLabel: 'library.json',
          truncated: false,
        );
      }

      return await _crawl(base);
    } finally {
      if (_closeSource) {
        await _source.close();
      }
    }
  }

  Future<OnlineLibraryResult> _crawl(Uri root) async {
    final directoryTracks = <LocalTrack>[];
    final seenDirectories = <String>{};
    final seenTracks = <String>{};
    final queue = <(Uri, int)>[(asDirectory(root), 0)];
    var requests = 0;
    var truncated = false;

    while (queue.isNotEmpty) {
      if (requests >= maxRequests || directoryTracks.length >= maxTracks) {
        truncated = true;
        break;
      }

      final (directory, depth) = queue.removeAt(0);
      final directoryKey = directory.toString();
      if (!seenDirectories.add(directoryKey)) {
        continue;
      }

      requests++;
      final OnlineDocument document;
      try {
        document = await _source.get(applyBaseQuery(root, directory));
      } on OnlineLibraryException {
        if (depth == 0) {
          rethrow;
        }
        continue;
      }

      if (document.statusCode != 200) {
        if (depth == 0) {
          throw OnlineLibraryException(statusMessage(document.statusCode));
        }
        continue;
      }

      final List<CatalogNode> nodes;
      try {
        nodes = parseCatalogDocument(document.body, directory);
      } on OnlineLibraryException {
        if (depth == 0) {
          rethrow;
        }
        continue;
      }

      for (final node in nodes) {
        if (!isInsideLibrary(root, node.uri) || _isHidden(node.uri)) {
          continue;
        }
        if (node.isDirectory) {
          if (depth >= maxDirectoryDepth) {
            truncated = true;
            continue;
          }
          queue.add((asDirectory(node.uri), depth + 1));
          continue;
        }
        if (!node.isAudio) {
          continue;
        }

        final playable = applyBaseQuery(root, node.uri);
        final url = playable.toString();
        if (!seenTracks.add(url)) {
          continue;
        }
        if (directoryTracks.length >= maxTracks) {
          truncated = true;
          continue;
        }
        directoryTracks.addAll(
          tracksFromNodes([
            CatalogNode(
              uri: playable,
              isDirectory: false,
              title: node.title,
              artist: node.artist,
              listedExplicitly: node.listedExplicitly,
            ),
          ]),
        );
      }
    }

    directoryTracks.sort((first, second) => first.title.compareTo(second.title));
    return OnlineLibraryResult(
      tracks: directoryTracks,
      sourceLabel: '目录列表',
      truncated: truncated,
    );
  }
}

bool _isHidden(Uri uri) {
  try {
    return uri.pathSegments.any(
      (segment) => segment.isNotEmpty && segment.startsWith('.'),
    );
  } on ArgumentError {
    return false;
  }
}

bool _looksLikeJson(String body) {
  final trimmed = body.replaceFirst('\uFEFF', '').trimLeft();
  return trimmed.startsWith('{') || trimmed.startsWith('[');
}

String _manifestLabel(Uri uri) {
  return uri.path.toLowerCase().endsWith('.txt') ? '曲目文本' : 'library.json';
}

String statusMessage(int statusCode) {
  return switch (statusCode) {
    401 => '服务器要求登录（401）。请把曲库目录设为可公开访问',
    403 => '服务器拒绝访问（403），请检查目录权限',
    404 => '找不到这个地址（404），请确认曲库目录是否存在',
    _ => '服务器返回 $statusCode，无法读取曲库',
  };
}

OnlineLibraryException _clientException(http.ClientException error) {
  final text = error.toString();
  if (text.contains('Handshake') || text.contains('Certificate')) {
    return const OnlineLibraryException('SSL 证书校验失败，请确认域名证书有效');
  }
  final message = error.message.trim();
  if (message.isEmpty) {
    return const OnlineLibraryException('无法连接服务器');
  }
  return OnlineLibraryException('无法连接服务器：$message');
}
