# Sonora Flutter

[![Flutter](https://img.shields.io/badge/Flutter-3.44+-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.12+-0175C2?logo=dart&logoColor=white)](https://dart.dev)
[![Android](https://img.shields.io/badge/Platform-Android-3DDC84?logo=android&logoColor=white)](https://developer.android.com)
[![License: MIT](https://img.shields.io/badge/License-MIT-red.svg)](LICENSE)

Klien musik Android berbasis Flutter untuk proxy backend mandiri (*self-hosted*) [Sonora Music](https://github.com/MuhWldns/Sonora-Music).

Aplikasi ini berfokus pada pengalaman mendengarkan musik YouTube Music yang bersih, cepat, dan independen. Klien Flutter menangani antarmuka pengguna serta pemutaran audio native di Android, sedangkan proxy Node.js bertugas menangani deciphering InnerTube, penanganan PO token (BotGuard/WebPO), dan relay streaming audio. Klien tidak pernah berkomunikasi langsung dengan YouTube/InnerTube dan tidak menyimpan kredensial apa pun.

## Arsitektur

```
┌────────────────────────────────────────┐
│           Sonora Flutter               │
│  (Flutter UI + just_audio Media Engine)│
└──────────────────┬─────────────────────┘
                   │
                   │ HTTP JSON (/home, /search, /browse, /healthz)
                   │ Audio Stream Relay (/stream?videoId=...)
                   ▼
┌────────────────────────────────────────┐
│          Sonora Node Proxy             │
│   (Hono + InnerTube + BotGuard PO)     │
└──────────────────┬─────────────────────┘
                   │
                   │ InnerTube API & Google Video
                   ▼
┌────────────────────────────────────────┐
│            YouTube Music               │
└────────────────────────────────────────┘
```

> **Catatan PO token:** klien Flutter tidak mengimplementasikan deciphering token maupun BotGuard. Seluruh proses tersebut ditangani proxy Sonora di sisi server, sehingga klien cukup melakukan streaming melalui `/stream?videoId=...`.

## Fitur

- **Beranda** — feed rekomendasi lagu dan playlist publik dari endpoint proxy `/home`, dengan skeleton loading dan status koneksi yang informatif.
- **Pencarian** — pencarian *debounced* dengan filter kategori (Semua, Lagu, Video, Album, Artis, Playlist) serta riwayat pencarian lokal berbasis SQLite.
- **Browse** — halaman detail album, artis, atau playlist dengan header artwork besar, aksi *Putar semua* dan *Acak*, serta daftar lagu bernomor.
- **Pemutar musik native**
  - Mini-player persisten bergaya dock kaca (blur) dengan micro-bar progres.
  - Full player dengan artwork ber-glow ambien, seekbar interaktif, dan kontrol transport lengkap.
  - Lirik tersinkronisasi dari [LRCLIB](https://lrclib.net): baris aktif disorot, auto-scroll mengikuti lagu, ketuk baris untuk melompat.
  - Mode acak (*shuffle*) dan pengulangan (*repeat off / all / one*).
  - Antrean lagu yang dapat diurutkan, diputar ulang, dan dihapus.
  - Penandaan lagu favorit yang tersimpan di perangkat.
- **Pemutaran latar belakang Android**
  - Berjalan sebagai Foreground Service (`audio_service` + `just_audio`).
  - Notifikasi kontrol media native dengan artwork.
  - Penanganan interupsi audio (panggilan masuk, headphone dicabut).
- **Konfigurasi proxy**
  - Input URL proxy melalui menu Pengaturan, tanpa alamat server yang di-hardcode.
  - Pengujian koneksi langsung ke endpoint `/healthz`.
  - Penghentian audio otomatis saat endpoint berganti untuk mencegah kebocoran stream antar-server.
- **Penyimpanan lokal (SQLite, 3 tabel)**
  - `playback_history`: riwayat pemutaran di perangkat (maksimal 100 entri terbaru).
  - `favorite_tracks`: daftar lagu favorit offline.
  - `search_history`: riwayat kata kunci pencarian beserta frekuensi.
- **Desain Nocturne Audio** — tema gelap atmosferik dengan aksen crimson tunggal (`#E03A3E`), tipografi Plus Jakarta Sans, dan dukungan tema terang sebagai derivasi.

## Memulai

### Prasyarat

- Flutter SDK 3.44.2 atau lebih baru (Dart 3.12+).
- Android SDK, API level 21 sampai 36+.
- Instance proxy Sonora Music yang aktif dan dapat diakses.

### Instalasi

1. Clone repository:

   ```sh
   git clone https://github.com/MuhWldns/Sonora-flutter.git
   cd Sonora-flutter
   ```

2. Unduh dependensi:

   ```sh
   flutter pub get
   ```

3. Jalankan pada perangkat atau emulator Android:

   ```sh
   flutter run
   ```

4. Buka menu **Pengaturan**, masukkan URL proxy Sonora Anda (misalnya `https://sonora.example.com`), tekan **Tes koneksi**, lalu **Simpan**.

Sebagai alternatif, URL proxy dapat disematkan saat build melalui `--dart-define` sehingga tidak perlu diisi manual:

```sh
flutter run --dart-define=SONORA_PROXY_URL=https://sonora.example.com
```

### Build APK

```sh
flutter build apk --debug
```

Hasil build tersedia di `build/app/outputs/flutter-apk/app-debug.apk`. Untuk build release dengan signing key milik Anda sendiri:

```sh
flutter build apk --release
```

## Pengujian

Pengujian mencakup boundary data, parsing model, normalisasi dan sanitasi URL, persistensi pengaturan, serta operasi basis data lokal:

```sh
# Analisis statis (harus 0 issues)
flutter analyze

# Unit test dan regression suite (28 test)
flutter test
```

## Struktur Proyek

```
lib/
├── main.dart                     # Bootstrap asinkron: settings, API, AudioService, SQLite
├── data/
│   ├── music_models.dart         # Model MusicItem & MusicSection (toleran terhadap JSON InnerTube)
│   ├── settings_store.dart       # Persistensi URL proxy (SharedPreferences)
│   ├── sonora_api.dart           # Klien HTTP untuk proxy Sonora
│   ├── lyrics_store.dart         # Klien LRCLIB dan parser LRC (lirik tersinkronisasi)
│   └── local_database.dart       # SQLite lokal: history, favorites, searches
├── playback/
│   └── sonora_audio_handler.dart # AudioHandler, notifikasi native, pemutaran latar belakang
└── ui/
    ├── sonora_app.dart           # Root widget dan pemasangan tema
    ├── theme.dart                # Tema Nocturne Audio (gelap/terang), token warna & tipografi
    ├── app_scope.dart            # SonoraScope (InheritedWidget) penyedia dependensi
    ├── root_shell.dart           # Navigasi tab utama dan penempatan mini-player
    ├── player_actions.dart       # Fasad aksi pemutar (play, queue, browse)
    ├── player/                   # PlayerController, mini-player, full player, lirik, antrean
    ├── screens/                  # Layar Beranda, Cari, Browse, dan Pengaturan
    └── widgets/                  # Komponen bersama: baris lagu, shelf, skeleton, state UI
```

## Lisensi

Proyek ini dilisensikan di bawah [Lisensi MIT](LICENSE).

```
Copyright (c) 2026 MuhWldns
```

Lisensi MIT merupakan lisensi perangkat lunak bebas yang permisif. Anda bebas menggunakan, menyalin, memodifikasi, menggabungkan, mendistribusikan, mensublisensikan, dan menjual salinan perangkat lunak ini, dengan satu-satunya kewajiban untuk menyertakan pemberitahuan hak cipta dan izin di atas pada setiap salinan atau bagian yang substantif dari perangkat lunak. Perangkat lunak disediakan "sebagaimana adanya", tanpa jaminan dalam bentuk apa pun; pembuat dan pemegang hak cipta tidak bertanggung jawab atas klaim, kerusakan, atau kewajiban apa pun yang timbul dari penggunaannya.

### Pemberitahuan dan Batasan Penggunaan

- Proyek ini **tidak berafiliasi, tidak didukung, dan tidak terhubung** dengan YouTube, Google LLC, maupun entitas afiliasinya mana pun. "YouTube" dan "YouTube Music" adalah merek dagang milik Google LLC dan digunakan di sini semata untuk keperluan identifikasi.
- Aplikasi ini **tidak meng-hosting, mengunggah, atau menyimpan** berkas musik berhak cipta. Seluruh audio dialirkan melalui proxy Sonora yang dioperasikan sendiri oleh pengguna dan tetap tunduk pada ketentuan layanan penyedia konten terkait.
- Aplikasi ini dimaksudkan untuk **penggunaan pribadi** (*self-hosted personal music player*). Setiap pengguna bertanggung jawab sepenuhnya atas kepatuhan terhadap hukum dan ketentuan layanan yang berlaku di yurisdiksinya masing-masing.
