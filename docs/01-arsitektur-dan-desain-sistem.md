# Arsitektur & Desain Sistem Sonora Flutter

Dokumen ini menjelaskan arsitektur perangkat lunak tingkat tinggi, batasan lapisan (*layering rules*), manajemen *state*, dan diagram alur sistem pemutar musik **Sonora Flutter**. Dokumen ini disusun secara teknis dan terstruktur sebagai acuan dokumentasi laporan atau makalah rekayasa perangkat lunak.

---

## 1. Konsep Inti & Paradigma Sistem

Aplikasi **Sonora Flutter** mengadopsi paradigma **Standalone-First Direct Streaming** dengan dukungan **Modular Add-on**.

```
┌────────────────────────────────────────────────────────┐
│                     Sonora Flutter                     │
│        (UI Layer + Native Media3 ExoPlayer Engine)     │
└───────────────┬────────────────────────┬───────────────┘
                │                        │
                │ Direct Streaming       │ HTTP REST API (Opsional)
                │ (GoogleVideo CDN)      │ (/home, /search, /browse)
                ▼                        ▼
┌────────────────────────┐      ┌────────────────────────┐
│     YouTube CDN        │      │   Sonora Node Proxy    │
│  (AAC itag 140 / M4A)  │      │     (Modular Add-on)   │
└────────────────────────┘      └────────────────────────┘
```

### Prinsip Utama Sistem:
1. **Mandiri Penuh (Standalone-First)**:
   - Pencarian lagu, feed beranda, pengambilan trek playlist, dan *streaming* audio diproses langsung dari perangkat klien ke CDN YouTube tanpa mewajibkan ketersediaan server perantara (*proxy/backend*).
   - Mengeliminasi biaya pemeliharaan VPS, *bandwidth bottleneck*, dan ketergantungan kredensial terpusat.
2. **Modular Add-on Support**:
   - Pengguna yang memiliki server proxy mandiri (*self-hosted* [Sonora Node](https://github.com/MuhWldns/Sonora-Music)) dapat mengaktifkan fitur ini melalui menu Pengaturan.
   - Bila Add-on dinonaktifkan atau server proxy mengalami kendala jaringan, seluruh alur aplikasi secara otomatis beralih ke mode mandiri (*graceful fallback*).
3. **Strict Layering Rules (Arsitektur Bersih)**:
   - `lib/ui/` $\rightarrow$ Mengimpor `lib/data/` dan `lib/playback/`.
   - `lib/playback/` $\rightarrow$ Mengimpor `lib/data/` saja.
   - `lib/data/` $\rightarrow$ **Tidak mengimpor lapisan lain dalam proyek**.
   - Lapisan `data` dan `playback` dilarang keras mengimpor lapisan `ui`.
4. **State Management Tanpa Pustaka Pihak Ketiga**:
   - Menghindari *dependency bloat* (tanpa Provider, Riverpod, atau Bloc).
   - Menggunakan kombinasi murni bawaan Flutter: `ChangeNotifier` untuk *store*, `InheritedWidget` (`SonoraScope`) untuk penyuntikan dependensi ke *tree*, dan `ValueNotifier` untuk status reaktif granular.

---

## 2. Diagram Arsitektur Tingkat Tinggi (High-Level Architecture)

Diagram berikut memvisualisasikan keterkaitan antar lapisan dan modul di dalam aplikasi:

```mermaid
flowchart TD
    subgraph UI_Layer ["Lapisan Antarmuka (UI Layer)"]
        App["SonoraApp\n(MaterialApp + Theme)"]
        Scope["SonoraScope\n(InheritedWidget Di Seluruh Tree)"]
        Shell["RootShell\n(IndexedStack: Home, Search, Library, Settings)"]
        MiniPlayer["MiniPlayer\n(Dock Glassmorphism Persisten)"]
        FullPlayer["FullPlayer & LyricsView\n(Ambient Glow + LRCLIB Synchronizer)"]
        PlayerCtrl["PlayerController\n(State Pemutar & Jembatan Audio)"]
    end

    subgraph Playback_Layer ["Lapisan Pemutar (Playback Layer)"]
        AudioHandler["SonoraAudioHandler\n(BaseAudioHandler + SeekHandler)"]
        AudioService["AudioService Background Runner\n(Android MediaNotification & Lockscreen)"]
        JustAudio["just_audio Player Engine\n(Media3 ExoPlayer Wrapper)"]
        AudioSession["audio_session\n(Manajemen Ducking & Noisy Interruption)"]
    end

    subgraph Data_Layer ["Lapisan Data & Penyimpanan (Data Layer)"]
        YTService["YouTubeMusicService\n(Ekstraktor Direct Stream & Search)"]
        CacheService["AudioCacheService\n(Manajemen Disk Cache LRU 500 MB)"]
        Database["LocalDatabase (SQLite)\n(7 Tabel Riwayat, Favorit, Playlist, Stats)"]
        LyricsStore["LyricsRepository\n(Klien LRCLIB & Parser LRC)"]
        Settings["SettingsStore\n(SharedPreferences: Proxy & Draft)"]
        Api["SonoraApi\n(Klien REST HTTP Opsional)"]
    end

    App --> Scope
    Scope --> Shell
    Shell --> MiniPlayer
    MiniPlayer --> FullPlayer
    Shell --> PlayerCtrl
    PlayerCtrl --> AudioHandler

    AudioHandler --> AudioService
    AudioHandler --> JustAudio
    AudioHandler --> AudioSession

    AudioHandler --> YTService
    AudioHandler --> CacheService
    PlayerCtrl --> Database
    FullPlayer --> LyricsStore
    Scope --> Settings
    Scope --> Api
    Scope --> Database
```

---

## 3. Diagram Alur Lifecycle Bootstrap Aplikasi

Saat aplikasi dijalankan (`lib/main.dart`), sistem melakukan bootstrapping secara bertingkat untuk menjamin semua dependensi kritis siap sebelum antarmuka pengguna dirender:

```mermaid
flowchart LR
    Start([Mulai Aplikasi]) --> InitSettings["1. Memuat SettingsStore\n(SharedPreferences)"]
    InitSettings --> InitAPI["2. Inisialisasi SonoraApi\n(Binding ke Settings)"]
    InitAPI --> InitYT["3. Inisialisasi YouTubeMusicService\n(Client Explode & Cache Stream)"]
    InitYT --> InitAudio["4. Inisialisasi SonoraAudioHandler\n(AudioSession + AudioService.init)"]
    InitAudio --> OpenDB{"5. Buka LocalDatabase\n(SQLite SQLiteOpen)"}
    
    OpenDB -- "Berhasil" --> SetDB["Database Terpasang"]
    OpenDB -- "Gagal" --> NullDB["Database = null\n(Graceful Degradation)"]
    
    SetDB --> PruneCache["6. Pangkas Cache di Latar Belakang\n(AudioCacheService.pruneCache)"]
    NullDB --> PruneCache
    
    PruneCache --> MountUI["7. Pasang SonoraScope &\nJalankan SonoraApp"]
    MountUI --> End([Aplikasi Siap Digunakan])
```

> **Catatan Ketahanan (*Resilience Note*)**: Kegagalan inisialisasi basis data SQLite tidak pernah mematikan aplikasi (*fail-safe*). Bila SQLite gagal dibuka, aplikasi tetap berjalan normal dalam mode mandiri dengan fitur riwayat dan playlist kustom dinonaktifkan secara halus (*graceful degradation*).

---

## 4. Diagram Alur Resolusi Format Audio

Untuk menjamin pemutaran stabil pada Android Media3 ExoPlayer tanpa kendala *playback error* atau pemblokiran HTTP 403 CDN, `YouTubeMusicService.resolveStreamUri` menerapkan hierarki prioritas format audio yang ketat:

```mermaid
flowchart TD
    Req([Permintaan Stream videoId]) --> CheckMemCache{"Apakah URI ada di\nMemory Cache & < 4 Jam?"}
    
    CheckMemCache -- "Ya (Hit)" --> ReturnMem["Kembalikan URI Cache\n(Langsung Siap Putar)"]
    
    CheckMemCache -- "Tidak (Miss/Expired)" --> FetchManifest["Ambil StreamManifest\n(YouTube Explode Client)"]
    
    FetchManifest --> CheckAAC{"Apakah Ada AudioStreamInfo\nAAC / M4A (itag 140 / mp4a)?"}
    
    CheckAAC -- "Ya" --> SelectAAC["Pilih Stream AAC Bitrate Tertinggi\n(Prioritas Utama Android Media3)"]
    CheckAAC -- "Tidak" --> CheckOpus{"Apakah Ada AudioStreamInfo\nOpus / WebM (itag 251)?"}
    
    CheckOpus -- "Ya" --> SelectOpus["Pilih Stream Opus Bitrate Tertinggi"]
    CheckOpus -- "Tidak" --> CheckMuxed{"Apakah Ada Stream\nMuxed Video+Audio?"}
    
    CheckMuxed -- "Ya" --> SelectMuxed["Pilih Muxed MP4 Safety Net"]
    CheckMuxed -- "Tidak" --> FailStream["Gagal Resolusi (Return null)"]
    
    SelectAAC --> SaveMemCache["Simpan ke Memory Cache\n(TTL: 4 Jam)"]
    SelectOpus --> SaveMemCache
    SelectMuxed --> SaveMemCache
    
    SaveMemCache --> ServeAudio["Sajikan ke AudioSource.uri\ndengan Browser User-Agent Header"]
    ServeAudio --> Done([Pemutaran Dimulai di ExoPlayer])
```

### Mengapa AAC / M4A (itag 140) Diprioritaskan?
1. **Presisi Seeking & Durasi**: Android Media3 ExoPlayer membaca metadata atom `moov` pada kontainer MP4/M4A jauh lebih presisi dibandingkan header WebM/Matroska.
2. **Kompatibilitas Standar**: Dekoder hardware AAC tersedia di 100% perangkat Android (API 21+), menghemat konsumsi baterai (*hardware offloading*).
3. **Bebas Galat 206 Partial Content**: Kontainer M4A mendukung request *byte-range* HTTP standar dari ExoPlayer `DefaultHttpDataSource` secara konsisten.
