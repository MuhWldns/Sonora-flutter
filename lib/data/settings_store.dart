/// Preferensi lokal Sonora: hanya base URL proxy.
///
/// Tidak ada cookie/rahasia yang disimpan. Nilai yang dimuat selalu
/// divalidasi; payload rusak diturunkan ke default aman.
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Kegagalan menulis preferensi ke penyimpanan.
///
/// Dilempar alih-alih melaporkan sukses palsu ketika `SharedPreferences`
/// menolak/mengembalikan `false` dari operasi tulis.
class SettingsPersistenceException implements Exception {
  const SettingsPersistenceException(this.message);

  final String message;

  @override
  String toString() => 'SettingsPersistenceException: $message';
}

/// Menyimpan dan mengamati base URL proxy.
class SettingsStore extends ChangeNotifier {
  SettingsStore._(this._preferences, this._proxyBase, this._proxyDraft);

  static const String _proxyBaseKey = 'sonora.proxyBase';
  static const String _proxyDraftKey = 'sonora.proxyDraft';

  /// Default opsional dari build (`--dart-define=SONORA_PROXY_URL=...`).
  static const String _environmentDefault =
      String.fromEnvironment('SONORA_PROXY_URL');

  final SharedPreferences _preferences;
  String _proxyBase;
  String _proxyDraft;

  /// Base URL proxy aktif (tanpa slash ujung). Bisa kosong.
  String get proxyBase => _proxyBase;

  /// Draf URL proxy terakhir yang tersimpan saat switch dinonaktifkan.
  String get proxyDraft => _proxyDraft;

  /// `true` bila base URL sudah diisi.
  bool get isConfigured => _proxyBase.isNotEmpty;

  /// Memuat preferensi. Selalu berhasil; nilai korup menjadi default.
  ///
  /// Key yang **hilang** (null) memakai default build, sedangkan key yang
  /// tersimpan sebagai string **kosong** tetap kosong (default tidak muncul
  /// kembali setelah pengguna menghapus alamat).
  static Future<SettingsStore> load() async {
    final prefs = await SharedPreferences.getInstance();

    final stored = prefs.get(_proxyBaseKey);
    final String proxyBase;
    if (stored == null) {
      proxyBase = _normalizeOrEmpty(_environmentDefault);
    } else if (stored is String) {
      proxyBase = _normalizeOrEmpty(stored);
    } else {
      // Nilai korup (bukan string) — turunkan ke default aman.
      proxyBase = '';
    }

    final storedDraft = prefs.get(_proxyDraftKey);
    final String proxyDraft;
    if (storedDraft is String && storedDraft.isNotEmpty) {
      proxyDraft = _normalizeOrEmpty(storedDraft);
    } else {
      proxyDraft = proxyBase;
    }

    return SettingsStore._(prefs, proxyBase, proxyDraft);
  }

  /// Menyimpan base URL proxy. String kosong menghapus konfigurasi.
  ///
  /// Persistensi dilakukan lebih dulu; state dan notifikasi hanya berubah bila
  /// penyimpanan benar-benar berhasil. Melempar [ArgumentError] untuk URL non-
  /// kosong yang tidak valid, dan [SettingsPersistenceException] bila gagal
  /// menyimpan.
  Future<void> setProxyBase(String value) async {
    final normalized = normalizeProxyBase(value) ?? '';
    final saved = await _preferences.setString(_proxyBaseKey, normalized);
    if (!saved) {
      throw const SettingsPersistenceException(
        'Gagal menyimpan alamat proxy. Perubahan tidak diterapkan.',
      );
    }
    if (normalized.isNotEmpty) {
      _proxyDraft = normalized;
      await _preferences.setString(_proxyDraftKey, normalized);
    }
    _proxyBase = normalized;
    notifyListeners();
  }

  /// Menyimpan draf URL proxy tanpa mengaktifkannya secara langsung.
  Future<void> setProxyDraft(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    _proxyDraft = trimmed;
    await _preferences.setString(_proxyDraftKey, trimmed);
    notifyListeners();
  }

  /// Menormalkan base URL proxy.
  ///
  /// Mengembalikan `null` untuk input kosong (berarti "tidak dikonfigurasi").
  /// Melempar [ArgumentError] bila input non-kosong bukan URL http(s) absolut
  /// yang wajar (tanpa kredensial/query/fragment). Base path dipertahankan.
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
    if (uri.userInfo.isNotEmpty) {
      throw ArgumentError.value(
        raw,
        'proxyBase',
        'URL proxy tidak boleh memuat kredensial.',
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

  static String _normalizeOrEmpty(String raw) {
    try {
      return normalizeProxyBase(raw) ?? '';
    } on ArgumentError {
      return '';
    }
  }
}
