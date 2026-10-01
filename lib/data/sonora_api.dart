/// Klien HTTP tipis untuk proxy Sonora.
///
/// - Base URL diambil dari [SettingsStore] setiap request sehingga perubahan
///   Settings langsung berlaku tanpa membuat ulang klien.
/// - Base path pada URL proxy dipertahankan (mis. `https://host/api` →
///   `https://host/api/home`).
/// - Cookie akun dikirim per-request lewat header `x-yt-cookie`; server tetap
///   stateless dan tidak pernah menyimpan cookie.
/// - Semua kegagalan jaringan/HTTP dilempar sebagai [SonoraApiException] dengan
///   pesan aman (tidak membocorkan cookie/URL internal) dan `statusCode`.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'music_models.dart';
import 'settings_store.dart';

/// Kegagalan yang berasal dari konfigurasi lokal (proxy belum diisi, dll).
class SonoraConfigurationException implements Exception {
  const SonoraConfigurationException(this.message);

  final String message;

  @override
  String toString() => 'SonoraConfigurationException: $message';
}

/// Kegagalan request ke proxy. `statusCode` null berarti kegagalan
/// jaringan/timeout atau payload tak valid.
class SonoraApiException implements Exception {
  const SonoraApiException(this.message, {this.statusCode, this.uri});

  final String message;
  final int? statusCode;
  final Uri? uri;

  /// Proxy menolak karena tidak ada cookie / cookie kedaluwarsa.
  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => 'SonoraApiException($statusCode): $message';
}

/// Klien API proxy Sonora.
class SonoraApi {
  SonoraApi(
    this._settings, {
    http.Client? client,
    Duration timeout = const Duration(seconds: 20),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _timeout = timeout;

  /// ID video YouTube kanonik: 11 karakter `[A-Za-z0-9_-]`.
  static final RegExp videoIdPattern = RegExp(r'^[A-Za-z0-9_-]{11}$');

  final SettingsStore _settings;
  final http.Client _client;
  final bool _ownsClient;
  final Duration _timeout;
  bool _closed = false;

  /// Base URL aktif, atau `null` bila belum dikonfigurasi/tidak valid.
  Uri? get baseUri {
    final base = _settings.proxyBase.trim();
    if (base.isEmpty) return null;
    final parsed = Uri.tryParse(base);
    if (parsed == null ||
        parsed.host.isEmpty ||
        !(parsed.isScheme('http') || parsed.isScheme('https'))) {
      return null;
    }
    return parsed;
  }

  bool get isConfigured => baseUri != null;

  /// `true` bila cookie akun tersedia.
  bool get hasCookie {
    final cookie = _settings.cookie;
    return cookie != null && cookie.trim().isNotEmpty;
  }

  // ---------------------------------------------------------------------------
  // Feed publik
  // ---------------------------------------------------------------------------

  Future<HealthStatus> healthz() async =>
      HealthStatus.fromJson(await _getJson('/healthz'));

  Future<MusicFeed> home() async => MusicFeed.fromJson(await _getJson('/home'));

  /// Pencarian. [filter] opsional: song|video|album|artist|playlist.
  Future<MusicFeed> search(String query, {String? filter}) async {
    final q = query.trim();
    if (q.isEmpty) {
      throw ArgumentError.value(query, 'query', 'Kata kunci pencarian kosong.');
    }
    return MusicFeed.fromJson(
      await _getJson(
        '/search',
        query: {
          'q': q,
          if (filter != null && filter.trim().isNotEmpty)
            'filter': filter.trim(),
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Feed akun (butuh cookie)
  // ---------------------------------------------------------------------------

  Future<MusicFeed> library() async =>
      MusicFeed.fromJson(await _getJson('/library', authenticated: true));

  Future<MusicFeed> history() async =>
      MusicFeed.fromJson(await _getJson('/history', authenticated: true));

  // ---------------------------------------------------------------------------
  // Browse / antrean
  // ---------------------------------------------------------------------------

  /// [id] dapat berupa browseId (`MPREb_...`, `UC...`) atau playlistId (`VL...`).
  Future<BrowseResult> browse(String id) async {
    final trimmed = id.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(id, 'id', 'ID browse kosong.');
    }
    return BrowseResult.fromJson(
      await _getJson('/browse', query: {'id': trimmed}),
    );
  }

  Future<PlaybackQueue> next(String videoId) async {
    final id = _requireVideoId(videoId);
    return PlaybackQueue.fromJson(
      await _getJson('/next', query: {'videoId': id}),
    );
  }

  Future<PlaybackQueue> nextContinue(String token) async {
    final trimmed = token.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(token, 'token', 'Token continuation kosong.');
    }
    return PlaybackQueue.fromJson(
      await _getJson('/next/continue', query: {'token': trimmed}),
    );
  }

  // ---------------------------------------------------------------------------
  // Playback & lirik
  // ---------------------------------------------------------------------------

  Future<PlayerInfo> player(String videoId) async {
    final id = _requireVideoId(videoId);
    return PlayerInfo.fromJson(
      await _getJson('/player', query: {'videoId': id}),
    );
  }

  /// Lirik; `null` bila upstream tidak punya lirik untuk video tersebut.
  Future<Lyrics?> lyrics(String videoId) async {
    final id = _requireVideoId(videoId);
    final body = await _getJson('/lyrics', query: {'videoId': id});
    final raw = body['lyrics'];
    if (raw == null) return null;
    return Lyrics.fromJson(raw);
  }

  /// URL relay audio untuk diputar oleh pemutar native. Melewati proxy agar
  /// stream terikat ke IP server (aman untuk VPS pribadi).
  Uri streamUri(String videoId) {
    final id = _requireVideoId(videoId);
    return _endpoint('/stream', query: {'videoId': id});
  }

  /// Membebaskan koneksi HTTP. Aman dipanggil berkali-kali.
  void close() {
    if (_closed) return;
    _closed = true;
    if (_ownsClient) _client.close();
  }

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  String _requireVideoId(String value) {
    final trimmed = value.trim();
    if (!videoIdPattern.hasMatch(trimmed)) {
      throw ArgumentError.value(value, 'videoId', 'ID video tidak valid.');
    }
    return trimmed;
  }

  /// Membangun URI endpoint dengan mempertahankan base path proxy.
  Uri _endpoint(String path, {Map<String, String>? query}) {
    final base = _settings.proxyBase.trim();
    if (base.isEmpty) {
      throw const SonoraConfigurationException(
        'URL proxy belum dikonfigurasi. Isi di Pengaturan.',
      );
    }
    final parsed = Uri.tryParse(base);
    if (parsed == null ||
        parsed.host.isEmpty ||
        !(parsed.isScheme('http') || parsed.isScheme('https'))) {
      throw const SonoraConfigurationException(
        'URL proxy tidak valid. Gunakan alamat http(s) lengkap.',
      );
    }

    final baseSegments = parsed.pathSegments.where(
      (segment) => segment.isNotEmpty,
    );
    final extraSegments = path
        .split('/')
        .where((segment) => segment.isNotEmpty);
    var uri = parsed.replace(pathSegments: [...baseSegments, ...extraSegments]);
    if (query != null && query.isNotEmpty) {
      uri = uri.replace(queryParameters: {...uri.queryParameters, ...query});
    }
    return uri;
  }

  Future<Map<String, Object?>> _getJson(
    String path, {
    Map<String, String>? query,
    bool authenticated = false,
  }) async {
    if (_closed) {
      throw const SonoraApiException('Klien API sudah ditutup.');
    }

    final uri = _endpoint(path, query: query);
    final headers = <String, String>{'accept': 'application/json'};

    if (authenticated) {
      final cookie = _settings.cookie?.trim();
      if (cookie == null || cookie.isEmpty) {
        throw SonoraApiException(
          'Akun YouTube belum dihubungkan. Tambahkan cookie di Pengaturan.',
          statusCode: 401,
          uri: uri,
        );
      }
      headers['x-yt-cookie'] = cookie;
    }

    http.Response response;
    try {
      response = await _client.get(uri, headers: headers).timeout(_timeout);
    } on TimeoutException {
      throw SonoraApiException('Koneksi ke proxy habis waktu.', uri: uri);
    } on http.ClientException catch (error) {
      throw SonoraApiException(
        'Tidak dapat menghubungi proxy: ${error.message}',
        uri: uri,
      );
    }

    if (response.statusCode != 200) {
      throw SonoraApiException(
        _errorMessage(response.statusCode, _decodeBody(response)),
        statusCode: response.statusCode,
        uri: uri,
      );
    }

    final body = _decodeBody(response);
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw SonoraApiException(
        'Respons proxy tidak dapat dibaca.',
        statusCode: response.statusCode,
        uri: uri,
      );
    }
    if (decoded is! Map) {
      throw SonoraApiException(
        'Format respons proxy tidak dikenal.',
        statusCode: response.statusCode,
        uri: uri,
      );
    }
    return jsonObject(decoded);
  }

  /// Body proxy selalu JSON UTF-8; `http` default latin1 akan merusak karakter
  /// non-ASCII (mis. `•`, `Ø`), jadi decode byte-nya sendiri.
  static String _decodeBody(http.Response response) =>
      utf8.decode(response.bodyBytes, allowMalformed: true);

  String _errorMessage(int statusCode, String body) {
    final detail = _errorDetail(body);
    if (detail != null) return detail;
    switch (statusCode) {
      case 400:
        return 'Permintaan tidak valid.';
      case 401:
        return 'Akun YouTube belum dihubungkan atau cookie kedaluwarsa.';
      case 403:
        return 'Akses ditolak oleh proxy.';
      case 404:
        return 'Data tidak ditemukan di proxy.';
      case 502:
        return 'Proxy gagal mengambil data dari upstream.';
      case 503:
        return 'Layanan sementara tidak tersedia. Coba lagi nanti.';
      default:
        return 'Proxy mengembalikan status $statusCode.';
    }
  }

  /// Mengekstrak `error` dari body JSON proxy, bila ada.
  static String? _errorDetail(String body) {
    if (body.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final message = jsonString(decoded['error']);
        if (message != null) return message;
      }
    } on FormatException {
      // Body non-JSON (mis. HTML error page) — abaikan.
    }
    return null;
  }
}
