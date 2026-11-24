# 06. Troubleshooting & Catatan Masalah

Dokumen ini mencatat masalah nyata yang pernah terjadi pada Sonora Flutter, akar penyebab yang telah diverifikasi, serta solusi yang diterapkan. Tujuannya agar pola kegagalan serupa dapat dikenali dan ditangani lebih cepat di kemudian hari.

## Ringkasan

| ID | Masalah | Lapisan | Penyebab Utama | Solusi |
| :--- | :--- | :--- | :--- | :--- |
| **M-01** | Pemutaran gagal: `HttpDataSource$InvalidResponseCodeException: Response code: 403` | data / playback | CDN GoogleVideo menolak unduhan penuh untuk sebagian URL format audio-only | Validasi kandidat URL sebelum dipakai + fallback bertingkat AAC → Opus → muxed |
| **M-02** | Pencarian gagal: `FormatException: Invalid radix-10 number (at character 1)` (sumber `Streamed`) dan/atau `NoSuchMethodError: ... getT` | data | Kerentanan parser pencarian pada pustaka `youtube_explode_dart` | Pencarian memakai innertube API langsung dengan parsing defensif |
| **M-03** | Debug assert: `ListTile background color or ink splashes may be invisible` | ui | `ListTile` tidak memiliki ancestor `Material` | Bungkus tile dengan `Material(color: Colors.transparent)` |

---

## M-01 — Pemutaran gagal dengan HTTP 403

### Gejala

```
E/ExoPlayerImplInternal: Playback error
  Caused by: androidx.media3.datasource.HttpDataSource$InvalidResponseCodeException: Response code: 403
E/AudioPlayer: TYPE_SOURCE: Response code: 403
```

Terjadi konsisten pada video tertentu, meski resolusi URL stream sukses dan URL terlihat valid.

### Akar Penyebab

URL stream yang dihasilkan resolusi manifest **valid**, tetapi server CDN GoogleVideo **membatasi unduhan penuh** untuk format audio-only pada sejumlah video:

- Permintaan **tanpa header `Range`** (pola request pertama ExoPlayer untuk `ProgressiveMediaPeriod`) → **403**.
- Permintaan range terbuka `bytes=0-` → **403**.
- Permintaan range kecil (`bytes=0-1024`) tetap dilayani → **206**.
- Format **muxed** (itag 18) dilayani penuh tanpa pembatasan → **200 / 206**.

Ini bukan persoalan kredensial atau konteks permintaan semata: dengan client yang sama, video lain menghasilkan URL yang sepenuhnya dapat diputar. Pembatasan bersifat per-video/per-format di sisi server.

### Bukti (matriks uji pada video `zlw7Q5Td8PY`, User-Agent aplikasi)

| Pola permintaan | audio-only itag 140 / 251 | muxed itag 18 |
| :--- | :--- | :--- |
| GET tanpa `Range` | 403 | **200** |
| `Range: bytes=0-` | 403 | 206 |
| `Range: bytes=0-1024` | 206 | 206 |
| `Range: bytes=0-10000000` | 403 | — |

### Solusi

`YouTubeMusicService.resolveStreamUri` kini bekerja sebagai berikut:

1. Mengurutkan kandidat format: **AAC/M4A (itag 140)** → **audioOnly bitrate tertinggi (Opus itag 251)** → **muxed MP4 (itag 18)**.
2. Menguji setiap kandidat dengan GET tanpa `Range` (pola yang sama dengan request pertama ExoPlayer); body respons tidak dibaca agar tidak mengunduh isi file.
3. Memakai kandidat pertama yang dilayani server (status 2xx/3xx); hasilnya di-cache 4 jam.
4. Bila seluruh kandidat gagal, mengembalikan `null` sehingga lapisan playback menampilkan pesan galat generik.

### Dampak & Batasan

Untuk video yang URL audio-only-nya dibatasi server, audio diputar melalui format muxed itag 18 (AAC 128 kbps + video 360p). Kualitas audio sedikit lebih rendah, tetapi pemutaran tetap berjalan dan deterministik.

---

## M-02 — Pencarian gagal: FormatException / NoSuchMethodError

### Gejala

```
I/flutter: [YouTubeMusicService] Pencarian "Top Music Hits 2026" gagal: FormatException: Invalid radix-10 number (at character 1)
I/flutter: Streamed
I/flutter: ^
I/flutter: [YouTubeMusicService] Pencarian "..." gagal: NoSuchMethodError: Class '_Map<String, dynamic>' has no instance method 'getT'.
```

Feed trending dan hasil pencarian kosong; kegagalan bersifat intermiten karena bergantung pada bentuk respons YouTube saat itu.

### Akar Penyebab

Dua kerentanan parsing pada pustaka `youtube_explode_dart` (terverifikasi masih ada pada commit master `44a39a65`):

- `helpers_extension.dart:185` — `StringUtility2.toDateTime()` memanggil `int.parse(parts.first)` tanpa pengaman untuk teks `publishedTimeText` berpola `Streamed ...` → `FormatException`.
- `search_page.dart:181` — `.getT<String>('text')` diakses melalui `firstOrNull` pada `List<dynamic>` sehingga menjadi *dynamic dispatch* ke `Map` → `NoSuchMethodError` ketika `viewCountText` berbentuk `runs`.

### Solusi

`YouTubeMusicService.search` tidak lagi memakai parser pencarian pustaka. Pencarian kini dilakukan dengan POST langsung ke endpoint innertube `youtubei/v1/search` (client WEB) dan memetakan setiap `videoRenderer` secara rekursif memakai helper null-safe (`_runsText`, `_plainText`) — tanpa `int.parse`, tanpa *cast* keras, dan tidak bergantung pada struktur sarang respons tertentu. Pustaka tetap dipakai untuk resolusi stream (`getManifest`) yang berjalan normal. Kegagalan pencarian tetap dicatat melalui `debugPrint` dan mengembalikan list kosong agar UI turun dengan anggun (*graceful degradation*).

---

## M-03 — Debug assert ListTile

### Gejala

```
Assert: "ListTile background color or ink splashes may be invisible"
```

### Akar Penyebab

`ListTile` menggambar latar dan *ink ripple* pada ancestor `Material` terdekat. Ketika tile ditempatkan langsung di dalam `Container` berwarna (bukan `Material`), efek tersebut tidak pernah terlihat dan Flutter menampilkan assert pada mode debug.

### Solusi

Bungkus tile dengan `Material(color: Colors.transparent)`:

- `SwitchListTile.adaptive` pada kartu Sonora Node Proxy di `lib/ui/screens/settings.dart`.
- `ListTile` pilihan playlist pada `lib/ui/player_actions.dart`.

---

## Catatan Dependensi

`pubspec.yaml` memakai `dependency_overrides` untuk `youtube_explode_dart` menuju commit master upstream (`44a39a65…`). Alasannya: versi pub 3.1.0 menghasilkan URL stream yang ditolak CDN saat diputar, sedangkan client default pada master menghasilkan URL yang dapat diputar. Override ini disengaja — **jangan dihapus** sebelum versi pub memuat perbaikan client stream.

## Catatan Pengujian

- Suite hermetik: `test/data_test.dart` + `test/database_test.dart` (35 test) — tanpa jaringan, aman dijalankan kapan pun.
- `test/blackbox_ui_test.dart` menjalankan pengujian terhadap jaringan nyata (±1 menit per kasus) — jalankan secara selektif, jangan masukkan ke rutinitas `flutter test` penuh.
