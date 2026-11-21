import 'package:flutter/material.dart';

import '../player/models/local_track.dart';
import '../player/player_controller.dart';
import 'online_catalog.dart';
import 'online_library_cache.dart';
import 'online_music_library.dart';

class OnlineMusicLibraryPage extends StatefulWidget {
  const OnlineMusicLibraryPage({super.key, required this.playerController});

  final PlayerController playerController;

  @override
  State<OnlineMusicLibraryPage> createState() => _OnlineMusicLibraryPageState();
}

class _OnlineMusicLibraryPageState extends State<OnlineMusicLibraryPage> {
  final _searchController = TextEditingController();
  final _cache = OnlineLibraryCache.instance;
  List<LocalTrack> _tracks = const [];
  Set<String> _cachedUrls = const {};
  String? _sourceLabel;
  bool _truncated = false;
  bool _loading = true;
  bool _caching = false;
  bool _cancelCache = false;
  String? _cacheProgress;
  String? _error;
  String? _loadedUrl;
  DateTime? _fetchedAt;
  int _audioBytes = 0;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    final url = normalizeLibraryUrl(fixedOnlineLibraryUrl).toString();
    final snapshot = await _cache.readCatalog();
    if (!mounted) {
      return;
    }
    if (snapshot != null && snapshot.url == url) {
      setState(() {
        _loadedUrl = snapshot.url;
        _tracks = snapshot.tracks;
        _sourceLabel = snapshot.sourceLabel;
        _truncated = snapshot.truncated;
        _fetchedAt = snapshot.fetchedAt;
        _loading = false;
      });
      await _refreshCacheStats();
      return;
    }
    await _load(url);
  }

  Future<void> _refreshLibrary() async {
    await _load(fixedOnlineLibraryUrl);
  }

  Future<void> _load(String rawUrl) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final normalized = normalizeLibraryUrl(rawUrl);
      final result = await OnlineMusicLibrary().load(normalized.toString());
      final fetchedAt = DateTime.now();
      await _cache.writeCatalog(
        OnlineLibrarySnapshot(
          url: normalized.toString(),
          sourceLabel: result.sourceLabel,
          truncated: result.truncated,
          fetchedAt: fetchedAt,
          tracks: result.tracks,
        ),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _loadedUrl = normalized.toString();
        _tracks = result.tracks;
        _sourceLabel = result.sourceLabel;
        _truncated = result.truncated;
        _fetchedAt = fetchedAt;
        _error = null;
        _loading = false;
      });
      await _refreshCacheStats();
    } on OnlineLibraryException catch (error) {
      _showLoadError(error.message);
    } catch (error) {
      _showLoadError('读取曲库失败：$error');
    }
  }

  void _showLoadError(String message) {
    if (!mounted) {
      return;
    }
    if (_tracks.isNotEmpty) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      return;
    }
    setState(() {
      _error = message;
      _loading = false;
    });
  }

  Future<void> _refreshCacheStats() async {
    final urls = await _cache.cachedUrls(_tracks.map((track) => track.path));
    final bytes = await _cache.audioBytes();
    if (!mounted) {
      return;
    }
    setState(() {
      _cachedUrls = urls;
      _audioBytes = bytes;
    });
  }

  Future<void> _cacheVisible(List<LocalTrack> tracks) async {
    final pending = [
      for (final track in tracks)
        if (!_cachedUrls.contains(track.path)) track,
    ];
    if (_caching || pending.isEmpty) {
      return;
    }
    _cancelCache = false;
    setState(() {
      _caching = true;
      _cacheProgress = '正在缓存 0/${pending.length}';
    });
    var finished = 0;
    var failed = 0;
    var cancelled = false;
    for (final track in pending) {
      if (!mounted || _cancelCache) {
        cancelled = _cancelCache;
        break;
      }
      try {
        await _cache.downloadAudio(
          track.path,
          isCancelled: () => _cancelCache,
          onProgress: (received, total) {
            if (!mounted) {
              return;
            }
            final percent = total != null && total > 0
                ? ' ${received * 100 ~/ total}%'
                : '';
            final text = '正在缓存 $finished/${pending.length}$percent';
            if (text == _cacheProgress) {
              return;
            }
            setState(() => _cacheProgress = text);
          },
        );
      } on DownloadCancelled {
        cancelled = true;
        break;
      } catch (_) {
        failed += 1;
      }
      finished += 1;
    }
    await _refreshCacheStats();
    if (!mounted) {
      return;
    }
    setState(() {
      _caching = false;
      _cacheProgress = null;
      _cancelCache = false;
    });
    final message = cancelled
        ? '已停止缓存'
        : failed == 0
        ? '音频已保存在本地'
        : '$failed 首音频缓存失败';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _cacheOne(LocalTrack track) async {
    if (_caching || _cachedUrls.contains(track.path)) {
      return;
    }
    await _cacheVisible([track]);
  }

  void _stopCache() {
    if (!_caching) {
      return;
    }
    setState(() {
      _cancelCache = true;
      _cacheProgress = '正在停止';
    });
  }

  Future<void> _clearLibraryCache() async {
    final audio = _audioBytes > 0
        ? '已下载音频 ${formatByteSize(_audioBytes)}'
        : '已下载音频';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除在线曲库缓存？'),
        content: Text('将删除$audio和已保存的曲目列表，然后重新读取服务器。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    _cancelCache = true;
    await _cache.clear();
    try {
      await widget.playerController.releaseCachedAudio();
    } catch (_) {}
    if (!mounted) {
      return;
    }
    setState(() {
      _tracks = const [];
      _cachedUrls = const {};
      _audioBytes = 0;
      _sourceLabel = null;
      _loadedUrl = null;
      _truncated = false;
      _fetchedAt = null;
      _error = null;
      _caching = false;
      _cancelCache = false;
      _cacheProgress = null;
    });
    await _refreshLibrary();
    if (!mounted || _error != null) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已清除在线曲库缓存')));
  }

  Future<void> _play(LocalTrack track) async {
    try {
      await widget.playerController.addTrack(track);
      if (!mounted) {
        return;
      }
      final index = widget.playerController.tracks.indexWhere(
        (item) => item.id == track.id,
      );
      if (index != -1) {
        await widget.playerController.playTrack(index);
      }
      if (mounted) {
        setState(() {});
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('播放失败：$error')));
    }
  }

  Future<void> _addVisible(List<LocalTrack> tracks) async {
    final existing = widget.playerController.tracks
        .map((track) => track.id)
        .toSet();
    final additions = tracks.where((track) => !existing.contains(track.id));
    await widget.playerController.addTracks(tracks);
    if (!mounted) {
      return;
    }
    setState(() {});
    final count = additions.length;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(count == 0 ? '这些曲目已经在播放列表里' : '已加入 $count 首到播放列表')),
    );
  }

  List<LocalTrack> get _filteredTracks {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return _tracks;
    }
    return _tracks.where((track) {
      final folder = libraryFolderLabel(track.path, libraryUrl: _loadedUrl);
      final haystack = '${track.title} ${track.artist} $folder'.toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  void _showGuide() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('准备在线曲库'),
        content: const SingleChildScrollView(child: _SetupGuide()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tracks = _filteredTracks;
    final query = _searchController.text.trim();
    final pendingCount = tracks
        .where((track) => !_cachedUrls.contains(track.path))
        .length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('在线曲库'),
        actions: [
          if (_loadedUrl != null || _audioBytes > 0)
            IconButton(
              tooltip: '清除曲库缓存',
              onPressed: _loading || _caching ? null : _clearLibraryCache,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          IconButton(
            tooltip: '如何准备服务器',
            onPressed: _showGuide,
            icon: const Icon(Icons.help_outline_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshLibrary,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      fixedOnlineLibraryUrl,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _loading ? null : _refreshLibrary,
                      icon: _loading
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.cloud_download_rounded),
                      label: Text(_loading ? '正在读取' : '刷新曲库'),
                    ),
                  ),
                ],
              ),
            ),
            if (_sourceLabel != null && _error == null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: _LibrarySummary(
                  trackCount: _tracks.length,
                  sourceLabel: _sourceLabel!,
                  truncated: _truncated,
                  fetchedAt: _fetchedAt,
                  cachedCount: _cachedUrls.length,
                  audioBytes: _audioBytes,
                  cacheProgress: _cacheProgress,
                  onAddAll: tracks.isEmpty ? null : () => _addVisible(tracks),
                  addLabel: query.isEmpty ? '全部加入' : '加入搜索结果',
                  onCacheAudio: pendingCount == 0 || _caching
                      ? null
                      : () => _cacheVisible(tracks),
                  onStopCache: _caching ? _stopCache : null,
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: '搜索标题、歌手或目录',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '清除搜索',
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                  filled: true,
                  fillColor: scheme.surfaceContainerHighest.withValues(
                    alpha: 0.55,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Expanded(child: _buildBody(tracks, query)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(List<LocalTrack> tracks, String query) {
    if (_loading && _tracks.isEmpty && _error == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        children: [
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          const _SetupGuide(),
        ],
      );
    }
    if (_loadedUrl == null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        children: const [
          Text('正在连接固定曲库。', textAlign: TextAlign.center),
          SizedBox(height: 16),
          _SetupGuide(),
        ],
      );
    }
    if (tracks.isEmpty) {
      if (query.isNotEmpty) {
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          children: [
            Text('没有找到「$query」', textAlign: TextAlign.center),
          ],
        );
      }
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        children: const [
          Text('这个地址下没有可播放的音频。', textAlign: TextAlign.center),
          SizedBox(height: 16),
          _SetupGuide(),
        ],
      );
    }

    final entries = _libraryEntries(tracks, libraryUrl: _loadedUrl);
    final scheme = Theme.of(context).colorScheme;
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final header = entry.header;
        if (header != null) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(8, 14, 8, 6),
            child: Text(
              header,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          );
        }
        final track = entry.track!;
        final cached = _cachedUrls.contains(track.path);
        final inPlaylist = widget.playerController.tracks.any(
          (item) => item.id == track.id,
        );
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            tileColor: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
            leading: CircleAvatar(
              backgroundColor: scheme.primaryContainer,
              foregroundColor: scheme.onPrimaryContainer,
              child: Icon(
                cached ? Icons.download_done_rounded : Icons.cloud_rounded,
              ),
            ),
            title: Text(
              track.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              _onlineSubtitle(
                track,
                cached: cached,
                inPlaylist: inPlaylist,
                showFolder: entries.length == tracks.length,
                libraryUrl: _loadedUrl,
              ),
            ),
            onTap: () => _play(track),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!cached)
                  IconButton(
                    tooltip: '缓存这首',
                    onPressed: _caching ? null : () => _cacheOne(track),
                    icon: const Icon(Icons.download_rounded),
                  ),
                IconButton(
                  tooltip: inPlaylist ? '已加入播放列表' : '加入播放列表',
                  onPressed: inPlaylist
                      ? null
                      : () async {
                          await widget.playerController.addTrack(track);
                          if (mounted) {
                            setState(() {});
                          }
                        },
                  icon: const Icon(Icons.playlist_add_rounded),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LibraryEntry {
  const _LibraryEntry.header(this.header) : track = null;
  const _LibraryEntry.track(this.track) : header = null;

  final String? header;
  final LocalTrack? track;
}

List<_LibraryEntry> _libraryEntries(
  List<LocalTrack> tracks, {
  String? libraryUrl,
}) {
  final grouped = <String, List<LocalTrack>>{};
  for (final track in tracks) {
    grouped
        .putIfAbsent(
          libraryFolderLabel(track.path, libraryUrl: libraryUrl),
          () => [],
        )
        .add(track);
  }
  if (grouped.length < 2) {
    return [for (final track in tracks) _LibraryEntry.track(track)];
  }
  final names = grouped.keys.toList()
    ..sort((first, second) {
      if (first == '根目录') {
        return -1;
      }
      if (second == '根目录') {
        return 1;
      }
      return first.compareTo(second);
    });
  final entries = <_LibraryEntry>[];
  for (final name in names) {
    final folderTracks = grouped[name]!;
    entries.add(_LibraryEntry.header('$name · ${folderTracks.length}'));
    entries.addAll(folderTracks.map(_LibraryEntry.track));
  }
  return entries;
}

String _onlineSubtitle(
  LocalTrack track, {
  required bool cached,
  required bool inPlaylist,
  required bool showFolder,
  String? libraryUrl,
}) {
  final folder = libraryFolderLabel(track.path, libraryUrl: libraryUrl);
  final parts = <String>[
    track.artist,
    if (showFolder && folder != '根目录') folder,
    if (cached) '已缓存',
    if (inPlaylist) '已在播放列表',
  ];
  return parts.join(' · ');
}

class _LibrarySummary extends StatelessWidget {
  const _LibrarySummary({
    required this.trackCount,
    required this.sourceLabel,
    required this.truncated,
    required this.fetchedAt,
    required this.cachedCount,
    required this.audioBytes,
    required this.cacheProgress,
    required this.onAddAll,
    required this.addLabel,
    required this.onCacheAudio,
    required this.onStopCache,
  });

  final int trackCount;
  final String sourceLabel;
  final bool truncated;
  final DateTime? fetchedAt;
  final int cachedCount;
  final int audioBytes;
  final String? cacheProgress;
  final VoidCallback? onAddAll;
  final String addLabel;
  final VoidCallback? onCacheAudio;
  final VoidCallback? onStopCache;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final detail = StringBuffer('$trackCount 首 · $sourceLabel');
    if (fetchedAt != null) {
      detail.write('\n更新于 ${_formatTime(fetchedAt!)}');
    }
    detail.write('\n音频缓存 $cachedCount 首');
    if (audioBytes > 0) {
      detail.write(' · ${formatByteSize(audioBytes)}');
    }
    if (cacheProgress != null) {
      detail.write('\n$cacheProgress');
    }
    if (truncated) {
      detail.write('\n还有更多目录没有继续读取');
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.cloud_done_rounded, color: scheme.onPrimaryContainer),
              const SizedBox(width: 12),
              Expanded(child: Text(detail.toString())),
            ],
          ),
          Wrap(
            spacing: 4,
            children: [
              if (onAddAll != null)
                TextButton(onPressed: onAddAll, child: Text(addLabel)),
              if (onCacheAudio != null)
                TextButton(onPressed: onCacheAudio, child: const Text('缓存音频')),
              if (onStopCache != null)
                TextButton(onPressed: onStopCache, child: const Text('停止')),
            ],
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final local = time.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$month-$day $hour:$minute';
  }
}

class _SetupGuide extends StatelessWidget {
  const _SetupGuide();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.bodyMedium;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('曲库地址已固定为：', style: style),
        const SizedBox(height: 8),
        const SelectableText(fixedOnlineLibraryUrl),
        const SizedBox(height: 16),
        Text('方式 A：在该目录放置 library.json', style: style),
        const SizedBox(height: 8),
        DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Padding(
            padding: EdgeInsets.all(12),
            child: SelectableText(
              '{\n'
              '  "tracks": [\n'
              '    {"file": "晚风.mp3", "title": "晚风", "artist": "橙子"}\n'
              '  ]\n'
              '}',
              style: TextStyle(fontFamily: 'monospace', height: 1.4),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text('file 写成相对路径，也可以写成完整的 https 链接。', style: style),
        const SizedBox(height: 16),
        Text('方式 B：只上传音频，并打开目录浏览。Nginx 示例：', style: style),
        const SizedBox(height: 8),
        DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Padding(
            padding: EdgeInsets.all(12),
            child: SelectableText(
              'location /music/ {\n'
              '    autoindex on;\n'
              '}',
              style: TextStyle(fontFamily: 'monospace', height: 1.4),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '也支持 Nginx 的 autoindex_format json，以及 Caddy、Apache 的目录列表。子目录会一并读取。可识别 mp3、flac、wav、m4a、aac、ogg、opus。曲目列表会留在手机里，再次打开时直接显示。播放过或手动缓存的音频也会保存在本地。',
          style: style,
        ),
      ],
    );
  }
}
