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
                    const _AboutTab(),
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
                backgroundColor: Colors.white.withValues(alpha: 0.96),
                indicatorColor: const Color(0x33FF8E3C),
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
                  NavigationDestination(
                    icon: Icon(Icons.info_outline_rounded),
                    label: '关于',
                  ),
                ],
              ),
            ),
          ),
          floatingActionButton: _tabIndex != 2
              ? FloatingActionButton.extended(
                  onPressed: _importTracks,
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  icon: const Icon(Icons.library_music_rounded),
                  label: const Text('导入音乐'),
                )
              : null,
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
            eyebrow: '聆听橙子',
            title: '你的离线橙调播放器',
            subtitle: '支持本地文件、后台播放、歌单维护与三种播放模式。',
            trailing: FilledButton.tonalIcon(
              onPressed: onImport,
              icon: const Icon(Icons.add_circle_outline_rounded),
              label: const Text('添加本地文件'),
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
                        color: Colors.white70,
                      ),
                    ),
                    Text(
                      _formatDuration(controller.duration),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white70,
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
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('接下来播放', style: theme.textTheme.titleLarge),
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
            title: '我的橙子歌单',
            subtitle: '支持拖拽排序、删除项目，并自动记住上次播放位置。',
            trailing: OutlinedButton.icon(
              onPressed: onImport,
              icon: const Icon(Icons.file_open_rounded),
              label: const Text('继续导入'),
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

class _AboutTab extends StatelessWidget {
  const _AboutTab();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            eyebrow: '关于应用',
            title: '聆听橙子',
            subtitle: '作者：橙子 · 一款专注离线、本地与后台播放体验的音乐播放器。',
            trailing: const Icon(Icons.music_note_rounded, size: 36),
          ),
          const SizedBox(height: 20),
          _GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '设计理念',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  '以暴力橙为主色，结合留白、柔和阴影与圆角卡片，营造高雅、扁平、轻盈的播放器气质。',
                  style: TextStyle(color: Colors.white, height: 1.6),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: const [
                    _InfoBadge(text: '本地离线导入'),
                    _InfoBadge(text: '后台播放'),
                    _InfoBadge(text: '顺序 / 随机 / 单曲循环'),
                    _InfoBadge(text: '播放列表排序维护'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _FeaturePanel(
            icon: Icons.offline_bolt_rounded,
            title: '离线优先',
            description: '通过系统文件选择器导入手机本地音频，不依赖网络服务即可播放。',
          ),
          const SizedBox(height: 12),
          _FeaturePanel(
            icon: Icons.headphones_battery_rounded,
            title: '后台不中断',
            description: '支持系统通知栏 / 锁屏媒体控制，切到后台也能持续播放。',
          ),
          const SizedBox(height: 12),
          _FeaturePanel(
            icon: Icons.auto_awesome_rounded,
            title: '橙系审美',
            description: '首页、歌单、信息页统一橙色渐变和玻璃质感卡片，适合继续扩展。',
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
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF9A44), Color(0xFFFF6B00), Color(0xFFFF8C42)],
        ),
        borderRadius: BorderRadius.circular(36),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33FF6B00),
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
                'Now Playing',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                ),
              ),
              IconButton(
                onPressed: controller.cyclePlaybackMode,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.16),
                ),
                color: Colors.white,
                icon: Icon(_modeIcon(controller.playbackMode)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: 148,
            height: 148,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.94),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.graphic_eq_rounded,
              size: 72,
              color: Color(0xFFFF6B00),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            currentTrack?.title ?? '还没有选中的歌曲',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            currentTrack?.artist ?? '点击下方按钮导入本地音乐',
            style: theme.textTheme.bodyLarge?.copyWith(color: Colors.white70),
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
            const LinearProgressIndicator(
              minHeight: 4,
              backgroundColor: Color(0x22FFFFFF),
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isCurrent ? const Color(0xFFFFF0E5) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x11000000),
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
                ? const Color(0xFFFF6B00)
                : const Color(0xFFFFE0CC),
            child: Icon(
              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: isCurrent ? Colors.white : const Color(0xFFFF6B00),
            ),
          ),
        ),
        title: Text(
          track.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            color: const Color(0xFF2A1C12),
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
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x11000000),
            blurRadius: 18,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 24,
            backgroundColor: Color(0xFFFFF0E5),
            child: Icon(Icons.play_arrow_rounded, color: Color(0xFFFF6B00)),
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
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  track.artist,
                  style: const TextStyle(color: Color(0xFF846E61)),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: Color(0xFFFF6B00)),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final String eyebrow;
  final String title;
  final String subtitle;
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
                  color: const Color(0xFFFF6B00),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(title, style: theme.textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: const Color(0xFF6C5548),
                ),
              ),
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
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFAD66), Color(0xFFFF7B1C)],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1AFF6B00),
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x11000000),
            blurRadius: 20,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.library_music_outlined,
            size: 44,
            color: Color(0xFFFF6B00),
          ),
          const SizedBox(height: 12),
          const Text(
            '还没有音乐',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            '点击按钮从手机或本地磁盘导入音频文件，马上开始你的橙色歌单。',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF7A6458), height: 1.5),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onImport,
            icon: const Icon(Icons.add_rounded),
            label: const Text('导入第一首音乐'),
          ),
        ],
      ),
    );
  }
}

class _FeaturePanel extends StatelessWidget {
  const _FeaturePanel({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x11000000),
            blurRadius: 16,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: const Color(0xFFFFF0E5),
            child: Icon(icon, color: const Color(0xFFFF6B00)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: const TextStyle(color: Color(0xFF6F594B), height: 1.5),
                ),
              ],
            ),
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
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(999),
      child: Ink(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: primary ? Colors.white : Colors.white.withValues(alpha: 0.16),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: primary ? 36 : 30,
          color: primary ? const Color(0xFFFF6B00) : Colors.white,
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_modeIcon(mode), size: 18, color: Colors.white),
            const SizedBox(width: 8),
            Text(
              switch (mode) {
                PlaybackMode.loopAll => '顺序循环',
                PlaybackMode.shuffle => '随机播放',
                PlaybackMode.repeatOne => '单曲循环',
              },
              style: const TextStyle(
                color: Colors.white,
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
    return Expanded(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 6),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
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

class _InfoBadge extends StatelessWidget {
  const _InfoBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
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
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: -80,
            left: -50,
            child: _GlowCircle(
              size: 220,
              colors: const [Color(0x55FFAA66), Color(0x00FFAA66)],
            ),
          ),
          Positioned(
            top: 140,
            right: -100,
            child: _GlowCircle(
              size: 260,
              colors: const [Color(0x44FF7A1B), Color(0x00FF7A1B)],
            ),
          ),
          Positioned(
            bottom: 80,
            left: -60,
            child: _GlowCircle(
              size: 180,
              colors: const [Color(0x33FF8B3D), Color(0x00FF8B3D)],
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
