import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../online_library/online_library_cache.dart';
import 'models/local_track.dart';

enum PlaybackMode { loopAll, shuffle, repeatOne }

class PlayerController extends ChangeNotifier {
  PlayerController._(this._prefs, {OnlineLibraryCache? onlineCache})
    : _audioPlayer = AudioPlayer(),
      _onlineCache = onlineCache ?? OnlineLibraryCache.instance;

  static const _playlistKey = 'orange_playlist_tracks';
  static const _modeKey = 'orange_playlist_mode';
  static const _indexKey = 'orange_playlist_index';

  final SharedPreferences _prefs;
  final AudioPlayer _audioPlayer;
  final OnlineLibraryCache _onlineCache;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final Set<String> _fileBackedIds = {};
  Future<void> _cacheGate = Future<void>.value();
  bool _disposed = false;

  List<LocalTrack> _tracks = const [];
  PlaybackMode _playbackMode = PlaybackMode.loopAll;
  int? _currentIndex;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  bool _isBusy = true;
  String? _playbackError;
  String? _activityMessage;

  static Future<PlayerController> bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    final controller = PlayerController._(prefs);
    await controller._configure();
    await controller._restoreState();
    return controller;
  }

  List<LocalTrack> get tracks => List.unmodifiable(_tracks);
  PlaybackMode get playbackMode => _playbackMode;
  int? get currentIndex => _currentIndex;
  Duration get position => _position;
  Duration get duration => _duration;
  bool get isPlaying => _isPlaying;
  bool get isBusy => _isBusy;
  String? get playbackError => _playbackError;
  String? get activityMessage => _activityMessage;

  bool isFileBacked(String trackId) => _fileBackedIds.contains(trackId);

  /// Drops local copies of remote tracks after the online cache is deleted.
  Future<void> releaseCachedAudio() async {
    final usesCache = _tracks.any(
      (track) => track.isRemote && _fileBackedIds.contains(track.id),
    );
    if (!usesCache) {
      return;
    }
    await _rebuildQueue(
      preferredTrackId: currentTrack?.id,
      resumePosition: _position,
      resumePlayback: _isPlaying,
    );
  }
  bool get hasTracks => _tracks.isNotEmpty;
  bool get canSkipNext => _tracks.length > 1;
  bool get canSkipPrevious => _tracks.length > 1;

  LocalTrack? get currentTrack {
    final index = _currentIndex;
    if (index == null || index < 0 || index >= _tracks.length) {
      return _tracks.isEmpty ? null : _tracks.first;
    }
    return _tracks[index];
  }

  List<LocalTrack> get upcomingTracks {
    return _tracks
        .where((track) => track.id != currentTrack?.id)
        .take(4)
        .toList();
  }

  Future<void> _configure() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    _subscriptions.addAll([
      _audioPlayer.playerStateStream.listen((state) {
        _isPlaying = state.playing;
        _isBusy =
            state.processingState == ProcessingState.loading ||
            state.processingState == ProcessingState.buffering;
        if (state.playing && _playbackError != null) {
          _playbackError = null;
        }
        if (state.processingState == ProcessingState.completed &&
            _playbackMode != PlaybackMode.repeatOne) {
          _position = _duration;
        }
        notifyListeners();
      }),
      _audioPlayer.playbackEventStream.listen(
        (_) {},
        onError: (Object _, StackTrace _) {
          _playbackError = '播放失败，请检查这首音乐是否还能访问';
          _isBusy = false;
          notifyListeners();
        },
      ),
      _audioPlayer.currentIndexStream.listen((index) {
        _currentIndex = index;
        _persistState();
        notifyListeners();
      }),
      _audioPlayer.positionStream.listen((position) {
        _position = position;
        notifyListeners();
      }),
      _audioPlayer.durationStream.listen((duration) {
        _duration = duration ?? Duration.zero;
        notifyListeners();
      }),
    ]);
  }

  Future<void> _restoreState() async {
    final playlistJson = _prefs.getString(_playlistKey);
    final savedMode = _prefs.getString(_modeKey);
    final savedIndex = _prefs.getInt(_indexKey);

    if (savedMode != null) {
      _playbackMode = PlaybackMode.values.firstWhere(
        (mode) => mode.name == savedMode,
        orElse: () => PlaybackMode.loopAll,
      );
    }

    if (playlistJson != null && playlistJson.isNotEmpty) {
      final decoded = jsonDecode(playlistJson) as List<dynamic>;
      final restoredTracks = decoded
          .map((item) => LocalTrack.fromJson(item as Map<String, dynamic>))
          .toList();
      _tracks = await _filterExistingTracks(restoredTracks);

      if (_tracks.length != restoredTracks.length) {
        await _persistPlaylist();
      }

      if (_tracks.isNotEmpty) {
        try {
          await _rebuildQueue(initialIndex: savedIndex);
        } catch (_) {
          _tracks = const [];
          await _persistPlaylist();
          _isBusy = false;
          notifyListeners();
        }
      } else {
        _isBusy = false;
        notifyListeners();
      }
    } else {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<List<LocalTrack>> _filterExistingTracks(
    List<LocalTrack> tracks,
  ) async {
    final existingTracks = <LocalTrack>[];
    for (final track in tracks) {
      if (track.isRemote || await File(track.path).exists()) {
        existingTracks.add(track);
      }
    }
    return existingTracks;
  }

  Future<int> pickAndAddTracks() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const [
        'mp3',
        'wav',
        'm4a',
        'aac',
        'flac',
        'ogg',
        'opus',
      ],
    );

    if (result == null) {
      return 0;
    }

    final existingIds = _tracks.map((track) => track.id).toSet();
    final additions = result.files
        .where((file) => file.path != null && !existingIds.contains(file.path))
        .map((file) => LocalTrack.fromPath(file.path!, title: file.name))
        .toList();

    if (additions.isEmpty) {
      return 0;
    }

    await addTracks(additions);
    return additions.length;
  }

  Future<void> addTrack(LocalTrack track) => addTracks([track]);

  Future<void> addTracks(Iterable<LocalTrack> tracks) async {
    final existingIds = _tracks.map((track) => track.id).toSet();
    final additions = tracks
        .where((track) => !existingIds.contains(track.id))
        .toList();
    if (additions.isEmpty) {
      return;
    }

    final preferredTrackId = currentTrack?.id;
    final resumePosition = _position;
    final resumePlayback = _isPlaying;
    _tracks = [..._tracks, ...additions];
    await _rebuildQueue(
      preferredTrackId: preferredTrackId,
      resumePosition: resumePosition,
      resumePlayback: resumePlayback,
    );
    await _persistPlaylist();
  }

  Future<void> playTrack(int index) async {
    if (index < 0 || index >= _tracks.length) {
      return;
    }
    final track = _tracks[index];
    if (await _alignSourceWithCache(track, position: Duration.zero, play: true)) {
      return;
    }
    await _audioPlayer.seek(Duration.zero, index: index);
    await _audioPlayer.play();
  }

  Future<void> togglePlayback() async {
    if (!hasTracks) {
      return;
    }
    if (_isPlaying) {
      await _audioPlayer.pause();
      return;
    }
    final track = currentTrack;
    if (track != null &&
        await _alignSourceWithCache(track, position: _position, play: true)) {
      return;
    }
    await _audioPlayer.play();
  }

  Future<void> skipNext() async {
    if (_tracks.isEmpty) {
      return;
    }
    final nextIndex = _audioPlayer.nextIndex;
    if (nextIndex != null && nextIndex >= 0 && nextIndex < _tracks.length) {
      final aligned = await _alignSourceWithCache(
        _tracks[nextIndex],
        position: Duration.zero,
        play: true,
      );
      if (aligned) {
        return;
      }
    }
    await _audioPlayer.seekToNext();
    if (!_isPlaying) {
      await _audioPlayer.play();
    }
  }

  Future<void> skipPrevious() async {
    if (_tracks.isEmpty) {
      return;
    }
    if (_position > const Duration(seconds: 3)) {
      await _audioPlayer.seek(Duration.zero);
      return;
    }
    final previousIndex = _audioPlayer.previousIndex;
    if (previousIndex != null &&
        previousIndex >= 0 &&
        previousIndex < _tracks.length) {
      final aligned = await _alignSourceWithCache(
        _tracks[previousIndex],
        position: Duration.zero,
        play: true,
      );
      if (aligned) {
        return;
      }
    }
    await _audioPlayer.seekToPrevious();
    if (!_isPlaying) {
      await _audioPlayer.play();
    }
  }

  Future<void> seek(Duration target) async {
    if (!hasTracks) {
      return;
    }
    await _audioPlayer.seek(target);
  }

  Future<void> cyclePlaybackMode() async {
    switch (_playbackMode) {
      case PlaybackMode.loopAll:
        _playbackMode = PlaybackMode.shuffle;
      case PlaybackMode.shuffle:
        _playbackMode = PlaybackMode.repeatOne;
      case PlaybackMode.repeatOne:
        _playbackMode = PlaybackMode.loopAll;
    }

    await _applyPlaybackMode(reshuffle: true);
    await _persistState();
    notifyListeners();
  }

  Future<void> removeTrackAt(int index) async {
    if (index < 0 || index >= _tracks.length) {
      return;
    }

    final wasPlaying = _isPlaying;
    final preferredId = currentTrack?.id == _tracks[index].id
        ? _fallbackTrackIdAfterRemoval(index)
        : currentTrack?.id;
    final resumePosition = currentTrack?.id == _tracks[index].id
        ? Duration.zero
        : _position;

    final updated = [..._tracks]..removeAt(index);
    _tracks = updated;

    await _rebuildQueue(
      preferredTrackId: preferredId,
      resumePosition: resumePosition,
      resumePlayback: wasPlaying && _tracks.isNotEmpty,
    );
    await _persistPlaylist();
  }

  Future<void> reorderTracks(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _tracks.length) {
      return;
    }

    if (newIndex > oldIndex) {
      newIndex -= 1;
    }

    final updated = [..._tracks];
    final track = updated.removeAt(oldIndex);
    updated.insert(newIndex, track);

    final preferredTrackId = currentTrack?.id;
    final resumePosition = _position;
    final wasPlaying = _isPlaying;

    _tracks = updated;
    await _rebuildQueue(
      preferredTrackId: preferredTrackId,
      resumePosition: resumePosition,
      resumePlayback: wasPlaying,
    );
    await _persistPlaylist();
  }

  Future<void> _rebuildQueue({
    String? preferredTrackId,
    int? initialIndex,
    Duration? resumePosition,
    bool resumePlayback = false,
  }) async {
    _isBusy = true;
    notifyListeners();

    if (_tracks.isEmpty) {
      _currentIndex = null;
      _position = Duration.zero;
      _duration = Duration.zero;
      await _audioPlayer.stop();
      _isBusy = false;
      notifyListeners();
      return;
    }

    final queue = <AudioSource>[];
    final fileBacked = <String>{};
    for (final track in _tracks) {
      queue.add(await _sourceFor(track, fileBacked));
    }
    _fileBackedIds
      ..clear()
      ..addAll(fileBacked);

    final restoredIndex = _resolveIndex(
      preferredTrackId: preferredTrackId,
      explicitIndex: initialIndex,
    );

    await _audioPlayer.setAudioSources(
      queue,
      initialIndex: restoredIndex,
      initialPosition: resumePosition,
    );
    _currentIndex = restoredIndex;
    await _applyPlaybackMode(reshuffle: true);

    if (resumePlayback) {
      await _audioPlayer.play();
    }

    _isBusy = false;
    await _persistState();
    notifyListeners();
  }

  Future<AudioSource> _sourceFor(
    LocalTrack track,
    Set<String> fileBacked,
  ) async {
    if (track.isRemote) {
      final cached = await _onlineCache.cachedAudio(track.path);
      if (cached != null) {
        fileBacked.add(track.id);
        return AudioSource.uri(Uri.file(cached.path), tag: track.mediaItem);
      }
      return AudioSource.uri(
        Uri.parse(track.path),
        tag: track.mediaItem,
        headers: const {'User-Agent': 'OrangePlayer'},
      );
    }
    return AudioSource.uri(Uri.file(track.path), tag: track.mediaItem);
  }

  /// Downloads a remote track when needed and reloads the queue once the local
  /// file should replace the network address. Returns true when playback was
  /// already started from the reloaded queue.
  Future<bool> _alignSourceWithCache(
    LocalTrack track, {
    Duration? position,
    required bool play,
  }) {
    final operation = _cacheGate.then(
      (_) => _alignSourceBody(track, position: position, play: play),
    );
    _cacheGate = operation.then((_) {}, onError: (_) {});
    return operation;
  }

  Future<bool> _alignSourceBody(
    LocalTrack track, {
    Duration? position,
    required bool play,
  }) async {
    if (!track.isRemote) {
      return false;
    }
    if (!await _onlineCache.isAudioCached(track.path)) {
      await _cacheRemote(track);
    }
    final onDisk = await _onlineCache.isAudioCached(track.path);
    final usingFile = _fileBackedIds.contains(track.id);
    if (onDisk == usingFile) {
      return false;
    }
    await _rebuildQueue(
      preferredTrackId: track.id,
      resumePosition: position,
      resumePlayback: play,
    );
    return true;
  }

  Future<void> _cacheRemote(LocalTrack track) async {
    if (!track.isRemote || await _onlineCache.isAudioCached(track.path)) {
      return;
    }
    _activityMessage = '正在缓存「${track.title}」';
    notifyListeners();
    var lastBucket = -1;
    try {
      await _onlineCache.downloadAudio(
        track.path,
        onProgress: (received, total) {
          if (_disposed || total == null || total <= 0) {
            return;
          }
          final bucket = received * 10 ~/ total;
          if (bucket == lastBucket) {
            return;
          }
          lastBucket = bucket;
          _activityMessage = '正在缓存「${track.title}」 ${bucket * 10}%';
          notifyListeners();
        },
      );
    } catch (_) {
      if (_disposed) {
        return;
      }
      _playbackError = '缓存失败，改为在线播放';
      notifyListeners();
    } finally {
      _activityMessage = null;
      if (!_disposed) {
        notifyListeners();
      }
    }
  }

  int _resolveIndex({String? preferredTrackId, int? explicitIndex}) {
    if (_tracks.isEmpty) {
      return 0;
    }

    if (preferredTrackId != null) {
      final index = _tracks.indexWhere((track) => track.id == preferredTrackId);
      if (index != -1) {
        return index;
      }
    }

    if (explicitIndex != null &&
        explicitIndex >= 0 &&
        explicitIndex < _tracks.length) {
      return explicitIndex;
    }

    return 0;
  }

  String? _fallbackTrackIdAfterRemoval(int removedIndex) {
    if (_tracks.length <= 1) {
      return null;
    }
    final fallbackIndex = removedIndex >= _tracks.length - 1
        ? _tracks.length - 2
        : removedIndex + 1;
    return _tracks[fallbackIndex].id;
  }

  Future<void> _applyPlaybackMode({bool reshuffle = false}) async {
    switch (_playbackMode) {
      case PlaybackMode.loopAll:
        await _audioPlayer.setLoopMode(LoopMode.all);
        await _audioPlayer.setShuffleModeEnabled(false);
      case PlaybackMode.shuffle:
        if (reshuffle) {
          await _audioPlayer.shuffle();
        }
        await _audioPlayer.setLoopMode(LoopMode.all);
        await _audioPlayer.setShuffleModeEnabled(true);
      case PlaybackMode.repeatOne:
        await _audioPlayer.setShuffleModeEnabled(false);
        await _audioPlayer.setLoopMode(LoopMode.one);
    }
  }

  Future<void> _persistPlaylist() async {
    final playlist = jsonEncode(
      _tracks.map((track) => track.toJson()).toList(),
    );
    await _prefs.setString(_playlistKey, playlist);
  }

  Future<void> _persistState() async {
    await _prefs.setString(_modeKey, _playbackMode.name);
    await _prefs.setInt(_indexKey, _currentIndex ?? 0);
  }

  @override
  void dispose() {
    _disposed = true;
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _audioPlayer.dispose();
    super.dispose();
  }
}
