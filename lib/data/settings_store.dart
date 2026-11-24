/// Preferensi lokal Sonora: hanya base URL proxy.
///
/// Tidak ada cookie/rahasia yang disimpan. Nilai yang dimuat selalu
/// divalidasi; payload rusak diturunkan ke default aman.
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'music_models.dart';

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

/// Mode tema aplikasi yang dipilih pengguna.
enum AppThemeMode { sistem, gelap, terang }

/// Menyimpan dan mengamati base URL proxy.
class SettingsStore extends ChangeNotifier {
  SettingsStore._(this._preferences, this._proxyBase, this._proxyDraft);

  static const String _proxyBaseKey = 'sonora.proxyBase';
  static const String _proxyDraftKey = 'sonora.proxyDraft';
  static const String _audioQualityKey = 'sonora.audioQuality';
  static const String _themeModeKey = 'sonora.themeMode';
  static const String _cacheLimitKey = 'sonora.cacheLimitMb';
  static const String _equalizerEnabledKey = 'sonora.equalizerEnabled';
  static const String _equalizerBandsKey = 'sonora.equalizerBands';

  /// Default opsional dari build (`--dart-define=SONORA_PROXY_URL=...`).
  static const String _environmentDefault =
      String.fromEnvironment('SONORA_PROXY_URL');

  final SharedPreferences _preferences;
  String _proxyBase;
  String _proxyDraft;
  AudioQuality _audioQuality = AudioQuality.auto;
  AppThemeMode _themeMode = AppThemeMode.sistem;
  int _cacheLimitMb = 500;
  bool _equalizerEnabled = false;
  List<int> _equalizerBands = const <int>[0, 0, 0, 0, 0];

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

    final SettingsStore store = SettingsStore._(prefs, proxyBase, proxyDraft)
      .._audioQuality = _parseAudioQuality(prefs.get(_audioQualityKey))
      .._themeMode = _parseThemeMode(prefs.get(_themeModeKey))
      .._cacheLimitMb = _parseCacheLimitMb(prefs.get(_cacheLimitKey))
      .._equalizerEnabled = prefs.getBool(_equalizerEnabledKey) ?? false
      .._equalizerBands = _parseEqualizerBands(prefs.get(_equalizerBandsKey));
    return store;
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

  /// Preferensi kualitas audio untuk pemilihan format stream.
  AudioQuality get audioQuality => _audioQuality;

  Future<void> setAudioQuality(AudioQuality value) async {
    if (value == _audioQuality) return;
    final String raw = switch (value) {
      AudioQuality.best => 'best',
      AudioQuality.auto => 'auto',
      AudioQuality.hemat => 'hemat',
    };
    await _persistString(
      _audioQualityKey,
      raw,
      'Gagal menyimpan preferensi kualitas audio.',
    );
    _audioQuality = value;
    notifyListeners();
  }

  /// Mode tema yang dipilih (sistem / gelap / terang).
  AppThemeMode get themeMode => _themeMode;

  Future<void> setThemeMode(AppThemeMode value) async {
    if (value == _themeMode) return;
    final String raw = switch (value) {
      AppThemeMode.sistem => 'system',
      AppThemeMode.gelap => 'gelap',
      AppThemeMode.terang => 'terang',
    };
    await _persistString(
      _themeModeKey,
      raw,
      'Gagal menyimpan preferensi tema.',
    );
    _themeMode = value;
    notifyListeners();
  }

  /// Batas cache audio dalam MB. `0` berarti tanpa batas.
  int get cacheLimitMb => _cacheLimitMb;

  Future<void> setCacheLimitMb(int value) async {
    if (value == _cacheLimitMb) return;
    final saved = await _preferences.setInt(_cacheLimitKey, value);
    if (!saved) {
      throw const SettingsPersistenceException(
        'Gagal menyimpan batas cache. Perubahan tidak diterapkan.',
      );
    }
    _cacheLimitMb = value;
    notifyListeners();
  }

  /// `true` bila equalizer Android aktif.
  bool get equalizerEnabled => _equalizerEnabled;

  Future<void> setEqualizerEnabled(bool value) async {
    if (value == _equalizerEnabled) return;
    final saved = await _preferences.setBool(_equalizerEnabledKey, value);
    if (!saved) {
      throw const SettingsPersistenceException(
        'Gagal menyimpan status equalizer. Perubahan tidak diterapkan.',
      );
    }
    _equalizerEnabled = value;
    notifyListeners();
  }

  /// Gain tiap band equalizer dalam dB (5 nilai, rentang -15..15).
  List<int> get equalizerBands => List<int>.unmodifiable(_equalizerBands);

  Future<void> setEqualizerBands(List<int> gains) async {
    final List<int> normalized = _normalizeBands(gains);
    if (listEquals(normalized, _equalizerBands)) return;
    await _persistString(
      _equalizerBandsKey,
      normalized.join(','),
      'Gagal menyimpan pengaturan equalizer.',
    );
    _equalizerBands = normalized;
    notifyListeners();
  }

  Future<void> _persistString(String key, String value, String errorMessage) async {
    final saved = await _preferences.setString(key, value);
    if (!saved) throw SettingsPersistenceException(errorMessage);
  }

  static List<int> _normalizeBands(List<int> gains) {
    final List<int> out = <int>[];
    for (var i = 0; i < 5; i++) {
      final int v = i < gains.length ? gains[i] : 0;
      out.add(v.clamp(-15, 15));
    }
    return out;
  }

  static AudioQuality _parseAudioQuality(Object? stored) {
    if (stored is String) {
      switch (stored) {
        case 'best':
          return AudioQuality.best;
        case 'hemat':
          return AudioQuality.hemat;
        case 'auto':
          return AudioQuality.auto;
      }
    }
    return AudioQuality.auto;
  }

  static AppThemeMode _parseThemeMode(Object? stored) {
    if (stored is String) {
      switch (stored) {
        case 'gelap':
          return AppThemeMode.gelap;
        case 'terang':
          return AppThemeMode.terang;
        case 'system':
          return AppThemeMode.sistem;
      }
    }
    return AppThemeMode.sistem;
  }

  static int _parseCacheLimitMb(Object? stored) {
    int? value;
    if (stored is int) value = stored;
    if (stored is String) value = int.tryParse(stored);
    if (value == null) return 500;
    if (value == 0) return 0;
    if (value >= 50 && value <= 4096) return value;
    return 500;
  }

  static List<int> _parseEqualizerBands(Object? stored) {
    if (stored is! String || stored.isEmpty) return const <int>[0, 0, 0, 0, 0];
    final List<String> parts = stored.split(',');
    if (parts.length != 5) return const <int>[0, 0, 0, 0, 0];
    final List<int> out = <int>[];
    for (final String part in parts) {
      final int? v = int.tryParse(part.trim());
      if (v == null || v < -15 || v > 15) return const <int>[0, 0, 0, 0, 0];
      out.add(v);
    }
    return out;
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
