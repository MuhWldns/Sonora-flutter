/// Mesin keadaan pengambilan lirik untuk tampilan lirik pemutar.
///
/// Dipisahkan dari widget agar alurnya dapat diuji secara hermetik: kegagalan
/// jaringan, pagu waktu 12 detik, lagu yang berganti di tengah permintaan,
/// dan percobaan ulang semuanya ditangani di sini. Lirik bersifat opsional —
/// kegagalan apa pun berakhir pada fase [LyricsPhase.unavailable], bukan
/// galat yang mengganggu pemutaran.
library;

import 'package:flutter/foundation.dart';

import '../../data/lyrics_store.dart';

/// Fase pemuatan lirik pada tampilan lirik.
enum LyricsPhase {
  /// Belum ada permintaan (tampilan baru dibuka); tampil seperti memuat.
  idle,

  /// Sedang mengambil lirik untuk lagu aktif.
  loading,

  /// Lirik berhasil dimuat.
  ready,

  /// Lirik tidak tersedia (gagal, hangus pagu waktu, atau memang tidak ada).
  unavailable,
}

/// Fungsi pengambil lirik untuk lagu aktif. Berbentuk typedef agar
/// pengujian dapat menyuntikkan fetch tiruan tanpa jaringan.
typedef LyricsFetcher = Future<LrcLyrics?> Function();

/// Pengendali fase lirik: `loading → ready/unavailable`, mendukung percobaan
/// ulang dan membuang balasan basi ketika lagu berganti di tengah permintaan.
class LyricsLoader extends ChangeNotifier {
  LyricsLoader({
    required this.fetch,
    this.timeout = const Duration(seconds: 12),
  });

  /// Sumber lirik; boleh mengembalikan `null` atau melempar — keduanya
  /// berarti lirik tidak tersedia.
  final LyricsFetcher fetch;

  /// Pagu total pengambilan; melewatinya dianggap tidak tersedia sehingga
  /// tidak ada skeleton yang menggantung selamanya.
  final Duration timeout;

  LyricsPhase _phase = LyricsPhase.idle;
  LrcLyrics? _lyrics;
  String _key = '';
  int _generation = 0;
  bool _disposed = false;

  /// Fase saat ini yang diamati UI.
  LyricsPhase get phase => _phase;

  /// Lirik yang berhasil dimuat; `null` kecuali pada fase [LyricsPhase.ready].
  LrcLyrics? get lyrics => _lyrics;

  /// Kunci lagu (videoId) yang sedang dimuat.
  String get key => _key;

  /// Menyiapkan muat untuk [trackKey] tanpa memberi tahu pendengar.
  ///
  /// Dipakai saat widget membangun ulang karena lagu berganti: pembangunan
  /// ulang yang sedang berjalan langsung membaca fase terbaru (tidak ada
  /// lirik lagu lama yang sempat terlihat), sementara pengambilan penuh
  /// mengikuti lewat [load] dengan `force: true`.
  void prepare(String trackKey) {
    if (_disposed || trackKey == _key) return;
    _key = trackKey;
    _generation++; // batalkan balasan basi yang masih dalam perjalanan.
    _lyrics = null;
    _phase = trackKey.isEmpty ? LyricsPhase.unavailable : LyricsPhase.loading;
  }

  /// Memuat lirik untuk [trackKey]. Pemanggilan dengan kunci sama diabaikan
  /// kecuali [force] benar (dipakai oleh percobaan ulang).
  Future<void> load(String trackKey, {bool force = false}) async {
    if (_disposed) return;
    if (trackKey.isEmpty) {
      // Tanpa kunci tidak ada yang bisa dicari; langsung tidak tersedia.
      _key = '';
      _generation++;
      _lyrics = null;
      _phase = LyricsPhase.unavailable;
      notifyListeners();
      return;
    }
    if (!force && trackKey == _key) return;
    _key = trackKey;
    final int generation = ++_generation;
    _lyrics = null;
    _phase = LyricsPhase.loading;
    notifyListeners();
    LrcLyrics? result;
    try {
      result = await fetch().timeout(timeout);
    } catch (_) {
      // Lirik opsional: kegagalan apa pun hanya berarti tidak tersedia.
      result = null;
    }
    // Balasan basi: lagu sudah berganti atau ada percobaan yang lebih baru.
    if (_disposed || generation != _generation) return;
    _phase = result == null ? LyricsPhase.unavailable : LyricsPhase.ready;
    _lyrics = result;
    notifyListeners();
  }

  /// Memuat ulang lirik untuk lagu yang sedang aktif.
  Future<void> retry() => load(_key, force: true);

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
