# Sonora-flutter

[![Flutter](https://img.shields.io/badge/Flutter-3.44+-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.12+-0175C2?logo=dart&logoColor=white)](https://dart.dev)
[![Android](https://img.shields.io/badge/Platform-Android-3DDC84?logo=android&logoColor=white)](https://developer.android.com)
[![License: MIT](https://img.shields.io/badge/License-MIT-amber.svg)](LICENSE)

**Sonora-flutter** adalah aplikasi client musik Android berbasis Flutter untuk proxy backend mandiri (*self-hosted*) [Sonora Music](https://github.com/MuhWldns/Sonora-Music).

Aplikasi ini berfokus pada pengalaman mendengarkan musik YouTube Music yang bersih, cepat, dan independen. Klien Flutter menangani antarmuka pengguna serta pemutaran audio native di Android, sedangkan proxy Node.js bertugas menangani deciphering InnerTube, bypass PO token (BotGuard/WebPO), dan relay streaming audio.

---

## ✨ Fitur Utama (MVP)

- 🏠 **Home Feed**: Menampilkan rekomendasi lagu dan playlist publik secara langsung dari endpoint proxy `/home`.
- 🔍 **Pencarian Musik**: Pencarian debounced dengan filter kategori: *Semua*, *Lagu*, *Video*, *Album*, *Artis*, dan *Playlist*.
- 📂 **Halaman Browse**: Menampilkan detail album, artis, atau playlist dengan aksi *Putar semua* dan pemutaran lagu individual.
- 🎵 **Pemutar Musik Native**:
  - Mini-player persisten di bagian bawah layar.
  - Full player modal dengan visual artwork, seekbar interaktif, transport controls (play, pause, next, previous).
  - Mode putar acak (*shuffle*) dan pengulangan (*repeat off / all / one*).
  - Tampilan dan pengelolaan antrean lagu (*queue*).
- 📱 **Android Background Playback**:
  - Berjalan di latar belakang via Android Foreground Service (`audio_service` + `just_audio`).
  - Notifikasi kontrol media native dengan tombol play/pause/skip dan artwork.
  - Penanganan interupsi audio (telepon masuk, headphone dicabut/becoming noisy).
- ⚙️ **Konfigurasi Proxy**:
  - Input URL proxy di menu Pengaturan tanpa hardcode alamat server privat.
  - Fitur pengujian koneksi langsung (`/healthz`).
  - Penghentian audio otomatis saat endpoint proxy berganti untuk mencegah kebocoran stream antar-server.
- 🎨 **Desain Elegan Sonora**:
  - Aksen warna khas Amber Sonora (`#F59E0B`).
  - Mendukung tema Material 3 Terang (*Light*) dan Gelap (*Dark*) mengikuti preferensi sistem.
  - Penanganan status koneksi: belum dikonfigurasi, memuat (*loading*), kosong (*empty*), dan error jaringan yang informatif.

---

## 🏗️ Arsitektur

```
┌────────────────────────────────────────┐
│           Sonora-flutter               │
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

> **Catatan PO Token:** Client Flutter **tidak** mengimplementasikan decipher token atau BotGuard sendiri. Semua deciphering dan streaming token ditangani oleh proxy Sonora di sisi server, sehingga client cukup melakukan streaming melalui `/stream?videoId=...`.

---

## 🚀 Memulai

### Prasyarat

- **Flutter SDK**: 3.44.2 atau lebih baru (Dart 3.12+).
- **Android SDK**: API level 21 s/d 36+.
- **Proxy Sonora**: Instance Node.js Sonora Music yang aktif dan dapat diakses.

### Instalasi & Menjalankan

1. Clone repository:
   ```sh
   git clone https://github.com/MuhWldns/Sonora-flutter.git
   cd Sonora-flutter
   ```

2. Unduh dependensi:
   ```sh
   flutter pub get
   ```

3. Jalankan aplikasi di perangkat/emulator Android:
   ```sh
   flutter run
   ```

4. Buka menu **Pengaturan**, masukkan URL proxy Sonora Anda (misalnya `https://sonora.example.com`), klik **Uji Koneksi**, lalu **Simpan**.

### Build dengan Default Proxy (Opsional)

Anda dapat menyematkan URL proxy default saat build tanpa harus menginput manual di aplikasi:

```sh
flutter run --dart-define=SONORA_PROXY_URL=https://sonora.example.com
```

---

## 📦 Build APK Android

Untuk membuat file APK Android:

```sh
flutter build apk --debug
```

File APK akan tersedia di:
```
build/app/outputs/flutter-apk/app-debug.apk
```

Untuk build release dengan signing key Anda sendiri:
```sh
flutter build apk --release
```

---

## 🧪 Pengujian & Analisis Kode

Aplikasi ini menggunakan pengujian ketat pada boundary data, model parsing, sanitasi URL, dan penanganan kegagalan proxy:

```sh
# Analisis statis linter (0 issues)
flutter analyze

# Menjalankan unit test & regression suite (25/25 passing)
flutter test
```

---

## 📂 Struktur Proyek

```
lib/
├── main.dart               # Inisialisasi asinkron settings, API, & AudioService
├── data/
│   ├── music_models.dart   # Model MusicItem & MusicSection (toleran InnerTube JSON)
│   ├── settings_store.dart # Pengelolaan persistensi URL proxy (SharedPreferences)
│   └── sonora_api.dart     # Klien HTTP proxy Sonora
├── playback/
│   └── sonora_audio_handler.dart # AudioHandler, just_audio, native notification & background
└── ui/
    ├── sonora_app.dart     # Root widget aplikasi Sonora
    ├── theme.dart          # Tema Amber Material 3 Sonora (Light/Dark)
    ├── app_scope.dart      # InheritedScope penyedia state & pengendali
    ├── root_shell.dart     # Navigasi tab utama & penempatan mini-player
    ├── player_actions.dart # Abstraksi aksi pemutar (play, queue, browse)
    ├── player/             # Controller pemutar, mini-player, & full player view
    ├── screens/            # Layar Home, Search, Browse, dan Settings
    └── widgets/            # Komponen kartu musik, dialog, dan helper UI
```

---

## 📜 Lisensi

Proyek ini dilisensikan di bawah lisensi [MIT](LICENSE).
Aplikasi ini ditujukan untuk penggunaan pribadi (*self-hosted personal music player*).
