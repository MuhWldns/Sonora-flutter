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
  });

  /// Penyimpanan sesi (terenkripsi di perangkat; memori saat pengujian).
  final SessionStore store;

  /// Validator opsional: `true` berarti cookie masih aktif.
  final Future<bool> Function(YoutubeSession session)? validate;

  /// Pengambil nama akun opsional untuk mengisi [accountName].
  final Future<String?> Function(YoutubeSession session)? fetchAccountName;

  YoutubeSession? _session;
  String? _accountName;

  /// True bila ada sesi aktif dengan cookie keluarga SAPISID.
  bool get signedIn => _session != null;

  /// Nama akun YouTube Music bila berhasil divalidasi; `null` bila belum.
  String? get accountName => _accountName;

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
    if (YoutubeSession.sapisidFromCookie(session.cookie) == null) return false;
    final Future<bool> Function(YoutubeSession)? validator = validate;
    if (validator != null && !(await validator(session))) return false;
    try {
      await store.write(jsonEncode(session.toJson()));
    } catch (e) {
      debugPrint('[YoutubeAuthService] Gagal menyimpan sesi: $e');
      return false;
    }
    _session = session;
    _accountName = await _resolveAccountName(session);
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
    _accountName = await _resolveAccountName(session);
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

  /// Membuang sesi yang tidak bisa dipulihkan tanpa memunculkan error.
  Future<void> _dropCorrupted() async {
    try {
      await store.clear();
    } catch (_) {
      // Penyimpanan gagal dibersihkan; biarkan state tetap keluar.
    }
    _session = null;
    _accountName = null;
  }
}
