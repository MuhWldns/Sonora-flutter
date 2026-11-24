library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'youtube_session.dart';

/// Layanan sesi login YouTube Music.
///
/// Menyimpan sesi hasil tangkapan WebView secara terenkripsi lewat
/// [SessionStore], memulihkannya saat aplikasi dibuka, dan menghapusnya saat
/// pengguna keluar. Validator [validate] (misal memanggil
/// `YouTubeMusicService.fetchAccountName`) dipakai untuk memastikan cookie
/// benar-benar masih aktif sebelum sesi diterima.
class YoutubeAuthService extends ChangeNotifier {
  YoutubeAuthService({
    required this.store,
    this.validate,
    this.fetchAccountName,
    this.fetchAccountInfo,
  });

  /// Penyimpanan sesi (terenkripsi di perangkat; memori saat pengujian).
  final SessionStore store;

  /// Validator opsional: `true` berarti cookie masih aktif.
  final Future<bool> Function(YoutubeSession session)? validate;

  /// Pengambil nama akun opsional untuk mengisi [accountName].
  final Future<String?> Function(YoutubeSession session)? fetchAccountName;

  /// Pengambil info akun opsional untuk mengisi [accountEmail] dan
  /// [accountAvatarUrl] (beserta [accountName] bila [fetchAccountName]
  /// tidak disediakan).
  final Future<AccountInfo?> Function(YoutubeSession session)?
      fetchAccountInfo;

  YoutubeSession? _session;
  String? _accountName;
  String? _accountEmail;
  String? _accountAvatarUrl;

  /// True bila ada sesi aktif dengan cookie keluarga SAPISID.
  bool get signedIn => _session != null;

  /// Nama akun YouTube Music bila berhasil divalidasi; `null` bila belum.
  String? get accountName => _accountName;

  /// Email akun YouTube Music bila tersedia; `null` bila belum masuk atau
  /// Google tidak menyertakannya.
  String? get accountEmail => _accountEmail;

  /// URL foto profil akun bila tersedia; `null` bila belum masuk atau
  /// tidak ada fotonya.
  String? get accountAvatarUrl => _accountAvatarUrl;

  /// Sesi aktif; `null` bila belum masuk.
  YoutubeSession? get session => _session;

  /// Menyimpan sesi hasil tangkapan WebView.
  ///
  /// Mengembalikan `false` (tanpa mengubah state) bila cookie tidak memuat
  /// keluarga SAPISID, validator menolak, atau penyimpanan gagal menulis.
  Future<bool> capture({
    required String cookie,
    String? pageId,
    required String dataSyncId,
    required String authUser,
    required String visitorData,
    required String clientVersion,
  }) async {
    final YoutubeSession session = YoutubeSession(
      cookie: cookie,
      pageId: pageId,
      dataSyncId: dataSyncId,
      authUser: authUser,
      visitorData: visitorData,
      clientVersion: clientVersion,
    );
    // Tanpa keluarga SAPISID berarti belum masuk — tolak tanpa notifikasi.
    if (YoutubeSession.sapisidFromCookie(session.cookie) == null) {
      // Diagnostik aman: tahap penolakan dicatat tanpa nilai cookie.
      debugPrint(
        '[YoutubeAuthService] Capture ditolak: cookie tanpa keluarga SAPISID',
      );
      return false;
    }
    final Future<bool> Function(YoutubeSession)? validator = validate;
    if (validator != null && !(await validator(session))) {
      // Diagnostik aman: validator menolak (mis. HTTP non-200).
      debugPrint(
        '[YoutubeAuthService] Capture ditolak: validator menolak sesi',
      );
      return false;
    }
    try {
      await store.write(jsonEncode(session.toJson()));
    } catch (e) {
      debugPrint('[YoutubeAuthService] Gagal menyimpan sesi: $e');
      return false;
    }
    _session = session;
    await _resolveAccountFields(session);
    notifyListeners();
    return true;
  }

  /// Keluar: menghapus sesi dari penyimpanan dan memori.
  Future<void> signOut() async {
    try {
      await store.clear();
    } catch (e) {
      debugPrint('[YoutubeAuthService] Gagal menghapus sesi tersimpan: $e');
    }
    _session = null;
    _accountName = null;
    _accountEmail = null;
    _accountAvatarUrl = null;
    notifyListeners();
  }

  /// Memulihkan sesi tersimpan saat aplikasi dibuka.
  ///
  /// Sesi rusak/kosong dibuang secara diam-diam; kegagalan jaringan saat
  /// mengambil nama akun tidak menggagalkan pemulihan.
  Future<void> restore() async {
    final String? raw;
    try {
      raw = await store.read();
    } catch (e) {
      debugPrint('[YoutubeAuthService] Gagal membaca sesi tersimpan: $e');
      return;
    }
    if (raw == null || raw.isEmpty) return;
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      await _dropCorrupted();
      return;
    }
    final YoutubeSession? session = YoutubeSession.fromJson(decoded);
    if (session == null) {
      await _dropCorrupted();
      return;
    }
    _session = session;
    await _resolveAccountFields(session);
    notifyListeners();
  }

  Future<String?> _resolveAccountName(YoutubeSession session) async {
    final Future<String?> Function(YoutubeSession)? fetcher = fetchAccountName;
    if (fetcher == null) return null;
    try {
      return await fetcher(session);
    } catch (_) {
      return null;
    }
  }

  /// Mengisi nama, email, dan avatar akun dari callback yang tersedia.
  ///
  /// [fetchAccountInfo] dipakai bila tersedia (satu request untuk semua
  /// field); bila tidak, kembali ke [fetchAccountName] untuk nama saja.
  /// Kegagalan jaringan tidak pernah menggagalkan capture/restore.
  Future<void> _resolveAccountFields(YoutubeSession session) async {
    _accountName = null;
    _accountEmail = null;
    _accountAvatarUrl = null;
    final Future<AccountInfo?> Function(YoutubeSession)? infoFetcher =
        fetchAccountInfo;
    if (infoFetcher != null) {
      try {
        final AccountInfo? info = await infoFetcher(session);
        final String name = info?.name ?? '';
        _accountName = name.isEmpty ? null : name;
        _accountEmail = info?.email;
        _accountAvatarUrl = info?.avatarUrl;
      } catch (_) {
        // Info akun bersifat pelengkap; biarkan seluruh field null.
      }
      return;
    }
    _accountName = await _resolveAccountName(session);
  }

  /// Membuang sesi yang tidak bisa dipulihkan tanpa memunculkan error.
  Future<void> _dropCorrupted() async {
    try {
      await store.clear();
    } catch (_) {
      // Penyimpanan gagal dibersihkan; biarkan state tetap keluar.
    }
    _session = null;
    _accountName = null;
    _accountEmail = null;
    _accountAvatarUrl = null;
  }
}
