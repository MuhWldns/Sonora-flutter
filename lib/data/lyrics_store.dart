/// Sumber lirik untuk Sonora: klien LRCLIB (lrclib.net).
///
/// Lirik diambil langsung dari LRCLIB oleh klien (tanpa melalui proxy Sonora)
/// berdasarkan judul + artis. API gratis tanpa kunci; kegagalan jaringan atau
/// lirik yang tidak ditemukan selalu menghasilkan `null`, bukan galat — lirik
/// adalah fitur opsional dan tidak boleh mengganggu pemutaran.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Satu baris lirik tersinkronisasi.
@immutable
class LrcLine {
  const LrcLine({required this.timestamp, required this.text});

  final Duration timestamp;
  final String text;
}

/// Hasil lirik: baris tersinkronisasi (LRC) atau teks polos.
@immutable
class LrcLyrics {
  const LrcLyrics({this.synced = const <LrcLine>[], this.plain});

  final List<LrcLine> synced;
  final String? plain;

  bool get hasSynced => synced.isNotEmpty;

  /// Indeks baris aktif pada [position], atau `null` bila belum ada yang aktif.
  int? activeIndexAt(Duration position, {Duration offset = const Duration(milliseconds: 300)}) {
    final Duration shifted = position - offset;
    int? active;
    for (int i = 0; i < synced.length; i++) {
      if (synced[i].timestamp <= shifted) {
        active = i;
      } else {
        break;
      }
    }
    return active;
  }
}

/// Klien LRCLIB.
class LyricsRepository {
  LyricsRepository({http.Client? client, this.baseAuthority = 'lrclib.net'})
      : _client = client ?? http.Client();

  final http.Client _client;

  /// Host LRCLIB; bisa diarahkan ke mirror lain saat pengujian.
  final String baseAuthority;

  static const String _userAgent =
      'Sonora Flutter/1.0 (https://github.com/MuhWldns/Sonora-flutter)';
  static const Duration _timeout = Duration(seconds: 10);

  /// Menutup klien HTTP bila dimiliki sendiri.
  void dispose() {
    _client.close();
  }

  /// Mencari lirik untuk sebuah lagu. Mengembalikan `null` bila tidak ditemukan
  /// atau terjadi kegagalan jaringan.
  Future<LrcLyrics?> find({
    required String track,
    required String artist,
    int? durationMs,
  }) async {
    final String trackName = track.trim();
    final String artistName = artist.trim();
    if (trackName.isEmpty) return null;

    // 1) Pencocokan langsung (paling akurat saat durasi diketahui).
    final Map<String, String> query = <String, String>{
      'track_name': trackName,
      if (artistName.isNotEmpty) 'artist_name': artistName,
      if (durationMs != null && durationMs > 0)
        'duration': (durationMs ~/ 1000).toString(),
    };
    final LrcLyrics? direct = await _tryGet(
      Uri.https(baseAuthority, '/api/get', query),
    );
    if (direct != null) return direct;

    // 2) Pencarian longgar, ambil kandidat pertama yang punya lirik.
    if (artistName.isEmpty) return null;
    return _trySearch(Uri.https(baseAuthority, '/api/search', <String, String>{
      'track_name': trackName,
      'artist_name': artistName,
    }));
  }

  Future<LrcLyrics?> _tryGet(Uri uri) async {
    try {
      final http.Response response = await _client
          .get(uri, headers: const <String, String>{'User-Agent': _userAgent})
          .timeout(_timeout);
      if (response.statusCode != 200) return null;
      final Object? decoded = jsonDecode(utf8.decode(response.bodyBytes));
      return _fromRecord(decoded);
    } on Exception {
      return null;
    }
  }

  Future<LrcLyrics?> _trySearch(Uri uri) async {
    try {
      final http.Response response = await _client
          .get(uri, headers: const <String, String>{'User-Agent': _userAgent})
          .timeout(_timeout);
      if (response.statusCode != 200) return null;
      final Object? decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! List) return null;
      for (final Object? record in decoded) {
        final LrcLyrics? lyrics = _fromRecord(record);
        if (lyrics != null && (lyrics.hasSynced || lyrics.plain != null)) {
          return lyrics;
        }
      }
      return null;
    } on Exception {
      return null;
    }
  }

  LrcLyrics? _fromRecord(Object? value) {
    if (value is! Map) return null;
    final Object? synced = value['syncedLyrics'];
    final Object? plain = value['plainLyrics'];
    final List<LrcLine> lines =
        synced is String ? parseSynced(synced) : const <LrcLine>[];
    final String? plainText = plain is String && plain.isNotEmpty ? plain : null;
    if (lines.isEmpty && plainText == null) return null;
    return LrcLyrics(synced: lines, plain: plainText);
  }

  /// Mem-parse konten LRC (`[mm:ss.xx] teks`) menjadi daftar baris urut.
  static List<LrcLine> parseSynced(String raw) {
    final RegExp tag = RegExp(r'^\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');
    final List<LrcLine> result = <LrcLine>[];
    for (final String rawLine in const LineSplitter().convert(raw)) {
      String rest = rawLine.trim();
      if (rest.isEmpty) continue;
      Duration? stamp;
      // Satu baris LRC bisa memuat beberapa penanda waktu.
      while (true) {
        final RegExpMatch? match = tag.firstMatch(rest);
        if (match == null) break;
        final int minutes = int.parse(match.group(1)!);
        final int seconds = int.parse(match.group(2)!);
        final String fraction = match.group(3) ?? '0';
        final int millis = switch (fraction.length) {
          1 => int.parse(fraction) * 100,
          2 => int.parse(fraction) * 10,
          _ => int.parse(fraction.substring(0, 3)),
        };
        stamp ??= Duration(
          minutes: minutes,
          seconds: seconds,
          milliseconds: millis,
        );
        rest = rest.substring(match.end).trim();
      }
      if (stamp == null) continue; // Lewati tag metadata seperti [ar:], [ti:].
      if (rest.isEmpty) continue;
      result.add(LrcLine(timestamp: stamp, text: rest));
    }
    result.sort((LrcLine a, LrcLine b) => a.timestamp.compareTo(b.timestamp));
    return result;
  }
}
