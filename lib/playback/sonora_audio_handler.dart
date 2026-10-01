import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../data/music_models.dart';
import '../data/sonora_api.dart';

/// Audio handler that bridges the Sonora API to [just_audio] and exposes the
/// standard [AudioHandler] surface consumed by the UI.
///
/// Ownership: the handler owns a single [AudioPlayer] playlist. Native
/// auto-advance between queue items is delegated to that playlist; the handler
/// never advances the queue manually.
///
/// Concurrency: all queue mutations run through a single serialized future
/// chain so that rapid [playItems] requests cannot interleave. The most
/// recently requested queue always wins, and a superseded request becomes a
/// no-op instead of racing the winner.
///
/// Errors: playback failures are captured from just_audio's error stream,
/// published to [error] for the UI, and reflected on [playbackState] (which
/// carries no error processing state of its own). Fire-and-forget calls
/// swallow [PlayerInterruptedException] (expected when a newer request
/// supersedes an in-flight one) but never let other failures escape unhandled.
class SonoraAudioHandler extends BaseAudioHandler with SeekHandler {
  SonoraAudioHandler(this._api) : _player = AudioPlayer() {
    _sub = _player.sequenceStateStream.listen(_onSequenceChanged);
    _stateSub = _player.playbackEventStream.listen(_onPlaybackEvent);
    _durationSub = _player.durationStream.listen(_onDuration);
    _positionSub = _player.positionStream.listen(_onPosition);
    _errorSub = _player.errorStream.listen(_onPlayerError);
  }

  final SonoraApi _api;
  final AudioPlayer _player;

  StreamSubscription<SequenceState>? _sub;
  StreamSubscription<PlaybackEvent>? _stateSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<PlayerException>? _errorSub;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;
  StreamSubscription<void>? _noisySub;

  PlaybackEvent? _lastEvent;
  Duration? _lastDuration;

  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();

  /// Last playback failure, or `null` when there is no error to show.
  final ValueNotifier<String?> error = ValueNotifier<String?>(null);

  /// Signature of the queue currently applied, used to ignore duplicate
  /// requests and to detect superseded requests.
  List<String> _signature = const <String>[];

  /// Serializes queue mutations so the latest request always wins.
  Future<void> _operations = Future<void>.value();

  /// Monotonic request counter. Each [playItems] call captures the next value;
  /// any operation whose captured value no longer matches has been superseded
  /// and must not load or start playback.
  int _generation = 0;

  bool _disposed = false;

  /// The most recent position reported by the player.
  Duration get position => _player.position;

  /// Position updates for the seek bar.
  Stream<Duration> get positionStream => _positionController.stream;

  /// Configures the audio session and starts the background service.
  ///
  /// Safe to call on Android and web. Android is the primary target; the web
  /// implementation is provided for smoke testing.
  static Future<SonoraAudioHandler> initialize(SonoraApi api) async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    final handler = await AudioService.init<SonoraAudioHandler>(
      builder: () => SonoraAudioHandler(api),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.example.sonora_flutter.playback',
        androidNotificationChannelName: 'Sonora playback',
        androidNotificationChannelDescription:
            'Playback controls for the Sonora music player',
        androidNotificationIcon: 'drawable/ic_stat_sonora',
        androidNotificationOngoing: false,
        androidStopForegroundOnPause: false,
        androidNotificationClickStartsActivity: true,
        androidShowNotificationBadge: false,
        preloadArtwork: true,
      ),
    );
    await handler._configureSession(session);
    return handler;
  }

  Future<void> _configureSession(AudioSession session) async {
    _interruptionSub = session.interruptionEventStream.listen((event) {
      if (event.begin) {
        switch (event.type) {
          case AudioInterruptionType.duck:
            _runGuarded(() => _player.setVolume(0.5));
          case AudioInterruptionType.pause:
          case AudioInterruptionType.unknown:
            _runGuarded(pause);
        }
      } else {
        _runGuarded(() => _player.setVolume(1.0));
      }
    });
    _noisySub = session.becomingNoisyEventStream.listen((_) {
      _runGuarded(pause);
    });
  }

  /// Replaces the queue with [items] and starts playback at [startIndex].
  ///
  /// Unplayable items are filtered out; the identity of the requested start
  /// item is preserved by looking it up in the filtered list. Repeated calls
  /// with an identical queue are idempotent and simply (re)start playback.
  Future<void> playItems(List<MusicItem> items, {int startIndex = 0}) {
    final generation = ++_generation;
    return _enqueue(() async {
      if (_disposed || generation != _generation) return;
      final playable = items.where((item) => item.isPlayable).toList();
      if (playable.isEmpty) {
        _publishError('No playable tracks were provided.');
        return;
      }
      final requested = (startIndex >= 0 && startIndex < items.length)
          ? items[startIndex]
          : null;
      var index = requested == null
          ? 0
          : playable.indexWhere(
              (item) => _sameTrack(item, requested),
            );
      if (index < 0) index = 0;

      final signature = playable.map(_trackKey).toList();
      if (!listEquals(signature, _signature)) {
        final loaded = await _applyQueue(playable, signature, index);
        if (!loaded) return;
      } else if (_player.sequenceState.currentIndex != index) {
        // Same queue, different selected item: jump without reloading streams.
        try {
          await _player.seek(Duration.zero, index: index);
        } on PlayerInterruptedException {
          return;
        } on PlayerException catch (exception) {
          _publishError(_describe(exception));
          return;
        }
      }
      // A newer request may have arrived while loading; if so, it owns playback.
      if (_disposed || generation != _generation) return;
      error.value = null;
      _publishPlaybackState();
      _startPlayback();
    });
  }

  Future<bool> _applyQueue(
    List<MusicItem> playable,
    List<String> signature,
    int startIndex,
  ) async {
    final sources = <AudioSource>[
      for (final item in playable)
        AudioSource.uri(
          _api.streamUri(item.videoId!),
          tag: item,
        ),
    ];
    try {
      await _player.setAudioSources(
        sources,
        preload: true,
        initialIndex: startIndex,
        initialPosition: Duration.zero,
      );
    } on PlayerInterruptedException {
      // A newer queue replaced this one mid-load; do not treat as loaded.
      return false;
    } on PlayerException catch (exception) {
      _publishError(_describe(exception));
      return false;
    } catch (exception) {
      _publishError(exception.toString());
      return false;
    }
    _signature = signature;
    // Broadcast so the notification and UI agree with the native playlist.
    _publishQueue();
    _publishMediaItem();
    return true;
  }

  /// Starts playback without awaiting its lifetime.
  ///
  /// [AudioPlayer.play]'s future completes only when playback later pauses,
  /// stops, or reaches the end, so awaiting it would stall the operation chain
  /// for an entire track. Failures are published instead of escaping.
  void _startPlayback() {
    if (_disposed) return;
    unawaited(
      _player.play().catchError((Object cause) {
        if (cause is PlayerInterruptedException) return;
        _publishError(
          cause is PlayerException ? _describe(cause) : cause.toString(),
        );
      }),
    );
  }

  /// Serializes [operation] behind any in-flight queue mutation.
  ///
  /// The returned future never completes with an error: unexpected failures
  /// are published to [error] instead of escaping to an un-awaited caller.
  Future<void> _enqueue(Future<void> Function() operation) {
    final next = _operations.then((_) => operation());
    _operations = next.catchError((Object _) {});
    return next.catchError((Object cause) {
      _publishError(cause.toString());
    });
  }

  /// Runs [operation] without letting errors escape, recording them instead.
  void _runGuarded(Future<void> Function() operation) {
    unawaited(
      operation().catchError((Object cause, StackTrace stackTrace) {
        _publishError(cause.toString());
      }),
    );
  }

  void _onSequenceChanged(SequenceState _) {
    if (_disposed) return;
    _publishQueue();
    _publishMediaItem();
  }

  void _onPlaybackEvent(PlaybackEvent event) {
    _lastEvent = event;
    if (_disposed) return;
    _publishPlaybackState();
  }

  void _onDuration(Duration? duration) {
    if (_disposed || duration == _lastDuration) return;
    _lastDuration = duration;
    // Republish the current item so the seek bar receives the real duration
    // once the stream has been probed.
    _publishMediaItem();
  }

  void _onPosition(Duration position) {
    if (_disposed || _positionController.isClosed) return;
    _positionController.add(position);
  }

  void _onPlayerError(PlayerException exception) {
    _publishError(_describe(exception));
  }

  void _publishPlaybackState() {
    if (_disposed) return;
    final event = _lastEvent;
    final state = _player.playerState;
    final message = error.value;
    final inError = message != null;
    playbackState.add(
      PlaybackState(
        processingState: _mapProcessing(state.processingState),
        playing: state.playing,
        controls: <MediaControl>[
          MediaControl.skipToPrevious,
          if (state.playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
        ],
        androidCompactActionIndices: const <int>[0, 1, 2],
        systemActions: const <MediaAction>{
          MediaAction.seek,
        },
        updatePosition: event?.updatePosition ?? _player.position,
        bufferedPosition: event?.bufferedPosition ?? Duration.zero,
        speed: _player.speed,
        // just_audio has no ProcessingState.error and its PlaybackEvent error
        // fields are unreachable; playback failures are carried by the error
        // notifier and reflected on the controls instead.
        errorCode: inError ? 1 : null,
        errorMessage: message,
        repeatMode: playbackState.value.repeatMode,
        shuffleMode: _player.shuffleModeEnabled
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
        queueIndex: event?.currentIndex ?? _player.currentIndex,
      ),
    );
  }

  AudioProcessingState _mapProcessing(ProcessingState state) {
    switch (state) {
      case ProcessingState.idle:
        return AudioProcessingState.idle;
      case ProcessingState.loading:
        return AudioProcessingState.loading;
      case ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
    }
  }

  void _publishQueue() {
    if (_disposed) return;
    final items = <MediaItem>[];
    for (final source in _player.sequenceState.sequence) {
      final item = _mediaItemFor(source);
      if (item != null) items.add(item);
    }
    queue.add(List<MediaItem>.unmodifiable(items));
  }

  void _publishMediaItem() {
    if (_disposed) return;
    mediaItem.add(_mediaItemFor(_player.sequenceState.currentSource));
  }

  MediaItem? _mediaItemFor(IndexedAudioSource? source) {
    final item = source?.tag;
    if (item is! MusicItem || item.videoId == null) return null;
    // Prefer the URI captured when the queue was built so a later proxy change
    // cannot rewrite the identity of an already-queued track.
    final id = source is UriAudioSource
        ? source.uri.toString()
        : _api.streamUri(item.videoId!).toString();
    final thumbnail = item.thumbnail;
    return MediaItem(
      id: id,
      title: item.title,
      artist: item.artist.isEmpty ? null : item.artist,
      artUri: (thumbnail != null && thumbnail.isNotEmpty)
          ? Uri.tryParse(thumbnail)
          : null,
      // Use the real probed duration when available; the source listing often
      // has none, and the seek bar needs a duration to render.
      duration: _player.duration ?? _parseDuration(item.duration),
      extras: <String, dynamic>{'videoId': item.videoId},
    );
  }

  void _publishError(String message) {
    if (_disposed) return;
    error.value = message;
    // Re-broadcast so the error code/message and controls update.
    _publishPlaybackState();
  }

  bool _sameTrack(MusicItem a, MusicItem b) {
    final aId = a.videoId;
    final bId = b.videoId;
    if (aId != null && bId != null) return aId == bId;
    return identical(a, b);
  }

  String _trackKey(MusicItem item) => item.videoId ?? item.title;

  String _describe(PlayerException exception) {
    final message = exception.message;
    return (message == null || message.isEmpty)
        ? 'Playback error (code ${exception.code})'
        : message;
  }

  @override
  Future<void> play() async {
    // AudioPlayer.play()'s future completes only at pause/stop/end, so it must
    // not be awaited; _startPlayback reports failures via the error notifier.
    _startPlayback();
  }

  @override
  Future<void> pause() async {
    if (_disposed) return;
    await _player.pause();
  }

  @override
  Future<void> seek(Duration position) async {
    if (_disposed) return;
    await _player.seek(position);
  }

  @override
  Future<void> skipToNext() async {
    if (_disposed) return;
    if (_player.hasNext) {
      await _player.seekToNext();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_disposed) return;
    if (_player.hasPrevious) {
      await _player.seekToPrevious();
    }
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (_disposed) return;
    final sequence = _player.sequenceState.sequence;
    if (index < 0 || index >= sequence.length) return;
    await _player.seek(Duration.zero, index: index);
  }

  @override
  Future<void> stop() async {
    if (_disposed) return;
    // Invalidate any queued or in-flight playItems so a pending load cannot
    // start playback after the user has stopped.
    _generation++;
    await _player.stop();
    // Drop the applied queue so a later proxy change is never reused with
    // stale stream URLs; the next playItems rebuilds everything.
    _signature = const <String>[];
    queue.add(const <MediaItem>[]);
    mediaItem.add(null);
    await super.stop();
  }

  /// Releases the player, subscriptions, and streams.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _sub?.cancel();
    await _stateSub?.cancel();
    await _durationSub?.cancel();
    await _positionSub?.cancel();
    await _errorSub?.cancel();
    await _interruptionSub?.cancel();
    await _noisySub?.cancel();
    await _player.dispose();
    await _positionController.close();
    error.dispose();
  }

  static Duration? _parseDuration(String? value) {
    if (value == null) return null;
    final parts = value.split(':');
    if (parts.length < 2 || parts.length > 3) return null;
    final seconds = <int>[];
    for (final part in parts) {
      final parsed = int.tryParse(part.trim());
      if (parsed == null || parsed < 0) return null;
      seconds.add(parsed);
    }
    Duration duration = Duration.zero;
    for (final part in seconds) {
      duration = duration * 60 + Duration(seconds: part);
    }
    return duration;
  }
}
