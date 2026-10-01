/// Klien HTTP tipis untuk proxy Sonora.
///
/// - Base URL diambil dari [SettingsStore] dan **ditangkap saat request
///   dimulai**, sehingga perubahan Settings di tengah request tidak mengubah
///   target request yang sedang berjalan.
/// - Base path proxy dipertahankan (mis. `https://host/api` →
///   `https://host/api/home`).
/// - Tidak ada cookie/rahasia: proxy MVP bersifat anonim.
/// - Pesan error selalu dipetakan ke teks tetap; body/URL internal dari server
///   atau exception transport tidak pernah diteruskan ke pemanggil.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'music_models.dart';
import 'settings_store.dart';

/// Kegagalan konfigurasi lokal (proxy belum diisi / URL tidak valid).
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

  @override
  String toString() => 'SonoraApiException($statusCode): $message';
}

/// Klien API proxy Sonora.
class SonoraApi {
  SonoraApi(
    this._settings, {
    http.Client? client,
    Duration timeout = const Duration(seconds: 20),
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _timeout = timeout;

  final SettingsStore _settings;
  final http.Client _client;
  final bool _ownsClient;
  final Duration _timeout;
  bool _closed = false;

  /// `true` bila base URL proxy sudah dikonfigurasi.
  bool get isConfigured => _settings.isConfigured;

  /// Feed beranda.
  Future<List<MusicSection>> home() async {
    final base = _captureBase();
    return _getSections(base, '/home');
  }

  /// Pencarian. [filter] opsional: song|video|album|artist|playlist.
  Future<List<MusicSection>> search(String query, {String? filter}) async {
    final q = query.trim();
    if (q.isEmpty) {
      throw ArgumentError.value(query, 'query', 'Kata kunci pencarian kosong.');
    }
    final base = _captureBase();
    return _getSections(base, '/search', query: {
      'q': q,
      if (filter != null && filter.trim().isNotEmpty) 'filter': filter.trim(),
    });
  }

  /// Detail browse. [id] dapat berupa browseId (`MPREb_...`, `UC...`) atau
  /// playlistId (`VL...`).
  Future<List<MusicSection>> browse(String id) async {
    final trimmed = id.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(id, 'id', 'ID browse kosong.');
    }
    final base = _captureBase();
    return _getSections(base, '/browse', query: {'id': trimmed});
  }

  /// Menguji koneksi ke [base] lewat `/healthz`.
  ///
  /// Sukses hanya bila respons `200` **dan** body JSON memuat `ok == true`.
  /// Melempar [ArgumentError] untuk URL tidak valid dan [SonoraApiException]
  /// untuk kegagalan lain.
  Future<void> checkConnection(String base) async {
    final normalized = SettingsStore.normalizeProxyBase(base);
    if (normalized == null) {
      throw const SonoraConfigurationException('URL proxy kosong.');
    }
    final uri = _resolve(Uri.parse(normalized), '/healthz');
    final response = await _send(uri);
    if (response.statusCode != 200) {
      throw SonoraApiException(
        _message(response.statusCode),
        statusCode: response.statusCode,
        uri: uri,
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(_decodeBody(response));
    } on FormatException {
      throw SonoraApiException(
        'Respons kesehatan proxy tidak dapat dibaca.',
        statusCode: response.statusCode,
        uri: uri,
      );
    }
    if (decoded is! Map || decoded['ok'] != true) {
      throw SonoraApiException(
        'Proxy tidak melaporkan status sehat.',
        statusCode: response.statusCode,
        uri: uri,
      );
    }
  }

  /// URL relay audio yang diputar oleh pemutar native. Melewati proxy agar
  /// stream terikat ke IP server.
  Uri streamUri(String videoId) {
    final id = videoId.trim();
    if (id.isEmpty) {
      throw ArgumentError.value(videoId, 'videoId', 'ID video kosong.');
    }
    final base = _captureBase();
    return _resolve(base, '/stream', query: {'videoId': id});
  }

  /// Membebaskan koneksi HTTP. Aman dipanggil berkali-kali.
  void close() {
    if (_closed) return;
    _closed = true;
    if (_ownsClient) _client.close();
  }

  // ---------------------------------------------------------------------------

  /// Menangkap base URL saat request dimulai (bukan setelah await).
  Uri _captureBase() {
    final raw = _settings.proxyBase.trim();
    if (raw.isEmpty) {
      throw const SonoraConfigurationException(
        'URL proxy belum dikonfigurasi. Isi di Pengaturan.',
      );
    }
    final parsed = Uri.tryParse(raw);
    if (parsed == null ||
        parsed.host.isEmpty ||
        !(parsed.isScheme('http') || parsed.isScheme('https'))) {
      throw const SonoraConfigurationException(
        'URL proxy tidak valid. Gunakan alamat http(s) lengkap.',
      );
    }
    return parsed;
  }

  /// Menggabungkan base (beserta path prefix-nya) dengan path endpoint.
  static Uri _resolve(Uri base, String path, {Map<String, String>? query}) {
    final baseSegments = base.pathSegments.where((s) => s.isNotEmpty);
    final extraSegments = path.split('/').where((s) => s.isNotEmpty);
    var uri = base.replace(pathSegments: [...baseSegments, ...extraSegments]);
    if (query != null && query.isNotEmpty) {
      uri = uri.replace(queryParameters: {...uri.queryParameters, ...query});
    }
    return uri;
  }

  Future<List<MusicSection>> _getSections(
    Uri base,
    String path, {
    Map<String, String>? query,
  }) async {
    final uri = _resolve(base, path, query: query);
    final response = await _send(uri);
    if (response.statusCode != 200) {
      throw SonoraApiException(
        _message(response.statusCode),
        statusCode: response.statusCode,
        uri: uri,
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(_decodeBody(response));
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
    final raw = decoded['sections'];
    if (raw is! List) {
      throw SonoraApiException(
        'Respons proxy tidak memuat daftar bagian.',
        statusCode: response.statusCode,
        uri: uri,
      );
    }

    // Toleran terhadap entri section rusak; bentuk root/sections tetap ketat.
    return raw
        .whereType<Map>()
        .map((entry) => MusicSection.fromJson(_asMap(entry)))
        .toList(growable: false);
  }

  Future<http.Response> _send(Uri uri) async {
    if (_closed) {
      throw const SonoraApiException('Klien API sudah ditutup.');
    }
    try {
      return await _client
          .get(uri, headers: const {'accept': 'application/json'})
          .timeout(_timeout);
    } on TimeoutException {
      throw SonoraApiException('Koneksi ke proxy habis waktu.', uri: uri);
    } on http.ClientException {
      // Pesan transport bisa memuat origin internal — jangan diteruskan.
      throw SonoraApiException(
        'Tidak dapat menghubungi proxy. Periksa jaringan dan alamat proxy.',
        uri: uri,
      );
    }
  }

  /// Body proxy selalu JSON UTF-8; `http` default latin1 akan merusak karakter
  /// non-ASCII (mis. `•`, `Ø`), jadi decode byte-nya sendiri.
  static String _decodeBody(http.Response response) =>
      utf8.decode(response.bodyBytes, allowMalformed: true);

  static Map<String, dynamic> _asMap(Map<Object?, Object?> value) {
    final out = <String, dynamic>{};
    for (final entry in value.entries) {
      out[entry.key.toString()] = entry.value;
    }
    return out;
  }

  /// Pesan tetap per status; body server tidak pernah diteruskan.
  static String _message(int statusCode) {
    switch (statusCode) {
      case 400:
        return 'Permintaan tidak valid.';
      case 401:
        return 'Akses ke proxy ditolak.';
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
}
