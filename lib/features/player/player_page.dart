import 'package:flutter/material.dart';

import 'models/local_track.dart';
import 'player_controller.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, required this.controller});

  final PlayerController controller;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  int _tabIndex = 0;

  PlayerController get controller => widget.controller;

  Future<void> _importTracks() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final count = await controller.pickAndAddTracks();
      if (!mounted || count == 0) {
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text('已导入 $count 首本地音乐')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text('导入失败：$error')));
    }
  }

  Future<void> _removeTrack(int index) async {
    final messenger = ScaffoldMessenger.of(context);
    await controller.removeTrackAt(index);
    if (!mounted) {
      return;
    }
    messenger.showSnackBar(const SnackBar(content: Text('已从歌单移除')));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final currentTrack = controller.currentTrack;
        return Scaffold(
          body: Stack(
            children: [
              const _BackdropDecoration(),
              SafeArea(
                child: IndexedStack(
                  index: _tabIndex,
                  children: [
                    _HomeTab(
                      controller: controller,
                      currentTrack: currentTrack,
                      onImport: _importTracks,
                    ),
                    _PlaylistTab(
                      controller: controller,
                      onImport: _importTracks,
                      onRemove: _removeTrack,
                    ),
                  ],
                ),
              ),
            ],
          ),
          bottomNavigationBar: SafeArea(
            minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: NavigationBar(
                selectedIndex: _tabIndex,
                height: 72,
                backgroundColor: Theme.of(context).colorScheme.surface
                    .withValues(
                      alpha: Theme.of(context).brightness == Brightness.dark
                          ? 0.92
                          : 0.9,
                    ),
                indicatorColor: Theme.of(context).colorScheme.primaryContainer,
                onDestinationSelected: (index) {
                  setState(() => _tabIndex = index);
                },
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.home_rounded),
                    label: '首页',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.queue_music_rounded),
                    label: '歌单',
                  ),
                ],
              ),
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _importTracks,
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Theme.of(context).colorScheme.onPrimary,
            icon: const Icon(Icons.library_music_rounded),
            label: const Text('导入音乐'),
          ),
        );
      },
    );
  }
}

class _HomeTab extends StatelessWidget {
  const _HomeTab({
    required this.controller,
    required this.currentTrack,
    required this.onImport,
  });

  final PlayerController controller;
  final LocalTrack? currentTrack;
  final Future<void> Function() onImport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = controller.hasTracks
        ? '${controller.tracks.length} 首音乐已加入播放列表'
        : '导入本地音乐后即可开始播放';
    final total = controller.duration.inMilliseconds <= 0
        ? 1.0
        : controller.duration.inMilliseconds.toDouble();
    final progress = (controller.position.inMilliseconds / total).clamp(
      0.0,
      1.0,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            eyebrow: '首页',
            title: '正在播放',
            subtitle: summary,
            trailing: FilledButton.tonalIcon(
              onPressed: onImport,
              icon: const Icon(Icons.add_circle_outline_rounded),
              label: const Text('导入'),
            ),
          ),
          const SizedBox(height: 20),
          _NowPlayingCard(controller: controller, currentTrack: currentTrack),
          const SizedBox(height: 20),
          _GlassCard(
            child: Column(
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: theme.colorScheme.primary,
                    inactiveTrackColor: const Color(0x22FFFFFF),
                    thumbColor: Colors.white,
                    overlayColor: const Color(0x22FFFFFF),
                  ),
                  child: Slider(
                    value: progress,
                    onChanged: controller.hasTracks
                        ? (value) {
                            final milliseconds =
                                (controller.duration.inMilliseconds * value)
                                    .round();
                            controller.seek(
                              Duration(milliseconds: milliseconds),
                            );
                          }
                        : null,
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDuration(controller.position),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      _formatDuration(controller.duration),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _ModeChip(mode: controller.playbackMode),
                    Text(
                      controller.hasTracks
                          ? '${controller.tracks.length} 首歌曲'
                          : '等待导入音乐',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('下一首', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          if (controller.upcomingTracks.isEmpty)
            _EmptyPrompt(onImport: onImport)
          else
            ...controller.upcomingTracks.map(
              (track) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _QueuePreviewTile(track: track),
              ),
            ),
        ],
      ),
    );
  }
}

class _PlaylistTab extends StatelessWidget {
  const _PlaylistTab({
    required this.controller,
    required this.onImport,
    required this.onRemove,
  });

  final PlayerController controller;
  final Future<void> Function() onImport;
  final Future<void> Function(int index) onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            eyebrow: '播放列表',
            title: '歌曲管理',
            subtitle: controller.hasTracks
                ? '${controller.tracks.length} 首歌曲，可拖拽排序和移除'
                : '当前还没有歌曲',
            trailing: OutlinedButton.icon(
              onPressed: onImport,
              icon: const Icon(Icons.file_open_rounded),
              label: const Text('添加'),
            ),
          ),
          const SizedBox(height: 16),
          _GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Row(
              children: [
                _StatPill(label: '歌曲', value: '${controller.tracks.length}'),
                const SizedBox(width: 12),
                _StatPill(
                  label: '模式',
                  value: switch (controller.playbackMode) {
                    PlaybackMode.loopAll => '顺序循环',
                    PlaybackMode.shuffle => '随机播放',
                    PlaybackMode.repeatOne => '单曲循环',
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (!controller.hasTracks)
            Expanded(child: _EmptyPrompt(onImport: onImport))
          else
            Expanded(
              child: ReorderableListView.builder(
                itemCount: controller.tracks.length,
                buildDefaultDragHandles: false,
                onReorder: controller.reorderTracks,
                itemBuilder: (context, index) {
                  final track = controller.tracks[index];
                  final isCurrent = track.id == controller.currentTrack?.id;
                  return Padding(
                    key: ValueKey(track.id),
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _PlaylistTile(
                      track: track,
                      index: index,
                      isCurrent: isCurrent,
                      isPlaying: isCurrent && controller.isPlaying,
                      onPlay: () => controller.playTrack(index),
                      onRemove: () => onRemove(index),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _NowPlayingCard extends StatelessWidget {
  const _NowPlayingCard({required this.controller, required this.currentTrack});

  final PlayerController controller;
  final LocalTrack? currentTrack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final base = isDark ? const Color(0xFF2A211D) : const Color(0xFFFFF1E6);
    final accent = isDark ? const Color(0xFF5E3A24) : const Color(0xFFF6D0B4);
    final border = isDark ? const Color(0x33FFD2B0) : const Color(0x66FFFFFF);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            base,
            accent,
            scheme.primary.withValues(alpha: isDark ? 0.3 : 0.18),
          ],
        ),
        borderRadius: BorderRadius.circular(36),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: isDark ? 0.18 : 0.1),
            blurRadius: 28,
            offset: Offset(0, 20),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '播放中',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: scheme.onSurface,
                ),
              ),
              IconButton(
                onPressed: controller.cyclePlaybackMode,
                style: IconButton.styleFrom(
                  backgroundColor: scheme.surface.withValues(
                    alpha: isDark ? 0.6 : 0.72,
                  ),
                ),
                color: scheme.onSurface,
                icon: Icon(_modeIcon(controller.playbackMode)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              color: scheme.surface.withValues(alpha: isDark ? 0.9 : 0.94),
              borderRadius: BorderRadius.circular(36),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Image.asset(
                  'assets/images/app_logo_cropped.png',
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            currentTrack?.title ?? '还没有选中的歌曲',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: scheme.onSurface,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            currentTrack?.artist ?? '点击下方按钮导入本地音乐',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _CircleControl(
                icon: Icons.skip_previous_rounded,
                onPressed: controller.canSkipPrevious
                    ? controller.skipPrevious
                    : null,
              ),
              const SizedBox(width: 16),
              _CircleControl(
                icon: controller.isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                size: 76,
                primary: true,
                onPressed: controller.hasTracks
                    ? controller.togglePlayback
                    : null,
              ),
              const SizedBox(width: 16),
              _CircleControl(
                icon: Icons.skip_next_rounded,
                onPressed: controller.canSkipNext ? controller.skipNext : null,
              ),
            ],
          ),
          if (controller.isBusy) ...[
            const SizedBox(height: 14),
            LinearProgressIndicator(
              minHeight: 4,
              backgroundColor: scheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
            ),
          ],
        ],
      ),
    );
  }
}

class _PlaylistTile extends StatelessWidget {
  const _PlaylistTile({
    required this.track,
    required this.index,
    required this.isCurrent,
    required this.isPlaying,
    required this.onPlay,
    required this.onRemove,
  });

  final LocalTrack track;
  final int index;
  final bool isCurrent;
  final bool isPlaying;
  final VoidCallback onPlay;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isCurrent
            ? scheme.primaryContainer.withValues(alpha: 0.72)
            : scheme.surface.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isCurrent
              ? scheme.primary.withValues(alpha: 0.28)
              : scheme.outlineVariant.withValues(alpha: 0.45),
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 10,
        ),
        leading: InkWell(
          onTap: onPlay,
          borderRadius: BorderRadius.circular(999),
          child: CircleAvatar(
            radius: 24,
            backgroundColor: isCurrent
                ? scheme.primary
                : scheme.secondaryContainer,
            child: Icon(
              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: isCurrent ? scheme.onPrimary : scheme.onSecondaryContainer,
            ),
          ),
        ),
        title: Text(
          track.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            color: scheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            isCurrent ? '正在播放 · ${track.artist}' : track.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.drag_indicator_rounded),
              ),
            ),
            IconButton(
              onPressed: onRemove,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _QueuePreviewTile extends StatelessWidget {
  const _QueuePreviewTile({required this.track});

  final LocalTrack track;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.35),
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: scheme.secondaryContainer,
            child: Icon(
              Icons.play_arrow_rounded,
              color: scheme.onSecondaryContainer,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  track.artist,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: scheme.primary),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.eyebrow,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String eyebrow;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eyebrow,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(title, style: theme.textTheme.headlineMedium),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  subtitle!,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 12), trailing!],
      ],
    );
  }
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.surface.withValues(
              alpha: theme.brightness == Brightness.dark ? 0.82 : 0.86,
            ),
            scheme.surfaceContainer.withValues(
              alpha: theme.brightness == Brightness.dark ? 0.72 : 0.88,
            ),
          ],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.06),
            blurRadius: 24,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _EmptyPrompt extends StatelessWidget {
  const _EmptyPrompt({required this.onImport});

  final Future<void> Function() onImport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.35),
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.library_music_outlined, size: 44, color: scheme.primary),
          const SizedBox(height: 12),
          Text(
            '还没有音乐',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '导入本地音频后即可开始播放。',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant, height: 1.5),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onImport,
            icon: const Icon(Icons.add_rounded),
            label: const Text('导入音乐'),
          ),
        ],
      ),
    );
  }
}

class _CircleControl extends StatelessWidget {
  const _CircleControl({
    required this.icon,
    required this.onPressed,
    this.primary = false,
    this.size = 56,
  });

  final IconData icon;
  final Future<void> Function()? onPressed;
  final bool primary;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(999),
      child: Ink(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: primary
              ? scheme.primary
              : scheme.surface.withValues(alpha: 0.72),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: primary ? 36 : 30,
          color: primary ? scheme.onPrimary : scheme.onSurface,
        ),
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({required this.mode});

  final PlaybackMode mode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_modeIcon(mode), size: 18, color: scheme.onSurface),
            const SizedBox(width: 8),
            Text(
              switch (mode) {
                PlaybackMode.loopAll => '顺序循环',
                PlaybackMode.shuffle => '随机播放',
                PlaybackMode.repeatOne => '单曲循环',
              },
              style: TextStyle(
                color: scheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 6),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BackdropDecoration extends StatelessWidget {
  const _BackdropDecoration();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: -80,
            left: -50,
            child: _GlowCircle(
              size: 220,
              colors: isDark
                  ? const [Color(0x223A2316), Color(0x003A2316)]
                  : const [Color(0x30F6C59C), Color(0x00F6C59C)],
            ),
          ),
          Positioned(
            top: 140,
            right: -100,
            child: _GlowCircle(
              size: 260,
              colors: isDark
                  ? const [Color(0x22A95A2A), Color(0x00A95A2A)]
                  : const [Color(0x22F7B071), Color(0x00F7B071)],
            ),
          ),
          Positioned(
            bottom: 80,
            left: -60,
            child: _GlowCircle(
              size: 180,
              colors: isDark
                  ? const [Color(0x1EE0A36D), Color(0x00E0A36D)]
                  : const [Color(0x20FFD8B0), Color(0x00FFD8B0)],
            ),
          ),
        ],
      ),
    );
  }
}

class _GlowCircle extends StatelessWidget {
  const _GlowCircle({required this.size, required this.colors});

  final double size;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: colors),
      ),
    );
  }
}

IconData _modeIcon(PlaybackMode mode) {
  return switch (mode) {
    PlaybackMode.loopAll => Icons.repeat_rounded,
    PlaybackMode.shuffle => Icons.shuffle_rounded,
    PlaybackMode.repeatOne => Icons.repeat_one_rounded,
  };
}

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (duration.inHours > 0) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }
  return '$minutes:$seconds';
}
