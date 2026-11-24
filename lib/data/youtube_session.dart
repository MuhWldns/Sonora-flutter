library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Origin YouTube Music yang dipakai untuk menandatangani request innertube.
const String youtubeMusicOrigin = 'https://music.youtube.com';

/// Daftar nama cookie SAPISID yang diterima, berurutan sesuai prioritas
/// (BitChord Innertube.kt): SAPISID, __Secure-3PAPISID, __Secure-1PAPISID.
const List<String> _sapisidCookieNames = <String>[
  'SAPISID',
  '__Secure-3PAPISID',
  '__Secure-1PAPISID',
];

/// Menghitung nilai hash untuk header `Authorization: SAPISIDHASH`.
///
/// Rumus (BitChord Innertube.kt): `sha1("{timestamp} {sapisid} {origin}")`
/// dalam heksadesimal huruf kecil. Dipisah sebagai fungsi bebas agar mudah
/// diuji dengan jam tiruan.
String sapisidHash(String sapisid, String origin, int timestampSeconds) {
  final String input = '$timestampSeconds $sapisid $origin';
  return sha1.convert(utf8.encode(input)).toString();
}

/// Sesi YouTube Music hasil tangkapan WebView.
///
/// Berisi cookie lengkap plus nilai ytcfg yang dibutuhkan untuk menandatangani
/// setiap request innertube terotorisasi. Disimpan sebagai JSON terenkripsi
/// lewat [SessionStore].
class YoutubeSession {
  const YoutubeSession({
    required this.cookie,
    this.pageId,
    required this.dataSyncId,
    required this.authUser,
    required this.visitorData,
    required this.clientVersion,
  });

  /// Cookie mentah lengkap dari domain music.youtube.com.
  final String cookie;

  /// X-Goog-PageId; boleh kosong (tidak semua sesi memilikinya).
  final String? pageId;

  /// Delegasi akun untuk `context.user.onBehalfOfUser`.
  final String dataSyncId;

  /// Nomor akun untuk header `X-Goog-AuthUser` (biasanya "0").
  final String authUser;

  /// Nilai `visitorData` untuk header `X-Goog-Visitor-Id`.
  final String visitorData;

  /// Versi klien WEB_REMIX dari ytcfg untuk header `X-YouTube-Client-Version`.
  final String clientVersion;

  /// Mengambil nilai SAPISID dari string cookie sesuai urutan prioritas.
  ///
  /// Mengembalikan `null` bila tidak ada cookie keluarga SAPISID yang punya
  /// nilai — artinya sesi ini tidak dianggap masuk.
  static String? sapisidFromCookie(String cookie) {
    final Map<String, String> pairs = <String, String>{};
    for (final String part in cookie.split(';')) {
      final int eq = part.indexOf('=');
      if (eq <= 0) continue;
      final String name = part.substring(0, eq).trim();
      final String value = part.substring(eq + 1).trim();
      if (name.isNotEmpty && value.isNotEmpty) {
        pairs.putIfAbsent(name, () => value);
      }
    }
    for (final String name in _sapisidCookieNames) {
      final String? value = pairs[name];
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'cookie': cookie,
        'pageId': pageId,
        'dataSyncId': dataSyncId,
        'authUser': authUser,
        'visitorData': visitorData,
        'clientVersion': clientVersion,
      };

  /// Membangun sesi dari JSON tersimpan; `null` bila bentuknya tidak valid
  /// atau cookie tidak memuat keluarga SAPISID.
  static YoutubeSession? fromJson(Object? json) {
    if (json is! Map) return null;
    final String? cookie = _string(json['cookie']);
    if (cookie == null) return null;
    final String? dataSyncId = _string(json['dataSyncId']);
    final String? authUser = _string(json['authUser']);
    final String? visitorData = _string(json['visitorData']);
    final String? clientVersion = _string(json['clientVersion']);
    if (dataSyncId == null || authUser == null) return null;
    if (visitorData == null || clientVersion == null) return null;
    if (sapisidFromCookie(cookie) == null) return null;
    return YoutubeSession(
      cookie: cookie,
      pageId: _string(json['pageId']),
      dataSyncId: dataSyncId,
      authUser: authUser,
      visitorData: visitorData,
      clientVersion: clientVersion,
    );
  }

  static String? _string(Object? value) =>
      value is String && value.isNotEmpty ? value : null;
}

/// Penyimpanan serial sesi (string JSON). Implementasi produksi memakai
/// enkripsi perangkat; pengujian memakai memori.
abstract class SessionStore {
  Future<void> write(String json);
  Future<String?> read();
  Future<void> clear();
}

/// Penyimpanan sesi terenkripsi di perangkat (flutter_secure_storage).
class FlutterSecureSessionStore implements SessionStore {
  const FlutterSecureSessionStore();

  static const String _storageKey = 'sonora.ytmusic_session';

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  @override
  Future<void> write(String json) => _storage.write(key: _storageKey, value: json);

  @override
  Future<String?> read() => _storage.read(key: _storageKey);

  @override
  Future<void> clear() => _storage.delete(key: _storageKey);
}

/// Penyimpanan sesi di memori untuk pengujian.
class InMemorySessionStore implements SessionStore {
  String? _value;

  @override
  Future<void> write(String json) async {
    _value = json;
  }

  @override
  Future<String?> read() async => _value;

  @override
  Future<void> clear() async {
    _value = null;
  }
}

/// Informasi profil akun YouTube Music hasil parsing `account_menu`.
///
/// Field yang tidak ditemukan pada respons bernilai `null`; [name] kosong
/// berarti nama akun tidak berhasil dibaca dari respons.
class AccountInfo {
  const AccountInfo({
    required this.name,
    this.email,
    this.avatarUrl,
  });

  /// Nama tampilan akun; string kosong bila tidak ditemukan.
  final String name;

  /// Email akun; `null` bila Google tidak menyertakannya.
  final String? email;

  /// URL foto profil (thumbnail terbesar); `null` bila tidak ada.
  final String? avatarUrl;
}
