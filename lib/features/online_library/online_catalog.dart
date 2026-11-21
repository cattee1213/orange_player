import 'dart:convert';

import '../player/models/local_track.dart';

const fixedOnlineLibraryUrl = 'https://bigorange.site/vicky-english/';

const audioExtensions = {
  '.mp3',
  '.m4a',
  '.aac',
  '.flac',
  '.wav',
  '.ogg',
  '.opus',
  '.wma',
};

class OnlineLibraryException implements Exception {
  const OnlineLibraryException(this.message);

  final String message;

  @override
  String toString() => message;
}

class CatalogNode {
  const CatalogNode({
    required this.uri,
    required this.isDirectory,
    this.title,
    this.artist,
    this.listedExplicitly = false,
  });

  final Uri uri;
  final bool isDirectory;
  final String? title;
  final String? artist;
  final bool listedExplicitly;

  bool get isAudio {
    if (isDirectory) {
      return false;
    }
    final extension = audioExtensionOf(uri);
    if (extension == null) {
      return listedExplicitly;
    }
    return audioExtensions.contains(extension);
  }
}

class OnlineLibraryResult {
  const OnlineLibraryResult({
    required this.tracks,
    required this.sourceLabel,
    required this.truncated,
  });

  final List<LocalTrack> tracks;
  final String sourceLabel;
  final bool truncated;
}

Uri normalizeLibraryUrl(String raw) {
  var text = raw.trim();
  if (text.isEmpty) {
    throw const OnlineLibraryException('请填写曲库地址');
  }
  if (!text.contains('://')) {
    text = 'https://$text';
  }

  final uri = Uri.tryParse(text);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    throw const OnlineLibraryException('地址格式不正确，例如 https://你的域名/music/');
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    throw const OnlineLibraryException('只支持 http 或 https 地址');
  }
  if (uri.userInfo.isNotEmpty) {
    throw const OnlineLibraryException('请不要在地址中包含账号密码');
  }

  var path = uri.path;
  if (path.isEmpty) {
    path = '/';
  }
  final lowerPath = path.toLowerCase();
  final isManifest = lowerPath.endsWith('.json') || lowerPath.endsWith('.txt');
  if (!isManifest && !path.endsWith('/')) {
    path = '$path/';
  }
  return Uri.parse(uri.replace(path: path).toString().split('#').first);
}

bool isManifestUrl(Uri uri) {
  final path = uri.path.toLowerCase();
  return path.endsWith('.json') || path.endsWith('.txt');
}

String? audioExtensionOf(Uri uri) {
  final segments = _safePathSegments(uri);
  if (segments.isEmpty) {
    return null;
  }
  final name = segments.last.toLowerCase();
  final dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) {
    return null;
  }
  return name.substring(dot);
}

String libraryFolderLabel(String url, {String? libraryUrl}) {
  final uri = Uri.tryParse(url);
  if (uri == null) {
    return '其他';
  }
  final segments = _safePathSegments(uri);
  if (segments.isEmpty) {
    return '根目录';
  }
  final relative = _withoutPrefix(
    segments.sublist(0, segments.length - 1),
    _libraryPrefix(libraryUrl),
  );
  if (relative.isEmpty) {
    return '根目录';
  }
  return relative.join(' / ');
}

List<String> _libraryPrefix(String? libraryUrl) {
  if (libraryUrl == null || libraryUrl.isEmpty) {
    return const [];
  }
  final uri = Uri.tryParse(libraryUrl);
  if (uri == null) {
    return const [];
  }
  final segments = _safePathSegments(uri);
  if (segments.isEmpty) {
    return const [];
  }
  if (isManifestUrl(uri)) {
    return segments.sublist(0, segments.length - 1);
  }
  return segments;
}

List<String> _withoutPrefix(List<String> path, List<String> prefix) {
  if (prefix.isEmpty || path.length < prefix.length) {
    return path;
  }
  for (var index = 0; index < prefix.length; index++) {
    if (path[index] != prefix[index]) {
      return path;
    }
  }
  return path.sublist(prefix.length);
}

String titleFromUri(Uri uri) {
  final segments = _safePathSegments(uri);
  if (segments.isEmpty) {
    return '未命名';
  }
  var name = segments.last.trim();
  final dot = name.lastIndexOf('.');
  if (dot > 0) {
    name = name.substring(0, dot);
  }
  name = name.trim();
  return name.isEmpty ? '未命名' : name;
}

List<CatalogNode> parseCatalogDocument(String rawBody, Uri base) {
  final body = rawBody.replaceFirst('\uFEFF', '').trim();
  if (body.isEmpty) {
    return const [];
  }
  if (body.startsWith('{') || body.startsWith('[')) {
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw const OnlineLibraryException('曲库清单不是有效的 JSON');
    }
    return _parseJson(decoded, base);
  }
  if (_looksLikeHtml(body)) {
    return _parseHtml(body, base);
  }
  return _parseLines(body, base);
}

List<LocalTrack> tracksFromNodes(Iterable<CatalogNode> nodes, {Uri? authBase}) {
  final tracks = <LocalTrack>[];
  final seen = <String>{};
  for (final node in nodes) {
    if (node.isDirectory || !node.isAudio) {
      continue;
    }
    final uri = authBase == null
        ? node.uri
        : applyBaseQuery(authBase, node.uri);
    final url = uri.toString();
    if (!seen.add(url)) {
      continue;
    }
    tracks.add(_trackFromNode(node, uri));
  }
  return tracks;
}

Uri applyBaseQuery(Uri base, Uri target) {
  if (base.query.isEmpty || target.query.isNotEmpty) {
    return target;
  }
  if (target.scheme != base.scheme || target.host != base.host) {
    return target;
  }
  if (_effectivePort(target) != _effectivePort(base)) {
    return target;
  }
  return target.replace(query: base.query);
}

bool isInsideLibrary(Uri root, Uri candidate) {
  if (candidate.scheme != root.scheme || candidate.host != root.host) {
    return false;
  }
  if (_effectivePort(candidate) != _effectivePort(root)) {
    return false;
  }
  final rootPath = root.path.endsWith('/') ? root.path : '${root.path}/';
  final path = candidate.path.isEmpty ? '/' : candidate.path;
  return path.startsWith(rootPath);
}

Uri asDirectory(Uri uri) {
  final withoutQuery = uri.toString().split('#').first.split('?').first;
  if (withoutQuery.endsWith('/')) {
    return Uri.parse(withoutQuery);
  }
  return Uri.parse('$withoutQuery/');
}

List<CatalogNode> _parseJson(Object? decoded, Uri base) {
  if (decoded is List) {
    return _parseNodeList(decoded, base, explicit: !_isNginxIndex(decoded));
  }
  if (decoded is Map) {
    final tracks = decoded['tracks'] ?? decoded['files'] ?? decoded['items'];
    if (tracks is List) {
      return _parseNodeList(tracks, base, explicit: true);
    }
  }
  throw const OnlineLibraryException('曲库清单格式无法识别。请使用 tracks 数组，或开启目录浏览。');
}

bool _isNginxIndex(List<dynamic> items) {
  if (items.isEmpty) {
    return false;
  }
  return items.every(
    (item) =>
        item is Map &&
        item.containsKey('name') &&
        item.containsKey('type') &&
        !item.containsKey('file') &&
        !item.containsKey('url') &&
        !item.containsKey('title'),
  );
}

List<CatalogNode> _parseNodeList(
  List<dynamic> items,
  Uri base, {
  required bool explicit,
}) {
  final nodes = <CatalogNode>[];
  for (final item in items) {
    final node = _parseNode(item, base, explicit: explicit);
    if (node != null) {
      nodes.add(node);
    }
  }
  return nodes;
}

CatalogNode? _parseNode(Object? item, Uri base, {required bool explicit}) {
  if (item is String) {
    return _nodeFromReference(item, base, explicit: true);
  }
  if (item is! Map) {
    return null;
  }

  final type = item['type']?.toString().toLowerCase();
  final explicitReference =
      item['url'] ?? item['file'] ?? item['path'] ?? item['src'];
  final reference = (explicitReference ?? item['name'])?.toString();
  if (reference == null || reference.trim().isEmpty) {
    return null;
  }

  final listedExplicitly = explicit || explicitReference != null;
  final isDirectory = type == 'directory' || reference.trim().endsWith('/');
  if (type == 'file') {
    return _nodeFromReference(
      reference,
      base,
      explicit: listedExplicitly,
      title: item['title']?.toString(),
      artist: item['artist']?.toString(),
      forceFile: true,
    );
  }
  return _nodeFromReference(
    reference,
    base,
    explicit: listedExplicitly,
    title: item['title']?.toString(),
    artist: item['artist']?.toString(),
    forceDirectory: isDirectory,
  );
}

CatalogNode? _nodeFromReference(
  String reference,
  Uri base, {
  required bool explicit,
  String? title,
  String? artist,
  bool forceDirectory = false,
  bool forceFile = false,
}) {
  final cleaned = _decodeHtml(reference.trim());
  if (cleaned.isEmpty || _shouldSkipReference(cleaned)) {
    return null;
  }
  final parsed = Uri.tryParse(cleaned);
  if (parsed != null &&
      parsed.hasScheme &&
      parsed.scheme != 'http' &&
      parsed.scheme != 'https') {
    return null;
  }

  final uri = _resolveReference(base, cleaned);
  final isDirectory = !forceFile && (forceDirectory || cleaned.endsWith('/'));
  if (isDirectory) {
    return CatalogNode(uri: asDirectory(uri), isDirectory: true);
  }

  final node = CatalogNode(
    uri: uri.hasFragment ? Uri.parse(uri.toString().split('#').first) : uri,
    isDirectory: false,
    title: _blankToNull(title),
    artist: _blankToNull(artist),
    listedExplicitly: explicit,
  );
  if (!node.isAudio) {
    return null;
  }
  return node;
}

List<CatalogNode> _parseHtml(String body, Uri requestUri) {
  final base = _htmlBase(body, requestUri);
  final nodes = <CatalogNode>[];
  final pattern = RegExp(
    '''href\\s*=\\s*(['"])(.*?)\\1''',
    caseSensitive: false,
  );
  for (final match in pattern.allMatches(body)) {
    final node = _nodeFromReference(
      match.group(2) ?? '',
      base,
      explicit: false,
    );
    if (node != null) {
      nodes.add(node);
    }
  }
  return nodes;
}

List<CatalogNode> _parseLines(String body, Uri base) {
  final nodes = <CatalogNode>[];
  for (final rawLine in body.split(RegExp(r'\r?\n'))) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) {
      continue;
    }
    final node = _nodeFromReference(line, base, explicit: true);
    if (node != null) {
      nodes.add(node);
    }
  }
  return nodes;
}

Uri _htmlBase(String body, Uri requestUri) {
  final match = RegExp(
    '''<base[^>]*href\\s*=\\s*(['"])(.*?)\\1''',
    caseSensitive: false,
  ).firstMatch(body);
  final href = match?.group(2);
  if (href == null || href.trim().isEmpty) {
    return requestUri;
  }
  return _resolveReference(requestUri, href.trim());
}

Uri _resolveReference(Uri base, String reference) {
  final parsed = Uri.tryParse(reference);
  if (parsed != null && parsed.hasScheme) {
    return parsed;
  }

  final encoded = reference.split('/').map(_encodePathSegment).join('/');
  return base.resolve(encoded);
}

String _encodePathSegment(String segment) {
  if (segment.isEmpty || segment == '.' || segment == '..') {
    return segment;
  }
  // decodeComponent rejects a segment that mixes raw Unicode with %HH.
  final buffer = StringBuffer();
  for (var index = 0; index < segment.length; index++) {
    final codeUnit = segment.codeUnitAt(index);
    if (codeUnit == 0x25 &&
        index + 2 < segment.length &&
        _isHex(segment.codeUnitAt(index + 1)) &&
        _isHex(segment.codeUnitAt(index + 2))) {
      buffer.write(segment.substring(index, index + 3));
      index += 2;
      continue;
    }
    buffer.write(Uri.encodeComponent(segment[index]));
  }
  return buffer.toString();
}

bool _isHex(int codeUnit) {
  return (codeUnit >= 0x30 && codeUnit <= 0x39) ||
      (codeUnit >= 0x41 && codeUnit <= 0x46) ||
      (codeUnit >= 0x61 && codeUnit <= 0x66);
}

bool _shouldSkipReference(String reference) {
  final lower = reference.toLowerCase();
  return reference.startsWith('#') ||
      reference.startsWith('?') ||
      reference.startsWith('//') ||
      lower.startsWith('javascript:') ||
      lower.startsWith('mailto:') ||
      lower.startsWith('data:') ||
      reference == '../' ||
      reference == '..' ||
      reference == './' ||
      reference == '.';
}

bool _looksLikeHtml(String body) {
  final lower = body.toLowerCase();
  return lower.contains('<html') ||
      lower.contains('<a ') ||
      lower.contains('<a\n') ||
      lower.contains('href=');
}

LocalTrack _trackFromNode(CatalogNode node, Uri uri) {
  final fromFile = _splitArtistTitle(titleFromUri(uri));
  final title = node.title ?? fromFile.title;
  final artist = node.artist ?? fromFile.artist ?? '在线曲库';
  return LocalTrack.remote(url: uri.toString(), title: title, artist: artist);
}

({String title, String? artist}) _splitArtistTitle(String fileTitle) {
  final parts = fileTitle.split(' - ');
  if (parts.length >= 2) {
    final artist = parts.first.trim();
    final title = parts.sublist(1).join(' - ').trim();
    if (artist.isNotEmpty && title.isNotEmpty) {
      return (title: title, artist: artist);
    }
  }
  return (title: fileTitle, artist: null);
}

String? _blankToNull(String? value) {
  if (value == null) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

List<String> _safePathSegments(Uri uri) {
  try {
    return uri.pathSegments.where((segment) => segment.isNotEmpty).toList();
  } on ArgumentError {
    return uri.path.split('/').where((segment) => segment.isNotEmpty).map((
      segment,
    ) {
      try {
        return Uri.decodeComponent(segment);
      } on ArgumentError {
        return segment;
      }
    }).toList();
  }
}

int _effectivePort(Uri uri) {
  if (uri.hasPort) {
    return uri.port;
  }
  return uri.scheme == 'https' ? 443 : 80;
}

String _decodeHtml(String value) {
  return value
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');
}
