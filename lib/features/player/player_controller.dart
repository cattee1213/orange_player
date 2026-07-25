import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/local_track.dart';

enum PlaybackMode { loopAll, shuffle, repeatOne }

class PlayerController extends ChangeNotifier {
  PlayerController._(this._prefs) : _audioPlayer = AudioPlayer();

  static const _playlistKey = 'orange_playlist_tracks';
  static const _modeKey = 'orange_playlist_mode';
  static const _indexKey = 'orange_playlist_index';

  final SharedPreferences _prefs;
  final AudioPlayer _audioPlayer;
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  List<LocalTrack> _tracks = const [];
  PlaybackMode _playbackMode = PlaybackMode.loopAll;
  int? _currentIndex;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  bool _isBusy = true;

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
        if (state.processingState == ProcessingState.completed &&
            _playbackMode != PlaybackMode.repeatOne) {
          _position = _duration;
        }
        notifyListeners();
      }),
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
      final exists = await File(track.path).exists();
      if (exists) {
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
    await _audioPlayer.seek(Duration.zero, index: index);
    await _audioPlayer.play();
  }

  Future<void> togglePlayback() async {
    if (!hasTracks) {
      return;
    }
    if (_isPlaying) {
      await _audioPlayer.pause();
    } else {
      await _audioPlayer.play();
    }
  }

  Future<void> skipNext() async {
    if (_tracks.isEmpty) {
      return;
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

    final queue = _tracks
        .map(
          (track) =>
              AudioSource.uri(Uri.file(track.path), tag: track.mediaItem),
        )
        .toList();

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
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _audioPlayer.dispose();
    super.dispose();
  }
}
