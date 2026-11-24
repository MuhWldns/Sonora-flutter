library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'music_models.dart';

/// Item cache stream URL direct dari YouTube CDN (GoogleVideo).
class _CachedStream {
  const _CachedStream({required this.uri, required this.expiresAt});

  final Uri uri;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// Layanan mandiri YouTube Music langsung dari klien.
///
/// Berjalan langsung dari perangkat klien tanpa membutuhkan proxy server VPS.
/// Mengambil stream audio dengan bitrate tertinggi langsung dari CDN YouTube
/// (GoogleVideo) dan menangani pencarian audio mandiri.
class YouTubeMusicService {
  YouTubeMusicService({YoutubeExplode? client, http.Client? httpClient})
      : _yt = client ?? YoutubeExplode(),
        _http = httpClient ?? http.Client();

  final YoutubeExplode _yt;
  final http.Client _http;
  final Map<String, _CachedStream> _streamCache = <String, _CachedStream>{};
  bool _disposed = false;

  /// Masa aktif cache URL stream (token googlevideo valid ~4-6 jam).
  static const Duration _cacheTtl = Duration(hours: 4);

  /// User-Agent yang sama dengan yang dikirim ExoPlayer saat memutar stream.
  static const String _playerUserAgent =
      'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip';

  /// Endpoint innertube untuk pencarian langsung (tanpa parser library yang
  /// masih crash pada beberapa bentuk respons).
  static const String _searchEndpoint =
      'https://www.youtube.com/youtubei/v1/search';
  static const String _innertubeKey = 'AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8';
  static const int _maxSearchResults = 30;

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
      // Client default di master (androidSdkless) menghasilkan URL yang valid,
      // TAPI googlevideo bisa menolak unduhan penuh (403) untuk format
      // audio-only tertentu, meski range kecil tetap 206. Setiap kandidat
      // divalidasi dulu dengan GET tanpa Range (pola request pertama ExoPlayer).
      final StreamManifest manifest =
          await _yt.videos.streamsClient.getManifest(videoId);

      // Hierarki prioritas format:
      // 1. AAC/M4A (itag 140 / mp4) untuk kompatibilitas durasi dan seeking presisi di Android Media3.
      // 2. audioOnly bitrate tertinggi (misal Opus/WebM itag 251, ~160 kbps).
      // 3. Fallback terakhir ke muxed MP4 (paling stabil dapat diakses).
      final List<AudioStreamInfo> aacStreams = manifest.audioOnly
          .where(
            (AudioStreamInfo s) =>
                s.container.name.toLowerCase() == 'mp4' ||
                s.audioCodec.toLowerCase().contains('mp4a') ||
                s.tag == 140,
          )
          .toList()
        ..sort(
            (AudioStreamInfo a, AudioStreamInfo b) => b.bitrate.compareTo(a.bitrate));
      final List<AudioStreamInfo> otherAudioStreams = manifest.audioOnly
          .where((AudioStreamInfo s) => !aacStreams.contains(s))
          .toList()
        ..sort(
            (AudioStreamInfo a, AudioStreamInfo b) => b.bitrate.compareTo(a.bitrate));
      final List<MuxedStreamInfo> muxedStreams = manifest.muxed.toList()
        ..sort((MuxedStreamInfo a, MuxedStreamInfo b) =>
            b.bitrate.compareTo(a.bitrate));

      final List<StreamInfo> candidates = <StreamInfo>[
        ...aacStreams,
        ...otherAudioStreams,
        ...muxedStreams,
      ];

      for (final StreamInfo stream in candidates) {
        if (!await _streamUsable(stream.url)) continue;
        final Uri uri = stream.url;
        _streamCache[videoId] = _CachedStream(
          uri: uri,
          expiresAt: DateTime.now().add(_cacheTtl),
        );
        return uri;
      }
      debugPrint('[YouTubeMusicService] Tidak ada stream $videoId yang lolos uji akses.');
      return null;
    } catch (e) {
      debugPrint('[YouTubeMusicService] Resolusi stream $videoId gagal: $e');
      return null;
    }
  }

  /// Melakukan pencarian lagu langsung dari YouTube tanpa perantara server.
  ///
  /// Memakai innertube API secara langsung dengan parsing defensif. Parser
  /// search bawaan youtube_explode masih crash pada beberapa bentuk respons
  /// (int.parse "Streamed ..." dan getT pada viewCountText berbentuk runs).
  Future<List<MusicItem>> search(String query) async {
    final String q = query.trim();
    if (_disposed || q.isEmpty) return const <MusicItem>[];

    try {
      final Uri uri =
          Uri.parse('$_searchEndpoint?key=$_innertubeKey&prettyPrint=false');
      final http.Response response = await _http
          .post(
            uri,
            headers: const <String, String>{
              'content-type': 'application/json; charset=utf-8',
              'user-agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            },
            body: jsonEncode(<String, dynamic>{
              'context': <String, dynamic>{
                'client': <String, dynamic>{
                  'clientName': 'WEB',
                  'clientVersion': '2.20250331.00.00',
                  'browserName': 'Chrome',
                  'browserVersion': '120.0.0.0',
                  'clientFormFactor': 'UNKNOWN_FORM_FACTOR',
                  'hl': 'en',
                  'gl': 'US',
                },
              },
              'query': q,
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        throw StateError('status ${response.statusCode}');
      }

      final dynamic root = jsonDecode(utf8.decode(response.bodyBytes));
      final List<MusicItem> items = <MusicItem>[];
      _collectVideoRenderers(root, items);
      return items;
    } catch (e) {
      debugPrint('[YouTubeMusicService] Pencarian "$query" gagal: $e');
      return const <MusicItem>[];
    }
  }

  /// Menelusuri seluruh pohon respons innertube dan mengumpulkan setiap
  /// videoRenderer yang valid. Tidak bergantung pada struktur sarang tertentu.
  static void _collectVideoRenderers(dynamic node, List<MusicItem> out) {
    if (out.length >= _maxSearchResults) return;
    if (node is Map<dynamic, dynamic>) {
      final dynamic renderer = node['videoRenderer'];
      if (renderer is Map<dynamic, dynamic>) {
        final MusicItem? item = _musicItemFromRenderer(renderer);
        if (item != null) out.add(item);
      }
      for (final dynamic child in node.values) {
        _collectVideoRenderers(child, out);
        if (out.length >= _maxSearchResults) return;
      }
    } else if (node is List<dynamic>) {
      for (final dynamic child in node) {
        _collectVideoRenderers(child, out);
        if (out.length >= _maxSearchResults) return;
      }
    }
  }

  /// Memetakan videoRenderer innertube menjadi MusicItem tanpa operasi yang
  /// bisa melempar exception (tanpa int.parse, tanpa cast keras).
  static MusicItem? _musicItemFromRenderer(Map<dynamic, dynamic> renderer) {
    final String? videoId = _plainText(renderer['videoId']);
    if (videoId == null || videoId.isEmpty) return null;

    final String title = _runsText(renderer['title']) ?? '';
    if (title.isEmpty) return null;

    final String author = _runsText(renderer['ownerText']) ??
        _runsText(renderer['longBylineText']) ??
        '';

    String? duration = _runsText(renderer['lengthText']);
    if (duration != null && (duration.isEmpty || duration == 'LIVE')) {
      duration = null;
    }

    String thumbnail = '';
    final dynamic thumbnails =
        (renderer['thumbnail'] as Map<dynamic, dynamic>?)?['thumbnails'];
    if (thumbnails is List<dynamic> && thumbnails.isNotEmpty) {
      final dynamic last = thumbnails.last;
      if (last is Map<dynamic, dynamic>) {
        final dynamic url = last['url'];
        if (url is String && url.isNotEmpty) {
          thumbnail = url.startsWith('//') ? 'https:$url' : url;
        }
      }
    }

    return MusicItem(
      type: 'song',
      title: title,
      artist: author,
      subtitle: author,
      thumbnail: thumbnail,
      videoId: videoId,
      duration: duration,
    );
  }

  static String? _plainText(dynamic value) => value is String ? value : null;

  /// Mengambil teks dari node `{runs: [{text: ...}]}` atau `{simpleText: ...}`;
  /// mengembalikan null bila bentuknya tidak dikenal.
  static String? _runsText(dynamic node) {
    if (node is! Map<dynamic, dynamic>) return null;
    final dynamic runs = node['runs'];
    if (runs is List<dynamic> && runs.isNotEmpty) {
      final dynamic first = runs.first;
      if (first is Map<dynamic, dynamic>) {
        final dynamic text = first['text'];
        if (text is String) return text;
      }
    }
    final dynamic simple = node['simpleText'];
    return simple is String ? simple : null;
  }

  /// Menguji URL stream dengan GET tanpa header Range — pola yang sama dengan
  /// request pertama ExoPlayer. Body tidak dibaca (koneksi langsung diputus)
  /// agar tidak ikut mengunduh isi file.
  Future<bool> _streamUsable(Uri url) async {
    if (_disposed) return false;
    final http.Client probeClient = http.Client();
    try {
      final http.StreamedResponse response = await probeClient
          .send(
            http.Request('GET', url)..headers['user-agent'] = _playerUserAgent,
          )
          .timeout(const Duration(seconds: 10));
      final int status = response.statusCode;
      return status >= 200 && status < 400;
    } catch (e) {
      return false;
    } finally {
      probeClient.close();
    }
  }

  /// Mengambil daftar lagu populer/trending langsung dari YouTube untuk feed beranda.
  Future<List<MusicItem>> getTrending() async {
    return search('Top Music Hits 2026');
  }

  /// Mengambil koleksi lagu untuk album, playlist, atau artis secara mandiri.
  ///
  /// Bila [browseId] merupakan playlist ID (mis. diawali `VL`, `PL`, `RD`), trek
  /// diambil langsung dari playlist YouTube (dibatasi 50 trek untuk efisiensi memori).
  /// Bila gagal atau bukan playlist ID, dilakukan pencarian lagu relevan via [title] / [browseId].
  Future<List<MusicSection>> browse(
    String browseId, {
    String? title,
    String? type,
    int limit = 50,
  }) async {
    if (_disposed || browseId.trim().isEmpty) return const <MusicSection>[];

    final String cleanId = browseId.startsWith('VL')
        ? browseId.substring(2)
        : browseId.trim();

    // 1. Coba ambil dari YouTube playlist bila ID valid.
    try {
      final Stream<Video> videoStream = _yt.playlists.getVideos(cleanId);
      final List<MusicItem> items = <MusicItem>[];
      await for (final Video video in videoStream.take(limit)) {
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
      if (items.isNotEmpty) {
        return <MusicSection>[
          MusicSection(
            title: title != null && title.isNotEmpty ? title : 'Daftar Lagu',
            items: items,
          ),
        ];
      }
    } catch (_) {
      // Abaikan galat dan lanjutkan ke fallback pencarian judul/artis.
    }

    // 2. Fallback: cari lagu berdasarkan nama judul / artis / album.
    final String query = (title != null && title.trim().isNotEmpty)
        ? title.trim()
        : cleanId;
    final List<MusicItem> searchResults = await search(query);
    if (searchResults.isNotEmpty) {
      return <MusicSection>[
        MusicSection(
          title: title != null && title.isNotEmpty ? title : 'Daftar Lagu',
          items: searchResults,
        ),
      ];
    }

    return const <MusicSection>[];
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
    _http.close();
  }
}
