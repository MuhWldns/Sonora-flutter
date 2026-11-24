/// Pengujian hermetik untuk [LyricsLoader]: alur fase lirik tanpa jaringan.
///
/// Semua skenario memakai fungsi fetch tiruan — gagal, melempar, menggantung
/// (pagu waktu), sukses, dan balasan basi saat lagu berganti.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonora_flutter/data/lyrics_store.dart';
import 'package:sonora_flutter/ui/player/lyrics_loader.dart';

void main() {
  group('LyricsLoader', () {
    test('kegagalan pengambilan menghasilkan unavailable, bukan loading', () async {
      final LyricsLoader loader = LyricsLoader(fetch: () async => null);
      await loader.load('vid-1');
      expect(loader.phase, LyricsPhase.unavailable);
      expect(loader.lyrics, isNull);
      loader.dispose();
    });

    test('fetch yang melempar juga menghasilkan unavailable', () async {
      final LyricsLoader loader = LyricsLoader(
        fetch: () async => throw Exception('jaringan putus'),
      );
      await loader.load('vid-1');
      expect(loader.phase, LyricsPhase.unavailable);
      loader.dispose();
    });

    test('melewati pagu waktu menghasilkan unavailable', () async {
      final LyricsLoader loader = LyricsLoader(
        // Tidak pernah selesai — meniru jaringan yang menggantung.
        fetch: () => Completer<LrcLyrics?>().future,
        timeout: const Duration(milliseconds: 20),
      );
      await loader.load('vid-1');
      expect(loader.phase, LyricsPhase.unavailable);
      loader.dispose();
    });

    test('lirik berhasil menghasilkan ready beserta liriknya', () async {
      final LrcLyrics lyrics = LrcLyrics(
        synced: <LrcLine>[
          const LrcLine(timestamp: Duration.zero, text: 'baris pertama'),
          const LrcLine(timestamp: Duration(seconds: 5), text: 'baris kedua'),
        ],
      );
      final LyricsLoader loader = LyricsLoader(fetch: () async => lyrics);
      await loader.load('vid-1');
      expect(loader.phase, LyricsPhase.ready);
      expect(loader.lyrics, same(lyrics));
      loader.dispose();
    });

    test('listener melihat urutan fase loading lalu hasil akhir', () async {
      final LyricsLoader loader = LyricsLoader(fetch: () async => null);
      final List<LyricsPhase> phases = <LyricsPhase>[];
      loader.addListener(() => phases.add(loader.phase));
      await loader.load('vid-1');
      expect(
        phases,
        <LyricsPhase>[LyricsPhase.loading, LyricsPhase.unavailable],
      );
      loader.dispose();
    });

    test('kunci sama tidak memicu pengambilan ulang tanpa force', () async {
      int calls = 0;
      final LyricsLoader loader = LyricsLoader(fetch: () async {
        calls++;
        return null;
      });
      await loader.load('vid-1');
      await loader.load('vid-1');
      expect(calls, 1);
      expect(loader.phase, LyricsPhase.unavailable);
      loader.dispose();
    });

    test('retry memasuki fase loading lalu selesai sesuai fetch terbaru', () async {
      LrcLyrics? hasil = const LrcLyrics(plain: 'teks lirik');
      final LyricsLoader loader = LyricsLoader(fetch: () async => hasil);
      await loader.load('vid-1');
      expect(loader.phase, LyricsPhase.ready);

      // Percobaan ulang pertama gagal: loading lalu unavailable.
      hasil = null;
      final Future<void> gagal = loader.retry();
      expect(loader.phase, LyricsPhase.loading);
      await gagal;
      expect(loader.phase, LyricsPhase.unavailable);

      // Percobaan ulang kedua berhasil: loading lalu ready.
      hasil = const LrcLyrics(plain: 'teks lirik');
      final Future<void> sukses = loader.retry();
      expect(loader.phase, LyricsPhase.loading);
      await sukses;
      expect(loader.phase, LyricsPhase.ready);
      expect(loader.lyrics?.plain, 'teks lirik');
      loader.dispose();
    });

    test('balasan basi lagu lama tidak mengubah state lagu baru', () async {
      final Completer<LrcLyrics?> laguLama = Completer<LrcLyrics?>();
      Future<LrcLyrics?> Function() sumber = () => laguLama.future;
      final LyricsLoader loader = LyricsLoader(fetch: () => sumber());

      final Future<void> muatPertama = loader.load('lagu-a');
      expect(loader.phase, LyricsPhase.loading);

      // Lagu berganti; pengambilan lagu baru langsung selesai (tidak ada).
      sumber = () async => null;
      await loader.load('lagu-b');
      expect(loader.phase, LyricsPhase.unavailable);
      expect(loader.key, 'lagu-b');

      // Balasan basi lagu-a tiba belakangan; tidak boleh bocor ke lagu-b.
      laguLama.complete(const LrcLyrics(plain: 'lirik lagu lama'));
      await muatPertama;
      expect(loader.phase, LyricsPhase.unavailable);
      expect(loader.lyrics, isNull);
      loader.dispose();
    });

    test('prepare mengubah fase memuat tanpa memberi tahu pendengar', () async {
      final LyricsLoader loader = LyricsLoader(fetch: () async => null);
      int notifications = 0;
      loader.addListener(() => notifications++);
      loader.prepare('vid-2');
      expect(loader.phase, LyricsPhase.loading);
      expect(notifications, 0);
      loader.dispose();
    });

    test('kunci kosong langsung unavailable tanpa memanggil fetch', () async {
      int calls = 0;
      final LyricsLoader loader = LyricsLoader(fetch: () async {
        calls++;
        return null;
      });
      await loader.load('');
      expect(loader.phase, LyricsPhase.unavailable);
      expect(calls, 0);
      loader.dispose();
    });

    test('load setelah dispose tidak melempar dan tidak mengubah fase', () async {
      final LyricsLoader loader = LyricsLoader(fetch: () async => null);
      loader.dispose();
      await loader.load('vid-1');
      expect(loader.phase, LyricsPhase.idle);
    });
  });
}
