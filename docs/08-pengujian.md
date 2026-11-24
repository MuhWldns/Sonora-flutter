# Pengujian (Testing) Sonora Flutter

Dokumen ini menjelaskan cara menjalankan pengujian Sonora Flutter: suite hermetis otomatis yang aman dijalankan kapan saja, dan uji kotak hitam UI yang **manual-only** karena menyentuh jaringan nyata.

---

## 1. Suite Hermetis Otomatis (`flutter test`)

Seluruh suite otomatis bersifat **hermetis murni** (in-memory test doubles, `MockClient`, `sqflite_common_ffi`) — **tanpa jaringan, tanpa proses native eksternal**, dan aman dijalankan di CI:

```sh
flutter test
```

### Isi suite

| Berkas | Cakupan | Jumlah Test |
| :--- | :--- | :---: |
| `test/data_test.dart` | Kontrak boundary lapisan data: serialisasi model, normalisasi `SettingsStore` (audio quality, equalizer, theme mode, cache limit), ketahanan `SonoraApi`, manipulasi direktori cache disk. | 34 |
| `test/database_test.dart` | Integritas basis data SQLite nyata (`databaseFactoryFfi`): *playback history limit 100*, relasi playlist, favorit, filter *skip 15 detik*. | 5 |
| `test/youtube_auth_test.dart` | Sesi & login YouTube Music: `sapisidHash`, `sapisidFromCookie`, `YoutubeAuthService.capture/restore/signOut`, header sesi innertube (SAPISIDHASH, `onBehalfOfUser` tanpa sufiks `\|\|`), `validateSession` berbasis status, `fetchAccountInfo` (nama/email/avatar), `fetchHomeSections`, dan pencarian sesi masuk. | 37 |
| `test/blackbox_ui_test.dart` | Uji kotak hitam UI (`WidgetTester`) 6 modul fungsional. **Tidak dihitung sebagai suite hermetis** — lihat §2. | 23 |
| **Total hermetis** | `data` + `database` + `youtube_auth` | **76** |

> Total keseluruhan bila `blackbox_ui_test.dart` ikut dijalankan: 99 test. Suite hermetis inti (data + database + youtube_auth) = 76 test.

### Menjalankan satu berkas

```sh
flutter test test/youtube_auth_test.dart
flutter test test/data_test.dart
flutter test test/database_test.dart
```

---

## 2. Uji Kotak Hitam UI — MANUAL ONLY (`test/blackbox_ui_test.dart`)

`test/blackbox_ui_test.dart` **tidak boleh dijalankan di suite hermetis/CI**. File ini melakukan pengujian UI yang menyentuh **jaringan nyata** (request live ke YouTube/CDN), sehingga:

- **Jangan** jalankan `flutter test` tanpa filter bila Anda ingin menghindarinya — atau jalankan hanya berkas hermetis di atas.
- **Jangan** masukkan ke pipeline CI.

### Cara menjalankannya secara sengaja

Jalankan langsung terhadap perangkat/emulator dengan koneksi jaringan nyata:

```sh
flutter test test/blackbox_ui_test.dart
```

### Cakupan

23 test yang memetakan 6 modul pertama matriks kasus uji di `docs/testing/01-blackbox-testing.md`; matriks manual itu kini memuat **8 modul / 44 kasus uji**, dengan dua modul terakhir (`TC-ACC`, `TC-PRS`) diverifikasi manual di perangkat karena bergantung pada sesi akun Google nyata:

- `TC-SET` — Pengaturan, ekstensi Add-on proxy, manajemen cache.
- `TC-PLY` — Pemutar audio & layanan latar belakang.
- `TC-SRC` — Pencarian & eksplorasi.
- `TC-LIB` — Koleksi, playlist lokal, statistik.
- `TC-LYR` — Lirik tersinkronisasi.
- `TC-BRW` — Browse & ketahanan jaringan (auto-fallback saat proxy offline).
- `TC-ACC` — Akun & login YouTube Music (WebView Google, validasi sesi, kartu profil, restore sesi terenkripsi, konten personal Koleksi).
- `TC-PRS` — Beranda & pencarian personal (rak YouTube Music, fallback pencarian anonim, penyembunyian rak kosong, fallback lirik).

Karena menyentuh jaringan nyata, hasilnya bergantung pada ketersediaan endpoint eksternal; kegagalan pada file ini bukan indikasi regresi kode lokal.