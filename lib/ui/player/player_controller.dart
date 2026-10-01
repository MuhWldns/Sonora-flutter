/// Pengendali pemutar: satu-satunya jembatan antara UI dan
/// [SonoraAudioHandler].
///
/// Tanggung jawab:
/// - Membangun antrean native dari [MusicItem] dan menyiarkan perubahan ke UI.
/// - Menjalankan mutasi antrean secara serial agar permintaan cepat tidak
///   saling menimpa (yang terbaru selalu menang).
/// - Menjaga mini-player tetap ada selama aplikasi berjalan dan menyediakan
///   kontrol antrean (putar, berikutnya, sebelumnya, acak, ulangi, urut, hapus).
/// - Menghentikan pemutaran saat endpoint proxy berubah agar audio lama tidak
///   berbunyi dari host lama.
library;

import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

import '../../data/music_models.dart';
import '../../playback/sonora_audio_handler.dart';

/// Satu lagu di antrean UI.
@immutable
class PlayerTrack {
  const PlayerTrack({
    required this.videoId,
    required this.title,
    this.artist = '',
    this.thumbnail,
    this.durationMs = 0,
  });

  final String videoId;
  final String title;
  final String artist;
  final String? thumbnail;
  final int durationMs;

  Duration? get duration => durationMs > 0 ? Duration(milliseconds: durationMs) : null;

  static PlayerTrack fromMediaItem(MediaItem item) {
    final Object? id = item.extras?['videoId'];
    return PlayerTrack(
      videoId: id is String && id.isNotEmpty ? id : item.id,
      title: item.title,
      artist: item.artist ?? '',
      thumbnail: item.artUri?.toString(),
      durationMs: item.duration?.inMilliseconds ?? 0,
    );
  }

  static PlayerTrack fromMusicItem(MusicItem item) => PlayerTrack(
        videoId: item.videoId ?? '',
        title: item.title,
        artist: item.artist,
        thumbnail: item.thumbnail,
        durationMs: parseDurationToMs(item.duration) ?? 0,
      );
}

/// Mengubah durasi `"m:ss"`/`"h:mm:ss"` menjadi milidetik.
int? parseDurationToMs(String? value) {
  final String raw = value?.trim() ?? '';
  if (raw.isEmpty) return null;
  final List<String> parts = raw.split(':');
  if (parts.length < 2 || parts.length > 3) return null;
  int seconds = 0;
  for (final String part in parts) {
    final int? amount = int.tryParse(part.trim());
    if (amount == null || amount < 0) return null;
    seconds = seconds * 60 + amount;
  }
  return seconds * 1000;
}

/// Pilihan pengulangan.
enum PlayerRepeatMode { off, all, one }

/// Status pemutar yang dapat diamati UI.
@immutable
class PlayerSnapshot {
  const PlayerSnapshot({
    this.queue = const <PlayerTrack>[],
    this.index = -1,
    this.playing = false,
    this.buffering = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.shuffle = false,
    this.repeat = PlayerRepeatMode.off,
    this.error,
  });

  final List<PlayerTrack> queue;
  final int index;
  final bool playing;
  final bool buffering;
  final Duration position;
  final Duration duration;
  final bool shuffle;
  final PlayerRepeatMode repeat;
  final String? error;

  bool get hasTrack => index >= 0 && index < queue.length;
  PlayerTrack? get current => hasTrack ? queue[index] : null;

  double get progress {
    final int total = duration.inMilliseconds;
    if (total <= 0) return 0;
    return (position.inMilliseconds / total).clamp(0.0, 1.0);
  }
}

/// Pengendali pemutar yang dapat diamati.
class PlayerController extends ChangeNotifier {
  PlayerController(this._handler) {
    _queueSub = _handler.queue.listen(_onQueue);
    _mediaItemSub = _handler.mediaItem.listen(_onMediaItem);
    _stateSub = _handler.playbackState.listen(_onPlaybackState);
    _positionSub = _handler.positionStream.listen(_onPosition);
    _handler.error.addListener(_onError);
  }

  final SonoraAudioHandler _handler;

  StreamSubscription<List<MediaItem>>? _queueSub;
  StreamSubscription<MediaItem?>? _mediaItemSub;
  StreamSubscription<PlaybackState>? _stateSub;
  StreamSubscription<Duration>? _positionSub;

  PlayerSnapshot _snapshot = const PlayerSnapshot();
  PlayerSnapshot get snapshot => _snapshot;

  List<MediaItem> _nativeQueue = const <MediaItem>[];
  MediaItem? _current;

  bool _disposed = false;
  bool _playing = false;
  bool _buffering = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _shuffle = false;
  PlayerRepeatMode _repeat = PlayerRepeatMode.off;
  String? _error;

  /// Serialisasi mutasi antrean agar yang terbaru menang.
  Future<void> _chain = Future<void>.value();

  /// Generasi antrean: menaik saat antrean diganti/dihentikan sehingga operasi
  /// lama tidak menimpa keadaan terbaru.
  int _generation = 0;

  // ---------------------------------------------------------------------------
  // Publik
  // ---------------------------------------------------------------------------

  /// Memutar satu item sebagai antrean satu lagu.
  Future<void> playItem(MusicItem item) => playQueue(<MusicItem>[item]);

  /// Memutar daftar item apa adanya (mis. album/playlist), mulai [startIndex].
  Future<void> playQueue(List<MusicItem> items, {int startIndex = 0}) async {
    final List<MusicItem> playable =
        items.where((MusicItem item) => item.isPlayable).toList(growable: false);
    if (playable.isEmpty) return;
    final int generation = ++_generation;
    final int index = startIndex.clamp(0, playable.length - 1);
    _publish(PlayerSnapshot(
      queue: playable.map(PlayerTrack.fromMusicItem).toList(growable: false),
      index: index,
      buffering: true,
      shuffle: _shuffle,
      repeat: _repeat,
    ));
    try {
      await _handler.playItems(playable, startIndex: index);
    } catch (error) {
      if (generation != _generation) return;
      _setError(_message(error));
    }
  }

  /// Menambahkan satu item ke antrean. [next] menyisipkan setelah lagu aktif.
  Future<void> addItem(MusicItem item, {bool next = false}) async {
    if (!item.isPlayable) return;
    if (_snapshot.queue.isEmpty) {
      await playQueue(<MusicItem>[item]);
      return;
    }
    await _serialize(() async {
      final List<MusicItem> items = _nativeQueue
          .map(_fromMediaItem)
          .where((MusicItem entry) => entry.isPlayable)
          .toList();
      final MusicItem? current = _toMusicItemOrNull(_current);
      final int activeIndex = current == null
          ? items.length
          : items.indexWhere((MusicItem entry) => entry.videoId == current.videoId);
      final int insertAt = next && activeIndex >= 0
          ? (activeIndex + 1).clamp(0, items.length)
          : items.length;
      items.insert(insertAt, item);
      final int target = _snapshot.index < 0 ? 0 : _snapshot.index;
      try {
        await _handler.playItems(items, startIndex: target);
      } catch (error) {
        _setError(_message(error));
      }
    });
  }

  Future<void> playAt(int index) async {
    if (index < 0 || index >= _snapshot.queue.length) return;
    try {
      await _handler.skipToQueueItem(index);
    } catch (error) {
      _setError(_message(error));
    }
  }

  Future<void> next() async {
    try {
      await _handler.skipToNext();
    } catch (error) {
      _setError(_message(error));
    }
  }

  Future<void> previous() async {
    try {
      await _handler.skipToPrevious();
    } catch (error) {
      _setError(_message(error));
    }
  }

  Future<void> togglePlay() async {
    if (_snapshot.queue.isEmpty) return;
    try {
      if (_playing) {
        await _handler.pause();
      } else {
        await _handler.play();
      }
    } catch (error) {
      _setError(_message(error));
    }
  }

  Future<void> seek(Duration position) async {
    try {
      await _handler.seek(position);
      _position = position;
      _publishCurrent();
    } catch (error) {
      _setError(_message(error));
    }
  }

  Future<void> toggleShuffle() async {
    _shuffle = !_shuffle;
    try {
      await _handler.setShuffleMode(
        _shuffle ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none,
      );
    } catch (_) {
      // Perubahan mode tetap tercermin di UI.
    }
    _publishCurrent();
  }

  Future<void> cycleRepeat() async {
    final PlayerRepeatMode nextMode = switch (_repeat) {
      PlayerRepeatMode.off => PlayerRepeatMode.all,
      PlayerRepeatMode.all => PlayerRepeatMode.one,
      PlayerRepeatMode.one => PlayerRepeatMode.off,
    };
    _repeat = nextMode;
    try {
      await _handler.setRepeatMode(switch (nextMode) {
        PlayerRepeatMode.off => AudioServiceRepeatMode.none,
        PlayerRepeatMode.all => AudioServiceRepeatMode.all,
        PlayerRepeatMode.one => AudioServiceRepeatMode.one,
      });
    } catch (_) {
      // Abaikan kegagalan platform; UI tetap menampilkan pilihan pengguna.
    }
    _publishCurrent();
  }

  Future<void> removeAt(int index) async {
    if (index < 0 || index >= _snapshot.queue.length) return;
    if (_snapshot.queue.length <= 1) {
      await stop();
      return;
    }
    await _serialize(() async {
      final List<MusicItem> items = _nativeQueue
          .map(_fromMediaItem)
          .where((MusicItem entry) => entry.isPlayable)
          .toList();
      if (index >= items.length) return;
      items.removeAt(index);
      final int active = _snapshot.index;
      final int target = active <= 0
          ? 0
          : (active >= items.length ? items.length - 1 : active);
      try {
        await _handler.playItems(items, startIndex: target);
      } catch (error) {
        _setError(_message(error));
      }
    });
  }

  Future<void> moveItem(int from, int to) async {
    if (from == to) return;
    if (from < 0 || to < 0 || from >= _snapshot.queue.length) return;
    await _serialize(() async {
      final List<MusicItem> items = _nativeQueue
          .map(_fromMediaItem)
          .where((MusicItem entry) => entry.isPlayable)
          .toList();
      if (from >= items.length || to > items.length) return;
      final MusicItem moved = items.removeAt(from);
      items.insert(to.clamp(0, items.length), moved);
      final String? activeId = _snapshot.current?.videoId;
      final int target = activeId == null
          ? 0
          : items.indexWhere((MusicItem entry) => entry.videoId == activeId);
      try {
        await _handler.playItems(items, startIndex: target < 0 ? 0 : target);
      } catch (error) {
        _setError(_message(error));
      }
    });
  }

  /// Menghentikan pemutaran dan membersihkan antrean. Dipakai saat endpoint
  /// proxy berubah agar audio lama tidak terus berbunyi dari host lama.
  Future<void> stop() async {
    _generation++;
    try {
      await _handler.stop();
    } catch (_) {
      // Tidak ada yang bisa dilakukan bila stop gagal.
    }
    _nativeQueue = const <MediaItem>[];
    _current = null;
    _position = Duration.zero;
    _duration = Duration.zero;
    _playing = false;
    _buffering = false;
    _error = null;
    _publish(PlayerSnapshot(shuffle: _shuffle, repeat: _repeat));
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _queueSub?.cancel();
    _mediaItemSub?.cancel();
    _stateSub?.cancel();
    _positionSub?.cancel();
    _handler.error.removeListener(_onError);
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Penanganan peristiwa
  // ---------------------------------------------------------------------------

  void _onQueue(List<MediaItem> items) {
    if (_disposed) return;
    _nativeQueue = items;
    _publish(_compose());
  }

  void _onMediaItem(MediaItem? item) {
    if (_disposed) return;
    _current = item;
    _duration = item?.duration ?? Duration.zero;
    _publish(_compose());
  }

  void _onPlaybackState(PlaybackState state) {
    if (_disposed) return;
    _playing = state.playing;
    _buffering = state.processingState == AudioProcessingState.loading ||
        state.processingState == AudioProcessingState.buffering;
    _position = state.updatePosition;
    if (state.errorMessage != null && state.errorMessage!.isNotEmpty) {
      _error = state.errorMessage;
    }
    _publish(_compose());
  }

  void _onPosition(Duration position) {
    if (_disposed) return;
    _position = position;
    if (_duration <= Duration.zero && _current?.duration != null) {
      _duration = _current!.duration!;
    }
    _publish(_compose());
  }

  void _onError() {
    if (_disposed) return;
    final String? message = _handler.error.value;
    if (message != null && message.isNotEmpty) {
      _error = message;
      _publish(_compose());
    }
  }

  // ---------------------------------------------------------------------------
  // Pembantu
  // ---------------------------------------------------------------------------

  MusicItem? _toMusicItemOrNull(MediaItem? item) =>
      item == null ? null : _fromMediaItem(item);

  MusicItem _fromMediaItem(MediaItem item) {
    final Object? id = item.extras?['videoId'];
    final String videoId = id is String && id.isNotEmpty ? id : item.id;
    final String artist = item.artist ?? '';
    return MusicItem(
      type: 'song',
      title: item.title,
      subtitle: artist.isEmpty ? null : artist,
      artist: artist,
      thumbnail: item.artUri?.toString(),
      duration: _formatDuration(item.duration),
      videoId: videoId,
    );
  }

  static String? _formatDuration(Duration? duration) {
    if (duration == null || duration <= Duration.zero) return null;
    final int totalSeconds = duration.inSeconds;
    final int hours = totalSeconds ~/ 3600;
    final int minutes = (totalSeconds % 3600) ~/ 60;
    final int seconds = totalSeconds % 60;
    final String mm = hours > 0 ? minutes.toString().padLeft(2, '0') : '$minutes';
    final String ss = seconds.toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
  }

  PlayerSnapshot _compose() {
    final List<PlayerTrack> queue = _nativeQueue
        .map(PlayerTrack.fromMediaItem)
        .where((PlayerTrack track) => track.videoId.isNotEmpty)
        .toList(growable: false);
    int index = -1;
    final MediaItem? current = _current;
    if (current != null) {
      final Object? id = current.extras?['videoId'];
      final String videoId = id is String && id.isNotEmpty ? id : current.id;
      index = queue.indexWhere((PlayerTrack track) => track.videoId == videoId);
    }
    final Duration duration = _duration > Duration.zero
        ? _duration
        : (index >= 0 ? (queue[index].duration ?? Duration.zero) : Duration.zero);
    return PlayerSnapshot(
      queue: queue,
      index: index,
      playing: _playing,
      buffering: _buffering,
      position: _position > duration ? duration : _position,
      duration: duration,
      shuffle: _shuffle,
      repeat: _repeat,
      error: _error,
    );
  }

  void _publish(PlayerSnapshot snapshot) {
    _snapshot = snapshot;
    notifyListeners();
  }

  void _publishCurrent() => _publish(_compose());

  void _setError(String message) {
    _error = message;
    _publish(_compose());
  }

  String _message(Object error) => error.toString();

  Future<void> _serialize(Future<void> Function() operation) {
    final Future<void> run =
        _chain.then((_) => operation(), onError: (_) => operation());
    _chain = run.then((_) {}, onError: (_) {});
    return run;
  }
}
