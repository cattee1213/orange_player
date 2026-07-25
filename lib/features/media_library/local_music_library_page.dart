import 'package:flutter/material.dart';

import '../player/models/local_track.dart';
import '../player/player_controller.dart';
import 'local_music_library.dart';

class LocalMusicLibraryPage extends StatefulWidget {
  const LocalMusicLibraryPage({super.key, required this.playerController});

  final PlayerController playerController;

  @override
  State<LocalMusicLibraryPage> createState() => _LocalMusicLibraryPageState();
}

class _LocalMusicLibraryPageState extends State<LocalMusicLibraryPage> {
  final _transcodeService = VideoToMp3Service();
  final _searchController = TextEditingController();
  List<LocalTrack> _tracks = const [];
  int _totalBytes = 0;
  bool _loading = true;
  bool _converting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadLibrary();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadLibrary() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<dynamic>([
        LocalMusicLibrary.loadTracks(),
        LocalMusicLibrary.totalBytes(),
      ]);
      if (!mounted) {
        return;
      }
      setState(() {
        _tracks = results[0] as List<LocalTrack>;
        _totalBytes = results[1] as int;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  Future<void> _convertVideo() async {
    final video = await _transcodeService.pickVideo();
    if (video == null || !mounted) {
      return;
    }
    setState(() => _converting = true);
    try {
      final track = await _transcodeService.convert(video);
      await widget.playerController.addTrack(track);
      await _loadLibrary();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已生成 MP3 并加入播放列表：${track.title}')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) {
        setState(() => _converting = false);
      }
    }
  }

  Future<void> _deleteTrack(LocalTrack track) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除 MP3？'),
        content: Text('将删除“${track.title}”生成的 MP3 文件。原始视频不会被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除 MP3'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      await LocalMusicLibrary.deleteTrack(track);
      final index = widget.playerController.tracks.indexWhere(
        (item) => item.id == track.id,
      );
      if (index != -1) {
        await widget.playerController.removeTrackAt(index);
      }
      await _loadLibrary();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('删除失败：$error')));
    }
  }

  List<LocalTrack> get _filteredTracks {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return _tracks;
    }
    return _tracks
        .where(
          (track) =>
              '${track.title} ${track.artist}'.toLowerCase().contains(query),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tracks = _filteredTracks;
    return Scaffold(
      appBar: AppBar(title: const Text('本地曲库')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _converting ? null : _convertVideo,
        icon: _converting
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.video_file_rounded),
        label: Text(_converting ? '正在转码' : '从视频导入'),
      ),
      body: RefreshIndicator(
        onRefresh: _loadLibrary,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: _StorageSummary(
                trackCount: _tracks.length,
                totalBytes: _totalBytes,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: '搜索已生成的 MP3',
                  prefixIcon: const Icon(Icons.search_rounded),
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
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? _ErrorState(error: _error!, onRetry: _loadLibrary)
                  : tracks.isEmpty
                  ? const _EmptyState()
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                      itemCount: tracks.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final track = tracks[index];
                        final inPlaylist = widget.playerController.tracks.any(
                          (item) => item.id == track.id,
                        );
                        return ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          tileColor: scheme.surfaceContainerHighest.withValues(
                            alpha: 0.35,
                          ),
                          leading: CircleAvatar(
                            backgroundColor: scheme.primaryContainer,
                            foregroundColor: scheme.onPrimaryContainer,
                            child: const Icon(Icons.music_note_rounded),
                          ),
                          title: Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(inPlaylist ? '已在播放列表' : '视频转码音轨'),
                          onTap: () async {
                            await widget.playerController.addTrack(track);
                            if (!mounted) {
                              return;
                            }
                            final playerIndex = widget.playerController.tracks
                                .indexWhere((item) => item.id == track.id);
                            await widget.playerController.playTrack(
                              playerIndex,
                            );
                          },
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: inPlaylist ? '已加入播放列表' : '加入播放列表',
                                onPressed: inPlaylist
                                    ? null
                                    : () => widget.playerController.addTrack(
                                        track,
                                      ),
                                icon: const Icon(Icons.playlist_add_rounded),
                              ),
                              IconButton(
                                tooltip: '删除 MP3',
                                onPressed: () => _deleteTrack(track),
                                icon: const Icon(Icons.delete_outline_rounded),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StorageSummary extends StatelessWidget {
  const _StorageSummary({required this.trackCount, required this.totalBytes});

  final int trackCount;
  final int totalBytes;

  String get _formattedSize {
    if (totalBytes < 1024 * 1024) {
      return '${(totalBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Icon(Icons.folder_copy_rounded, color: scheme.onPrimaryContainer),
          const SizedBox(width: 12),
          Expanded(child: Text('$trackCount 首已生成曲目\n占用 $_formattedSize')),
          Text('仅 MP3', style: TextStyle(color: scheme.onPrimaryContainer)),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(36),
      child: Text('还没有由视频转出的 MP3。\n点击右下角从手机视频导入。', textAlign: TextAlign.center),
    ),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('无法读取本地曲库：$error', textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    ),
  );
}
