library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'music_models.dart';
import 'youtube_session.dart';

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

  /// Penyedia sesi aktif untuk request terotorisasi (disetel dari bootstrap).
  Future<YoutubeSession?> Function()? _sessionProvider;
  set sessionProvider(Future<YoutubeSession?> Function()? provider) =>
      _sessionProvider = provider;

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

  /// Basis endpoint innertube YouTube Music (klien WEB_REMIX).
  static const String _musicInnertubeBase =
      'https://music.youtube.com/youtubei/v1/';
  static const String _remixClientName = 'WEB_REMIX';

  /// Versi klien cadangan saat request dikirim tanpa sesi aktif.
  static const String _fallbackRemixClientVersion = '1.20250331.01.00';
  static const String _musicHl = 'en';
  static const String _musicGl = 'US';
  static const int _maxLibraryResults = 100;
  static const Duration _musicRequestTimeout = Duration(seconds: 20);

  /// Browse ID feed beranda YouTube Music untuk sesi masuk.
  static const String _homeBrowseId = 'FEmusic_home';

  /// Batas jumlah rak beranda dan item per rak agar feed tetap ringan.
  static const int _maxHomeShelves = 10;
  static const int _maxHomeItemsPerShelf = 30;

  /// Judul pengganti rak beranda tanpa judul (mengikuti YouTube Music).
  static const String _homeDefaultShelfTitle = 'For you';

  /// User-Agent peramban untuk request innertube langsung.
  static const String _browserUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  /// Mengambil direct stream URI sesuai preferensi [quality].
  ///
  /// Mengembalikan `null` jika resolusi gagal agar pemanggil dapat melakukan fallback.
  Future<Uri?> resolveStreamUri(
    String videoId, {
    AudioQuality quality = AudioQuality.auto,
  }) async {
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

      final List<StreamInfo> candidates = _orderCandidates(manifest, quality);

      // Uji seluruh kandidat secara paralel agar lagu cepat mulai; urutan
      // preferensi tetap dipakai saat memilih kandidat pertama yang lolos.
      final List<bool> usable = await Future.wait(
        candidates.map((StreamInfo stream) => _streamUsable(stream.url)),
      );
      for (var i = 0; i < candidates.length; i++) {
        if (!usable[i]) continue;
        final Uri uri = candidates[i].url;
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

  /// Mengurutkan kandidat stream sesuai preferensi kualitas [quality].
  ///
  /// Semua kandidat tetap melewati uji akses (`_streamUsable`) di pemanggil;
  /// urutan hanya menentukan format mana yang dicoba lebih dulu.
  static List<StreamInfo> _orderCandidates(
    StreamManifest manifest,
    AudioQuality quality,
  ) {
    final List<AudioStreamInfo> audioOnly = manifest.audioOnly.toList();
    final List<MuxedStreamInfo> muxed = manifest.muxed.toList();
    switch (quality) {
      case AudioQuality.best:
        // Bitrate tertinggi dulu tanpa memandang codec, lalu muxed.
        audioOnly.sort(
            (AudioStreamInfo a, AudioStreamInfo b) => b.bitrate.compareTo(a.bitrate));
        muxed.sort((MuxedStreamInfo a, MuxedStreamInfo b) =>
            b.bitrate.compareTo(a.bitrate));
        return <StreamInfo>[...audioOnly, ...muxed];
      case AudioQuality.hemat:
        // Bitrate terendah dulu untuk menghemat kuota data.
        audioOnly.sort(
            (AudioStreamInfo a, AudioStreamInfo b) => a.bitrate.compareTo(b.bitrate));
        muxed.sort((MuxedStreamInfo a, MuxedStreamInfo b) =>
            a.bitrate.compareTo(b.bitrate));
        return <StreamInfo>[...audioOnly, ...muxed];
      case AudioQuality.auto:
        // AAC/M4A (itag 140 / mp4) untuk presisi seeking Media3, lalu
        // audio-only lain (Opus/WebM), terakhir muxed MP4.
        final List<AudioStreamInfo> aac = audioOnly
            .where(
              (AudioStreamInfo s) =>
                  s.container.name.toLowerCase() == 'mp4' ||
                  s.audioCodec.toLowerCase().contains('mp4a') ||
                  s.tag == 140,
            )
            .toList()
          ..sort((AudioStreamInfo a, AudioStreamInfo b) =>
              b.bitrate.compareTo(a.bitrate));
        final List<AudioStreamInfo> other = audioOnly
            .where((AudioStreamInfo s) => !aac.contains(s))
            .toList()
          ..sort((AudioStreamInfo a, AudioStreamInfo b) =>
              b.bitrate.compareTo(a.bitrate));
        muxed.sort((MuxedStreamInfo a, MuxedStreamInfo b) =>
            b.bitrate.compareTo(a.bitrate));
        return <StreamInfo>[...aac, ...other, ...muxed];
    }
  }

  /// Melakukan pencarian lagu langsung dari YouTube tanpa perantara server.
  ///
  /// Saat sesi YouTube Music aktif, pencarian dikirim ke innertube
  /// music.youtube.com (klien WEB_REMIX, bercookie) agar hasil
  /// terpersonalisasi; setiap kegagalan (status bukan 200, respons tak
  /// terbaca, atau exception) jatuh kembali ke jalur anonim www.youtube.com
  /// di bawah. Tanpa sesi, perilaku sama persis dengan jalur anonim lama.
  ///
  /// Memakai innertube API secara langsung dengan parsing defensif. Parser
  /// search bawaan youtube_explode masih crash pada beberapa bentuk respons
  /// (int.parse "Streamed ..." dan getT pada viewCountText berbentuk runs).
  Future<List<MusicItem>> search(String query) async {
    final String q = query.trim();
    if (_disposed || q.isEmpty) return const <MusicItem>[];

    try {
      final YoutubeSession? session = await _sessionProvider?.call();
      if (session != null) {
        final List<MusicItem>? signedIn = await _searchSignedIn(q, session);
        if (signedIn != null) return signedIn;
        // Gagal → lanjut ke pencarian anonim di bawah.
      }
    } catch (e) {
      debugPrint('[YouTubeMusicService] Sesi pencarian gagal: $e');
    }

    try {
      final Uri uri =
          Uri.parse('$_searchEndpoint?key=$_innertubeKey&prettyPrint=false');
      final http.Response response = await _http
          .post(
            uri,
            headers: const <String, String>{
              'content-type': 'application/json; charset=utf-8',
              'user-agent': _browserUserAgent,
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

  /// Pencarian terotorisasi via music.youtube.com (WEB_REMIX + cookie).
  ///
  /// Mengembalikan `null` bila gagal atau hasil kosong agar pemanggil jatuh
  /// ke jalur anonim; query sah yang berhasil diparse tidak mungkin nihil.
  Future<List<MusicItem>?> _searchSignedIn(
    String query,
    YoutubeSession session,
  ) async {
    try {
      final http.Response response = await _postMusicInnertube(
        'search',
        <String, dynamic>{'query': query},
        session: session,
      );
      if (response.statusCode != 200) {
        debugPrint(
          '[YouTubeMusicService] Pencarian sesi masuk ditolak: '
          'HTTP ${response.statusCode}',
        );
        return null;
      }
      final dynamic root = jsonDecode(utf8.decode(response.bodyBytes));
      final List<MusicItem> items = <MusicItem>[];
      _collectMusicRenderers(root, items);
      if (items.isEmpty) return null;
      return items.take(_maxSearchResults).toList(growable: false);
    } catch (e) {
      debugPrint('[YouTubeMusicService] Pencarian sesi masuk gagal: $e');
      return null;
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
          .timeout(const Duration(seconds: 6));
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

  /// Mengirim POST `account/account_menu` untuk [session] (atau sesi aktif).
  ///
  /// Mengembalikan `null` bila layanan sudah ditutup atau request gagal.
  Future<http.Response?> _postAccountMenu({YoutubeSession? session}) async {
    if (_disposed) return null;
    try {
      return await _postMusicInnertube(
        'account/account_menu',
        const <String, dynamic>{},
        session: session,
      );
    } catch (e) {
      debugPrint('[YouTubeMusicService] Gagal memanggil account_menu: $e');
      return null;
    }
  }

  /// Memvalidasi sesi YouTube Music lewat status HTTP `account_menu`.
  ///
  /// Validasi berbasis status (HTTP 200 = sesi aktif) dan tidak bergantung
  /// pada isi respons, sehingga perubahan bentuk JSON dari Google tidak
  /// membuat cookie yang masih valid ditolak.
  Future<bool> validateSession({YoutubeSession? session}) async {
    final http.Response? response = await _postAccountMenu(session: session);
    if (response == null) return false;
    if (response.statusCode != 200) {
      // Diagnostik aman: hanya kode status, tanpa isi respons atau header.
      debugPrint(
        '[YouTubeMusicService] Validasi sesi ditolak: '
        'HTTP ${response.statusCode}',
      );
      return false;
    }
    return true;
  }

  /// Mengambil nama akun YouTube Music yang sedang masuk.
  ///
  /// [session] opsional dipakai untuk permintaan kandidat sesi. Nama akun
  /// hanya pelengkap tampilan; kegagalan membacanya bukan tanda sesi
  /// invalid. Mengembalikan `null` bila gagal atau belum masuk.
  Future<String?> fetchAccountName({YoutubeSession? session}) async {
    final AccountInfo? info = await fetchAccountInfo(session: session);
    if (info == null || info.name.isEmpty) return null;
    return info.name;
  }

  /// Mengambil informasi profil akun YouTube Music yang sedang masuk.
  ///
  /// Memakai respons `account_menu` yang sama dengan [fetchAccountName]:
  /// nama dari logika penelusuran yang sama, email dari
  /// `accountItemRenderer.email`, dan avatar dari thumbnail foto akun
  /// (thumbnail terbesar yang dipilih). Field yang tidak ditemukan
  /// bernilai `null`; metode ini tidak pernah melempar exception dan
  /// mengembalikan `null` bila request gagal atau status bukan 200.
  Future<AccountInfo?> fetchAccountInfo({YoutubeSession? session}) async {
    final http.Response? response = await _postAccountMenu(session: session);
    if (response == null || response.statusCode != 200) return null;
    try {
      final dynamic root = jsonDecode(utf8.decode(response.bodyBytes));
      return AccountInfo(
        name: _findAccountName(root) ?? '',
        email: _findAccountEmail(root),
        avatarUrl: _findAccountAvatarUrl(root),
      );
    } catch (e) {
      debugPrint('[YouTubeMusicService] Gagal membaca info akun: $e');
      return null;
    }
  }

  /// Mengambil daftar video yang disukai dari akun YouTube Music.
  ///
  /// Daftar kosong dikembalikan bila gagal atau belum masuk — fitur ini
  /// opsional dan tidak boleh membuat UI error.
  Future<List<MusicItem>> fetchLiked() =>
      _fetchAccountBrowse('FEmusic_liked_videos');

  /// Mengambil riwayat putar dari akun YouTube Music.
  Future<List<MusicItem>> fetchHistory() =>
      _fetchAccountBrowse('FEmusic_history');

  /// Menyukai video memakai endpoint `like/like`.
  ///
  /// Mengembalikan `true` bila server menerima request.
  Future<bool> likeVideo(String videoId) async {
    final String id = videoId.trim();
    if (_disposed || id.isEmpty) return false;
    try {
      final http.Response response = await _postMusicInnertube(
        'like/like',
        <String, dynamic>{
          'target': <String, dynamic>{'videoId': id},
          'action': 'like/like',
        },
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[YouTubeMusicService] Gagal menyukai $id: $e');
      return false;
    }
  }

  /// Membuat playlist pribadi baru memakai endpoint `playlist/create`.
  Future<bool> createPlaylist(String title) async {
    final String cleanTitle = title.trim();
    if (_disposed || cleanTitle.isEmpty) return false;
    try {
      final http.Response response = await _postMusicInnertube(
        'playlist/create',
        <String, dynamic>{
          'title': cleanTitle,
          'privacyStatus': 'PRIVATE',
        },
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[YouTubeMusicService] Gagal membuat playlist: $e');
      return false;
    }
  }

  /// Mengirim POST innertube YouTube Music dengan header sesi bila ada.
  ///
  /// Tanpa sesi aktif, request tetap dikirim sebagai pengguna anonim tanpa
  /// Cookie/Authorization. Header mengikuti pola BitChord (Innertube.kt):
  /// SAPISIDHASH per request, X-YouTube-Client-Name 67 (WEB_REMIX), serta
  /// X-Goog-Visitor-Id/AuthUser/PageId dari ytcfg.
  Future<http.Response> _postMusicInnertube(
    String endpoint,
    Map<String, dynamic> payload, {
    YoutubeSession? session,
  }) async {
    final YoutubeSession? active = session ?? await _sessionProvider?.call();
    final int timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final String? sapisid =
        active == null ? null : YoutubeSession.sapisidFromCookie(active.cookie);
    final Uri uri = Uri.parse('$_musicInnertubeBase$endpoint').replace(
      queryParameters: <String, String>{
        'prettyPrint': 'false',
        'hl': _musicHl,
      },
    );
    final Map<String, dynamic> body = <String, dynamic>{
      'context': <String, dynamic>{
        'client': <String, dynamic>{
          'clientName': _remixClientName,
          'clientVersion': active?.clientVersion ?? _fallbackRemixClientVersion,
          'hl': _musicHl,
          'gl': _musicGl,
        },
        if (active != null && active.dataSyncId.isNotEmpty)
          'user': <String, dynamic>{
            // DATASYNC_ID dari ytcfg berformat "<id>||<timestamp>".
            // Google menjawab HTTP 500 bila nilai lengkap (dengan "||")
            // dikirim sebagai onBehalfOfUser — hanya bagian sebelum "||"
            // yang valid (mengikuti perilaku klien web/BitChord).
            'onBehalfOfUser': active.dataSyncId.split('||').first,
          },
      },
      ...payload,
    };
    final Map<String, String> headers = <String, String>{
      'content-type': 'application/json; charset=utf-8',
      'user-agent': _browserUserAgent,
      'x-origin': youtubeMusicOrigin,
      'origin': youtubeMusicOrigin,
      'referer': '$youtubeMusicOrigin/',
      'x-youtube-client-name': '67',
      'x-youtube-client-version':
          active?.clientVersion ?? _fallbackRemixClientVersion,
      if (active != null) ...<String, String>{
        'x-goog-visitor-id': active.visitorData,
        // BitChord selalu mengirim indeks akun; "0" adalah default yang
        // aman bila probe ytcfg gagal membaca SESSION_INDEX.
        'x-goog-authuser': active.authUser.isNotEmpty ? active.authUser : '0',
        if (active.pageId != null && active.pageId!.isNotEmpty)
          'x-goog-pageid': active.pageId!,
        'cookie': active.cookie,
        if (sapisid != null)
          'authorization':
              'SAPISIDHASH ${timestamp}_${sapisidHash(sapisid, youtubeMusicOrigin, timestamp)}',
      },
    };
    return _http
        .post(uri, headers: headers, body: jsonEncode(body))
        .timeout(_musicRequestTimeout);
  }

  /// Mengambil isi koleksi akun (disukai/riwayat) lewat endpoint browse.
  Future<List<MusicItem>> _fetchAccountBrowse(String browseId) async {
    if (_disposed) return const <MusicItem>[];
    try {
      final http.Response response = await _postMusicInnertube(
        'browse',
        <String, dynamic>{'browseId': browseId},
      );
      if (response.statusCode != 200) return const <MusicItem>[];
      final dynamic root = jsonDecode(utf8.decode(response.bodyBytes));
      final List<MusicItem> items = <MusicItem>[];
      _collectMusicRenderers(root, items);
      return items;
    } catch (e) {
      debugPrint('[YouTubeMusicService] Gagal mengambil $browseId: $e');
      return const <MusicItem>[];
    }
  }

  /// Mengambil rak-rak beranda personal YouTube Music (browse FEmusic_home).
  ///
  /// Hanya aktif saat sesi masuk; mengembalikan daftar kosong bila belum
  /// masuk, request gagal, atau respons tidak dikenali. Fitur ini opsional
  /// dan tidak boleh membuat layar Home error.
  Future<List<MusicSection>> fetchHomeSections() async {
    if (_disposed) return const <MusicSection>[];
    try {
      final YoutubeSession? session = await _sessionProvider?.call();
      if (session == null) return const <MusicSection>[];
      final http.Response response = await _postMusicInnertube(
        'browse',
        <String, dynamic>{'browseId': _homeBrowseId},
        session: session,
      );
      if (response.statusCode != 200) {
        debugPrint(
          '[YouTubeMusicService] Beranda ditolak: HTTP ${response.statusCode}',
        );
        return const <MusicSection>[];
      }
      final dynamic root = jsonDecode(utf8.decode(response.bodyBytes));
      return _parseHomeSections(root);
    } catch (e) {
      debugPrint('[YouTubeMusicService] Gagal mengambil beranda: $e');
      return const <MusicSection>[];
    }
  }

  /// Memarsek respons browse FEmusic_home menjadi rak-rak berjudul.
  ///
  /// Jalur renderer (pola BitChord): contents.singleColumnBrowseResults
  /// Renderer.tabs[0].tabRenderer.content.sectionListRenderer.contents[].
  /// Tiap entri berupa musicCarouselShelfRenderer (kartu dua baris) atau
  /// musicShelfRenderer (baris responsif). Bentuk tak dikenal dan rak kosong
  /// dilewati; jumlah rak dan item per rak dibatasi agar feed ringan.
  static List<MusicSection> _parseHomeSections(dynamic root) {
    final Map<dynamic, dynamic>? rootMap = _asMap(root);
    final Map<dynamic, dynamic>? contents = _asMap(rootMap?['contents']);
    final Map<dynamic, dynamic>? singleColumn =
        _asMap(contents?['singleColumnBrowseResultsRenderer']);
    final List<dynamic>? tabs = _asList(singleColumn?['tabs']);
    if (tabs == null || tabs.isEmpty) return const <MusicSection>[];
    final Map<dynamic, dynamic>? tabRenderer =
        _asMap(_asMap(tabs.first)?['tabRenderer']);
    final Map<dynamic, dynamic>? sectionList = _asMap(
      _asMap(tabRenderer?['content'])?['sectionListRenderer'],
    );
    final List<dynamic>? shelfNodes = _asList(sectionList?['contents']);
    if (shelfNodes == null) return const <MusicSection>[];

    final List<MusicSection> shelves = <MusicSection>[];
    for (final dynamic node in shelfNodes) {
      if (shelves.length >= _maxHomeShelves) break;
      final Map<dynamic, dynamic>? shelfMap = _asMap(node);
      if (shelfMap == null) continue;
      final Map<dynamic, dynamic>? carousel =
          _asMap(shelfMap['musicCarouselShelfRenderer']);
      final Map<dynamic, dynamic>? plain =
          _asMap(shelfMap['musicShelfRenderer']);
      final Map<dynamic, dynamic>? shelf = carousel ?? plain;
      if (shelf == null) continue;

      // Judul rak: header carousel (musicCarouselShelfBasicHeaderRenderer)
      // atau field title langsung pada musicShelfRenderer.
      String title = carousel != null
          ? _runsText(
              _asMap(_asMap(carousel['header'])
                  ?['musicCarouselShelfBasicHeaderRenderer'])?['title'],
            ) ??
            ''
          : _runsText(plain!['title']) ?? '';
      if (title.trim().isEmpty) title = _homeDefaultShelfTitle;

      final List<dynamic>? itemNodes = _asList(shelf['contents']);
      if (itemNodes == null || itemNodes.isEmpty) continue;
      final List<MusicItem> items = <MusicItem>[];
      for (final dynamic itemNode in itemNodes) {
        if (items.length >= _maxHomeItemsPerShelf) break;
        final Map<dynamic, dynamic>? itemMap = _asMap(itemNode);
        if (itemMap == null) continue;
        final Map<dynamic, dynamic>? twoRow =
            _asMap(itemMap['musicTwoRowItemRenderer']);
        final Map<dynamic, dynamic>? responsive =
            _asMap(itemMap['musicResponsiveListItemRenderer']);
        MusicItem? item;
        if (twoRow != null) {
          item = _musicItemFromTwoRow(twoRow);
        } else if (responsive != null) {
          item = _musicItemFromResponsive(responsive);
        }
        if (item != null) items.add(item);
      }
      if (items.isEmpty) continue;
      shelves.add(MusicSection(title: title, items: items));
    }
    return shelves;
  }

  /// Menelusuri pohon respons account_menu dan mengambil nama akun pertama.
  static String? _findAccountName(dynamic node) {
    if (node is Map<dynamic, dynamic>) {
      final String? name = _runsText(node['accountName']);
      if (name != null && name.isNotEmpty) return name;
      for (final dynamic child in node.values) {
        final String? found = _findAccountName(child);
        if (found != null) return found;
      }
    } else if (node is List<dynamic>) {
      for (final dynamic child in node) {
        final String? found = _findAccountName(child);
        if (found != null) return found;
      }
    }
    return null;
  }

  /// Menelusuri pohon respons account_menu dan mengambil email akun
  /// pertama dari `accountItemRenderer.email` (simpleText atau runs).
  static String? _findAccountEmail(dynamic node) {
    if (node is Map<dynamic, dynamic>) {
      final dynamic item = node['accountItemRenderer'];
      if (item is Map<dynamic, dynamic>) {
        final String? email = _runsText(item['email']);
        if (email != null && email.isNotEmpty) return email;
      }
      for (final dynamic child in node.values) {
        final String? found = _findAccountEmail(child);
        if (found != null) return found;
      }
    } else if (node is List<dynamic>) {
      for (final dynamic child in node) {
        final String? found = _findAccountEmail(child);
        if (found != null) return found;
      }
    }
    return null;
  }

  /// Menelusuri pohon respons account_menu dan mengambil URL foto akun
  /// dari `accountPhoto`/`avatar` dengan thumbnail terbesar.
  static String? _findAccountAvatarUrl(dynamic node) {
    if (node is Map<dynamic, dynamic>) {
      final String? fromPhoto =
          _largestThumbnailUrl(node['accountPhoto']?['thumbnails']);
      if (fromPhoto != null) return fromPhoto;
      final String? fromAvatar =
          _largestThumbnailUrl(node['avatar']?['thumbnails']);
      if (fromAvatar != null) return fromAvatar;
      for (final dynamic child in node.values) {
        final String? found = _findAccountAvatarUrl(child);
        if (found != null) return found;
      }
    } else if (node is List<dynamic>) {
      for (final dynamic child in node) {
        final String? found = _findAccountAvatarUrl(child);
        if (found != null) return found;
      }
    }
    return null;
  }

  /// Memilih URL thumbnail terbesar dari daftar `{url, width, height}`,
  /// mengikuti orientasi `//` milik Google menjadi `https:`.
  static String? _largestThumbnailUrl(dynamic thumbnails) {
    if (thumbnails is! List<dynamic> || thumbnails.isEmpty) return null;
    String? bestUrl;
    int bestWidth = -1;
    for (final dynamic entry in thumbnails) {
      if (entry is! Map<dynamic, dynamic>) continue;
      final dynamic url = entry['url'];
      if (url is! String || url.isEmpty) continue;
      final dynamic width = entry['width'];
      final int parsedWidth =
          width is int ? width : int.tryParse('$width') ?? 0;
      if (parsedWidth > bestWidth) {
        bestWidth = parsedWidth;
        bestUrl = url.startsWith('//') ? 'https:$url' : url;
      }
    }
    return bestUrl;
  }

  /// Menelusuri seluruh pohon respons innertube dan mengumpulkan renderer
  /// musik (musicTwoRowItemRenderer / musicResponsiveListItemRenderer).
  static void _collectMusicRenderers(dynamic node, List<MusicItem> out) {
    if (out.length >= _maxLibraryResults) return;
    if (node is Map<dynamic, dynamic>) {
      final dynamic twoRow = node['musicTwoRowItemRenderer'];
      if (twoRow is Map<dynamic, dynamic>) {
        final MusicItem? item = _musicItemFromTwoRow(twoRow);
        if (item != null) out.add(item);
      }
      final dynamic responsive = node['musicResponsiveListItemRenderer'];
      if (responsive is Map<dynamic, dynamic>) {
        final MusicItem? item = _musicItemFromResponsive(responsive);
        if (item != null) out.add(item);
      }
      for (final dynamic child in node.values) {
        _collectMusicRenderers(child, out);
        if (out.length >= _maxLibraryResults) return;
      }
    } else if (node is List<dynamic>) {
      for (final dynamic child in node) {
        _collectMusicRenderers(child, out);
        if (out.length >= _maxLibraryResults) return;
      }
    }
  }

  /// Memetakan musicTwoRowItemRenderer (kartu grid) menjadi MusicItem.
  ///
  /// Kartu dapat berupa trek (watchEndpoint.videoId) atau koleksi
  /// (browseEndpoint.browseId: playlist/album/artis). Awalan `MPED<videoId>`
  /// menandai trek riwayat yang belum masuk katalog: videoId diambil dari
  /// awalan tersebut dan browseId dibuang (pola BitChord). Kartu tanpa
  /// browseId ber-videoId dengan artur melebar dianggap video.
  static MusicItem? _musicItemFromTwoRow(Map<dynamic, dynamic> renderer) {
    final Map<dynamic, dynamic>? navigation =
        _asMap(renderer['navigationEndpoint']);
    String? videoId =
        _plainText(_asMap(navigation?['watchEndpoint'])?['videoId']);
    String? browseId =
        _plainText(_asMap(navigation?['browseEndpoint'])?['browseId']);
    if (browseId != null && browseId.startsWith('MPED')) {
      videoId ??= browseId.substring(4);
      browseId = null;
    }
    final String title = _runsText(renderer['title']) ?? '';
    if (title.isEmpty) return null;
    final bool hasVideo = videoId != null && videoId.isNotEmpty;
    final bool hasBrowse = browseId != null && browseId.isNotEmpty;
    if (!hasVideo && !hasBrowse) return null;
    final String artist = _runsText(renderer['subtitle']) ?? '';
    final String type = hasVideo
        ? (!hasBrowse && _isWidescreenCard(renderer) ? 'video' : 'song')
        : _collectionType(browseId!);
    return MusicItem(
      type: type,
      title: title,
      artist: artist,
      subtitle: artist.isNotEmpty ? artist : null,
      thumbnail: _musicThumbnailUrl(renderer['thumbnailRenderer']),
      videoId: hasVideo ? videoId : null,
      browseId: hasBrowse ? browseId : null,
    );
  }

  /// Memetakan musicResponsiveListItemRenderer (baris daftar) menjadi
  /// MusicItem. Baris dengan videoId adalah trek ('song'); baris yang hanya
  /// membawa browseId dipetakan sebagai koleksi (playlist/album/artis).
  static MusicItem? _musicItemFromResponsive(Map<dynamic, dynamic> renderer) {
    String? videoId =
        _plainText(_asMap(renderer['playlistItemData'])?['videoId']);
    final String? browseId = _plainText(
      _asMap(_asMap(renderer['navigationEndpoint'])?['browseEndpoint'])
          ?['browseId'],
    );
    final List<dynamic>? columns = _asList(renderer['flexColumns']);
    String title = '';
    String artist = '';
    if (columns != null && columns.isNotEmpty) {
      final Map<dynamic, dynamic>? titleText = _flexColumnText(columns.first);
      title = _runsText(titleText) ?? '';
      videoId ??= _videoIdFromRuns(titleText);
      if (columns.length > 1) {
        artist = _runsText(_flexColumnText(columns[1])) ?? '';
      }
    }
    if (title.isEmpty) return null;
    final bool hasVideo = videoId != null && videoId.isNotEmpty;
    final bool hasBrowse = browseId != null && browseId.isNotEmpty;
    if (!hasVideo && !hasBrowse) return null;
    String? duration;
    final List<dynamic>? fixedColumns = _asList(renderer['fixedColumns']);
    if (fixedColumns != null && fixedColumns.isNotEmpty) {
      final Map<dynamic, dynamic>? fixedText = _asMap(
        _asMap(fixedColumns.first)
            ?['musicResponsiveListItemFixedColumnRenderer']?['text'],
      );
      final String? fixed = _runsText(fixedText);
      if (fixed != null && fixed.isNotEmpty) duration = fixed;
    }
    return MusicItem(
      type: hasVideo ? 'song' : _collectionType(browseId!),
      title: title,
      artist: artist,
      subtitle: artist.isNotEmpty ? artist : null,
      thumbnail: _musicThumbnailUrl(renderer['thumbnail']),
      videoId: hasVideo ? videoId : null,
      browseId: hasVideo ? null : browseId,
      duration: duration,
    );
  }

  /// Mengambil node teks dari satu kolom responsif innertube.
  static Map<dynamic, dynamic>? _flexColumnText(dynamic column) => _asMap(
        _asMap(_asMap(column)?['musicResponsiveListItemFlexColumnRenderer'])
            ?['text'],
      );

  /// Mengambil videoId dari run pertama (`navigationEndpoint.watchEndpoint`).
  static String? _videoIdFromRuns(dynamic textNode) {
    final List<dynamic>? runs = _asList(_asMap(textNode)?['runs']);
    if (runs == null || runs.isEmpty) return null;
    return _plainText(
      _asMap(_asMap(_asMap(runs.first)?['navigationEndpoint'])
          ?['watchEndpoint'])?['videoId'],
    );
  }

  /// Mengambil URL thumbnail terbesar dari node thumbnail innertube.
  static String? _musicThumbnailUrl(dynamic node) {
    final List<dynamic>? thumbnails = _asList(_asMap(
      _asMap(_asMap(node)?['musicThumbnailRenderer'])?['thumbnail'],
    )?['thumbnails']);
    if (thumbnails == null || thumbnails.isEmpty) return null;
    final String? url = _plainText(_asMap(thumbnails.last)?['url']);
    if (url == null || url.isEmpty) return null;
    return url.startsWith('//') ? 'https:$url' : url;
  }

  /// Melempar nilai ke peta bila memungkinkan; selain itu `null`.
  static Map<dynamic, dynamic>? _asMap(dynamic value) =>
      value is Map<dynamic, dynamic> ? value : null;

  /// Melempar nilai ke daftar bila memungkinkan; selain itu `null`.
  static List<dynamic>? _asList(dynamic value) =>
      value is List<dynamic> ? value : null;

  /// Menentukan tipe koleksi dari awalan browseId YouTube Music (pola
  /// BitChord): MPRE/OLAK5uy_ → album, UC → artis, selain itu (VL, RD…,
  /// campuran/radio) diasumsikan playlist.
  static String _collectionType(String browseId) {
    if (browseId.startsWith('MPRE') || browseId.startsWith('OLAK5uy_')) {
      return 'album';
    }
    if (browseId.startsWith('UC')) return 'artist';
    return 'playlist';
  }

  /// True bila kartu dua baris tampak seperti video: aspek 16:9 atau
  /// thumbnail terbesarnya melebar (tidak persegi).
  static bool _isWidescreenCard(Map<dynamic, dynamic> renderer) {
    final dynamic aspectRatio = renderer['aspectRatio'];
    if (aspectRatio is String && aspectRatio.contains('16_9')) return true;
    final List<dynamic>? thumbnails = _asList(
      _asMap(
        _asMap(_asMap(renderer['thumbnailRenderer'])
            ?['musicThumbnailRenderer'])?['thumbnail'],
      )?['thumbnails'],
    );
    if (thumbnails == null || thumbnails.isEmpty) return false;
    final Map<dynamic, dynamic>? last = _asMap(thumbnails.last);
    final int? width = _intOf(last?['width']);
    final int? height = _intOf(last?['height']);
    if (width == null || height == null || height <= 0) return false;
    return width > height;
  }

  /// Membaca bilangan bulat dari nilai int atau string angka.
  static int? _intOf(dynamic value) =>
      value is int ? value : int.tryParse('$value');

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
        items.add(_videoToItem(video));
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

  /// Mengambil saran lagu terkait (radio YouTube) untuk satu video agar
  /// antrean selalu berisi lagu berikutnya secara otomatis.
  ///
  /// Kegagalan jaringan atau video tanpa saran mengembalikan daftar kosong —
  /// sifat radio bersifat opsional dan tidak boleh mengganggu pemutaran.
  Future<List<MusicItem>> fetchRadio(
    String videoId, {
    int limit = 50,
    Set<String> exclude = const <String>{},
  }) async {
    if (_disposed || videoId.trim().isEmpty) return const <MusicItem>[];
    try {
      final Video seed = await _yt.videos.get(videoId.trim());
      RelatedVideosList? related = await _yt.videos.getRelatedVideos(seed);
      if (related == null) return const <MusicItem>[];
      final List<MusicItem> items = <MusicItem>[];
      final Set<String> seen = <String>{...exclude};
      // Telusuri halaman saran sampai limit terpenuhi (maks. 6 halaman).
      for (var page = 0; page < 6 && related != null && items.length < limit; page++) {
        for (final Video video in related) {
          if (items.length >= limit) break;
          final MusicItem item = _videoToItem(video);
          if (!item.isPlayable || seen.contains(item.videoId)) continue;
          seen.add(item.videoId!);
          items.add(item);
        }
        if (items.length < limit) {
          related = await related.nextPage();
        }
      }
      return items;
    } catch (_) {
      return const <MusicItem>[];
    }
  }

  /// Memetakan satu video YouTube menjadi item musik yang dapat diputar.
  MusicItem _videoToItem(Video video) {
    final String thumbnail = video.thumbnails.highResUrl.isNotEmpty
        ? video.thumbnails.highResUrl
        : video.thumbnails.standardResUrl;
    return MusicItem(
      type: 'song',
      title: video.title,
      artist: video.author,
      subtitle: video.author,
      thumbnail: thumbnail,
      videoId: video.id.value,
      duration: _formatDuration(video.duration),
    );
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
