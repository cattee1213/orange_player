import 'package:flutter/material.dart';

import '../media_library/local_music_library_page.dart';
import '../online_library/online_music_library_page.dart';
import 'models/local_track.dart';
import 'player_controller.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, required this.controller});
  final PlayerController controller;
  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  PlayerController get controller => widget.controller;

  Future<void> _openLibrary() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LocalMusicLibraryPage(playerController: controller),
      ),
    );
  }

  Future<void> _openOnlineLibrary() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OnlineMusicLibraryPage(playerController: controller),
      ),
    );
  }

  Future<void> _importTracks() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final count = await controller.pickAndAddTracks();
      if (!mounted || count == 0) return;
      messenger.showSnackBar(SnackBar(content: Text('已导入 $count 首音乐')));
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('导入失败：$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          return Stack(
            children: [
              const _DynamicBackground(),
              SafeArea(
                child: Column(
                  children: [
                    _PlayerHeader(
                      onImport: _importTracks,
                      onOpenLibrary: _openLibrary,
                      onOpenOnline: _openOnlineLibrary,
                    ),
                    const SizedBox(height: 12),
                    _NowPlayingCard(
                      controller: controller,
                      onImport: _importTracks,
                      onOpenOnline: _openOnlineLibrary,
                    ),
                    const SizedBox(height: 24),
                    Expanded(child: _PlaylistSection(controller: controller)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PlayerHeader extends StatelessWidget {
  final VoidCallback onImport;
  final VoidCallback onOpenLibrary;
  final VoidCallback onOpenOnline;
  const _PlayerHeader({
    required this.onImport,
    required this.onOpenLibrary,
    required this.onOpenOnline,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Row(
              children: [
                Icon(
                  Icons.music_note_rounded,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Orange Player',
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              IconButton.filledTonal(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.library_music_rounded),
                onPressed: onOpenLibrary,
                tooltip: '本地曲库',
              ),
              IconButton.filledTonal(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.cloud_rounded),
                onPressed: onOpenOnline,
                tooltip: '在线曲库',
              ),
              IconButton.filledTonal(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.add_rounded),
                onPressed: onImport,
                tooltip: '导入音乐',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NowPlayingCard extends StatelessWidget {
  final PlayerController controller;
  final VoidCallback onImport;
  final VoidCallback onOpenOnline;
  const _NowPlayingCard({
    required this.controller,
    required this.onImport,
    required this.onOpenOnline,
  });

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (duration.inHours > 0) {
      final hours = duration.inHours.toString().padLeft(2, '0');
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final track = controller.currentTrack;

    if (track == null) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.2),
          ),
        ),
        child: Center(
          child: Column(
            children: [
              Icon(
                Icons.headphones_rounded,
                size: 48,
                color: scheme.primary.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 16),
              Text('享受纯粹音乐', style: theme.textTheme.titleMedium),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onImport,
                icon: const Icon(Icons.folder_open_rounded),
                label: const Text('导入本地音频'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onOpenOnline,
                icon: const Icon(Icons.cloud_rounded),
                label: const Text('打开在线曲库'),
              ),
            ],
          ),
        ),
      );
    }

    final total = controller.duration.inMilliseconds <= 0
        ? 1.0
        : controller.duration.inMilliseconds.toDouble();
    final progress = (controller.position.inMilliseconds / total).clamp(
      0.0,
      1.0,
    );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    colors: [scheme.primaryContainer, scheme.tertiaryContainer],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Icon(
                  Icons.music_note_rounded,
                  size: 32,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      track.artist,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(switch (controller.playbackMode) {
                  PlaybackMode.loopAll => Icons.repeat_rounded,
                  PlaybackMode.shuffle => Icons.shuffle_rounded,
                  PlaybackMode.repeatOne => Icons.repeat_one_rounded,
                }, color: scheme.primary),
                onPressed: controller.cyclePlaybackMode,
              ),
            ],
          ),
          if (controller.activityMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              controller.activityMessage!,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.primary),
            ),
          ],
          if (controller.playbackError != null) ...[
            const SizedBox(height: 12),
            Text(
              controller.playbackError!,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
            ),
          ],
          const SizedBox(height: 16),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              activeTrackColor: scheme.primary,
              inactiveTrackColor: scheme.primary.withValues(alpha: 0.1),
              thumbColor: scheme.onPrimary,
              overlayColor: scheme.primary.withValues(alpha: 0.1),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: progress,
              onChanged: (val) {
                final ms = (controller.duration.inMilliseconds * val).round();
                controller.seek(Duration(milliseconds: ms));
              },
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(controller.position),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              Text(
                _formatDuration(controller.duration),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                iconSize: 32,
                icon: const Icon(Icons.skip_previous_rounded),
                onPressed: controller.canSkipPrevious
                    ? controller.skipPrevious
                    : null,
              ),
              Container(
                height: 64,
                width: 64,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: IconButton(
                  iconSize: 32,
                  color: scheme.onPrimary,
                  icon: Icon(
                    controller.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                  ),
                  onPressed: controller.togglePlayback,
                ),
              ),
              IconButton(
                iconSize: 32,
                icon: const Icon(Icons.skip_next_rounded),
                onPressed: controller.canSkipNext ? controller.skipNext : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PlaylistSection extends StatelessWidget {
  final PlayerController controller;
  const _PlaylistSection({required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow.withValues(alpha: 0.6),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '播放列表',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '${controller.tracks.length} 首',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: !controller.hasTracks
                ? Center(
                    child: Text(
                      '暂无音乐',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ReorderableListView.builder(
                    padding: const EdgeInsets.only(bottom: 32),
                    physics: const BouncingScrollPhysics(),
                    buildDefaultDragHandles: false,
                    itemCount: controller.tracks.length,
                    onReorder: controller.reorderTracks,
                    proxyDecorator: (child, index, animation) =>
                        Material(color: Colors.transparent, child: child),
                    itemBuilder: (context, index) {
                      final track = controller.tracks[index];
                      final isCurrent = track.id == controller.currentTrack?.id;
                      return _TrackTile(
                        key: ValueKey(track.id),
                        track: track,
                        index: index,
                        isCurrent: isCurrent,
                        isPlaying: isCurrent && controller.isPlaying,
                        isCached: controller.isFileBacked(track.id),
                        onTap: () => controller.playTrack(index),
                        onRemove: () => controller.removeTrackAt(index),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

String _trackSubtitle(LocalTrack track, {required bool cached}) {
  if (!track.isRemote) {
    return track.artist;
  }
  final state = cached ? '已缓存' : '在线';
  if (track.artist == '在线曲库') {
    return state;
  }
  return '${track.artist} · $state';
}

class _TrackTile extends StatelessWidget {
  final LocalTrack track;
  final int index;
  final bool isCurrent;
  final bool isPlaying;
  final bool isCached;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _TrackTile({
    super.key,
    required this.track,
    required this.index,
    required this.isCurrent,
    required this.isPlaying,
    required this.isCached,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isCurrent
            ? scheme.primaryContainer.withValues(alpha: 0.3)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        border: isCurrent
            ? Border.all(color: scheme.primary.withValues(alpha: 0.2))
            : null,
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        onTap: onTap,
        leading: SizedBox(
          width: 40,
          child: Center(
            child: isCurrent
                ? Icon(Icons.bar_chart_rounded, color: scheme.primary)
                : Text(
                    '${index + 1}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
        title: Text(
          track.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
            color: isCurrent ? scheme.primary : null,
          ),
        ),
        subtitle: Text(
          _trackSubtitle(track, cached: isCached),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 20),
              color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
              onPressed: onRemove,
            ),
            ReorderableDragStartListener(
              index: index,
              child: Icon(
                Icons.drag_handle_rounded,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DynamicBackground extends StatelessWidget {
  const _DynamicBackground();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: -100,
            left: -50,
            child: _Glow(
              size: 300,
              color: isDark ? const Color(0x1A808080) : const Color(0x30FFB347),
            ),
          ),
          Positioned(
            bottom: -50,
            right: -100,
            child: _Glow(
              size: 250,
              color: isDark ? const Color(0x1A404040) : const Color(0x20FF8C00),
            ),
          ),
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
      ),
    );
  }
}
