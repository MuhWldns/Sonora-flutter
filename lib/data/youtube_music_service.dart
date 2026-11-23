library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'music_models.dart';

/// Item cache stream URL direct dari YouTube CDN (GoogleVideo).
class _CachedStream {
  const _CachedStream({required this.uri, required this.expiresAt});

  final Uri uri;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// Layanan mandiri YouTube Music ala BitChord.
///
/// Berjalan langsung dari perangkat klien tanpa membutuhkan proxy server VPS.
/// Mengambil stream audio dengan bitrate tertinggi langsung dari CDN YouTube
/// (GoogleVideo) dan menangani pencarian audio mandiri.
class YouTubeMusicService {
  YouTubeMusicService({YoutubeExplode? client})
      : _yt = client ?? YoutubeExplode();

  final YoutubeExplode _yt;
  final Map<String, _CachedStream> _streamCache = <String, _CachedStream>{};
  bool _disposed = false;

  /// Masa aktif cache URL stream (token googlevideo valid ~4-6 jam).
  static const Duration _cacheTtl = Duration(hours: 4);

  /// Mengambil direct stream URI dengan bitrate audio tertinggi.
  ///
  /// Mengembalikan `null` jika resolusi gagal agar pemanggil dapat melakukan fallback.
  Future<Uri?> resolveStreamUri(String videoId) async {
    if (_disposed || videoId.isEmpty) return null;

    final _CachedStream? cached = _streamCache[videoId];
    if (cached != null && !cached.isExpired) {
      return cached.uri;
    }

    try {
      final StreamManifest manifest =
          await _yt.videos.streamsClient.getManifest(videoId);
      // Hierarki prioritas format audio:
      // 1. Prioritaskan AAC/M4A (itag 140 / mp4) untuk kompatibilitas durasi dan seeking presisi di Android Media3.
      // 2. Fallback ke audioOnly bitrate tertinggi (misal Opus/WebM itag 251, ~160 kbps).
      // 3. Fallback terakhir ke muxed MP4 jika audioOnly kosong sama sekali.
      AudioStreamInfo? chosenAudio;
      final Iterable<AudioStreamInfo> aacStreams = manifest.audioOnly.where(
        (AudioStreamInfo s) =>
            s.container.name.toLowerCase() == 'mp4' ||
            s.audioCodec.toLowerCase().contains('mp4a') ||
            s.tag == 140,
      );
      if (aacStreams.isNotEmpty) {
        chosenAudio = aacStreams.withHighestBitrate();
      } else if (manifest.audioOnly.isNotEmpty) {
        chosenAudio = manifest.audioOnly.withHighestBitrate();
      }

      final StreamInfo stream = chosenAudio ??
          (manifest.muxed.isNotEmpty
              ? manifest.muxed.withHighestBitrate()
              : manifest.streams.first);

      final Uri uri = stream.url;
      _streamCache[videoId] = _CachedStream(
        uri: uri,
        expiresAt: DateTime.now().add(_cacheTtl),
      );
      return uri;
    } catch (e) {
      debugPrint('[YouTubeMusicService] Resolusi stream $videoId gagal: $e');
      return null;
    }
  }

  /// Melakukan pencarian lagu langsung dari YouTube tanpa perantara server.
  Future<List<MusicItem>> search(String query) async {
    if (_disposed || query.trim().isEmpty) return const <MusicItem>[];

    try {
      final VideoSearchList results = await _yt.search.search(query.trim());
      final List<MusicItem> items = <MusicItem>[];

      for (final Video video in results) {
        final String thumbnail = video.thumbnails.highResUrl.isNotEmpty
            ? video.thumbnails.highResUrl
            : video.thumbnails.standardResUrl;
        items.add(
          MusicItem(
            type: 'song',
            title: video.title,
            artist: video.author,
            subtitle: video.author,
            thumbnail: thumbnail,
            videoId: video.id.value,
            duration: _formatDuration(video.duration),
          ),
        );
      }
      return items;
    } catch (e) {
      debugPrint('[YouTubeMusicService] Pencarian "$query" gagal: $e');
      return const <MusicItem>[];
    }
  }

  /// Mengambil daftar lagu populer/trending langsung dari YouTube untuk feed beranda.
  Future<List<MusicItem>> getTrending() async {
    return search('Top Music Hits 2026');
  }

  static String? _formatDuration(Duration? duration) {
    if (duration == null || duration <= Duration.zero) return null;
    final int total = duration.inSeconds;
    final int h = total ~/ 3600;
    final int m = (total % 3600) ~/ 60;
    final int s = total % 60;
    final String mm = h > 0 ? m.toString().padLeft(2, '0') : '$m';
    final String ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  /// Menutup koneksi klien.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _streamCache.clear();
    _yt.close();
  }
}
