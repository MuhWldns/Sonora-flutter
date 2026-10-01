/// Penyimpanan preferensi lokal Sonora: base URL proxy dan cookie akun.
///
/// Cookie **tidak pernah** dikirim ke mana pun kecuali sebagai header
/// `x-yt-cookie` pada request proxy; proxy tetap stateless. Nilai yang
/// tersimpan selalu divalidasi/di-sanitasi saat dimuat, dan payload yang rusak
/// diturunkan ke default aman alih-alih menggagalkan startup.
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preferensi yang dapat diamati (observable) oleh UI.
class SettingsStore extends ChangeNotifier {
  SettingsStore._(
    this._preferences, {
    required String proxyBase,
    required String? cookie,
  }) : _proxyBase = proxyBase,
       _cookie = cookie;

  static const String _proxyBaseKey = 'sonora.proxyBase';
  static const String _cookieKey = 'sonora.cookie';

  /// Base URL default: kosong. Tanpa konfigurasi, aplikasi tidak memiliki
  /// endpoint dan UI harus meminta pengguna mengisi alamat proxy.
  static const String defaultProxyBase = '';

  final SharedPreferences _preferences;
  String _proxyBase;
  String? _cookie;

  /// Base URL proxy aktif (tanpa slash di ujung). Bisa kosong.
  String get proxyBase => _proxyBase;

  /// Cookie akun mentah, atau `null` bila belum diatur.
  String? get cookie => _cookie;

  bool get hasProxyBase => _proxyBase.isNotEmpty;
  bool get hasCookie => _cookie != null && _cookie!.isNotEmpty;

  /// Memuat preferensi dari penyimpanan. Selalu berhasil: nilai korup
  /// dikembalikan ke default.
  static Future<SettingsStore> load({SharedPreferences? preferences}) async {
    final prefs = preferences ?? await SharedPreferences.getInstance();

    var proxyBase = '';
    final storedProxy = prefs.getString(_proxyBaseKey);
    if (storedProxy != null) {
      try {
        proxyBase = normalizeProxyBase(storedProxy) ?? '';
      } on ArgumentError {
        proxyBase = '';
      }
    }

    final storedCookie = prefs.getString(_cookieKey);
    final cookie = _sanitizeCookie(storedCookie);

    return SettingsStore._(prefs, proxyBase: proxyBase, cookie: cookie);
  }

  /// Menyimpan base URL proxy. String kosong menghapus konfigurasi.
  ///
  /// Melempar [ArgumentError] bila URL non-kosong tidak valid.
  Future<void> setProxyBase(String url) async {
    final normalized = normalizeProxyBase(url) ?? '';
    _proxyBase = normalized;
    if (normalized.isEmpty) {
      await _preferences.remove(_proxyBaseKey);
    } else {
      await _preferences.setString(_proxyBaseKey, normalized);
    }
    notifyListeners();
  }

  /// Menyimpan cookie akun. String kosong ditolak.
  Future<void> setCookie(String cookie) async {
    final sanitized = _sanitizeCookie(cookie);
    if (sanitized == null) {
      throw ArgumentError.value(cookie, 'cookie', 'Cookie tidak boleh kosong.');
    }
    _cookie = sanitized;
    await _preferences.setString(_cookieKey, sanitized);
    notifyListeners();
  }

  /// Menghapus cookie akun dari memori dan penyimpanan.
  Future<void> clearCookie() async {
    if (_cookie == null) return;
    _cookie = null;
    await _preferences.remove(_cookieKey);
    notifyListeners();
  }

  /// Menghapus seluruh preferensi.
  Future<void> clear() async {
    _proxyBase = '';
    _cookie = null;
    await _preferences.remove(_proxyBaseKey);
    await _preferences.remove(_cookieKey);
    notifyListeners();
  }

  /// Menormalkan base URL proxy.
  ///
  /// Mengembalikan `null` untuk input kosong (berarti "tidak dikonfigurasi").
  /// Melempar [ArgumentError] bila input non-kosong bukan URL http(s) absolut
  /// yang wajar (tanpa query/fragment). Base path dipertahankan.
  static String? normalizeProxyBase(String? raw) {
    final trimmed = raw?.trim() ?? '';
    if (trimmed.isEmpty) return null;

    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw ArgumentError.value(
        raw,
        'proxyBase',
        'URL proxy harus berupa alamat lengkap, mis. https://host:8787',
      );
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw ArgumentError.value(
        raw,
        'proxyBase',
        'Skema URL proxy harus http atau https.',
      );
    }
    if (uri.hasQuery || uri.hasFragment) {
      throw ArgumentError.value(
        raw,
        'proxyBase',
        'URL proxy tidak boleh memuat query atau fragment.',
      );
    }

    var path = uri.path;
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    return uri.replace(path: path).toString();
  }

  static String? _sanitizeCookie(String? raw) {
    final trimmed = raw?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }
}
