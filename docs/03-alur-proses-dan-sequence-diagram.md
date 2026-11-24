# Diagram Alur Proses & Sequence Diagram

Dokumen ini memaparkan pemodelan dinamis interaksi antar komponen sistem pada aplikasi **Sonora Flutter** menggunakan **Sequence Diagram** dan **Flowchart** berbasis sintaks Mermaid. Dokumen ini dirancang sebagai acuan bab perancangan proses dan interaksi sistem dalam laporan atau makalah ilmiah rekayasa perangkat lunak.

---

## 1. Sequence Diagram: Pemutaran Audio Mandiri (*Direct YouTube Streaming*)

Diagram sekuens berikut menggambarkan interaksi saat pengguna menekan tombol putar pada lagu hingga audio berhasil dialirkan langsung dari GoogleVideo CDN ke engine native Android Media3 ExoPlayer:

```mermaid
sequenceDiagram
    autonumber
    actor User as Pengguna
    participant UI as Antarmuka (HomeScreen / ShelfCard)
    participant PA as PlayerActions
    participant PC as PlayerController
    participant AH as SonoraAudioHandler
    participant YTS as YouTubeMusicService
    participant CDN as GoogleVideo CDN
    participant Exo as Android Media3 ExoPlayer
    participant DB as LocalDatabase

    User->>UI: Ketuk kartu lagu (Tap MusicItem)
    UI->>PA: play(item)
    PA->>PC: playItem(item)
    PC->>AH: playItems([item], startIndex: 0)
    
    activate AH
    Note over AH: Kunci antrean serial (Future chain) & naikkan _generation counter
    AH->>YTS: resolveStreamUri(videoId)
    
    activate YTS
    alt URI ada di Cache Memori & Belum Expired
        YTS-->>AH: Return cached URI
    else Cache Miss atau Expired
        YTS->>CDN: Request StreamManifest via YouTube Client
        CDN-->>YTS: Return StreamManifest
        Note over YTS: Filter prioritas AAC (itag 140) -> Opus -> Muxed
        YTS->>YTS: Simpan URI ke memori (TTL 4 jam)
        YTS-->>AH: Return resolved stream URI
    end
    deactivate YTS

    AH->>AH: Bungkus ke AudioSource.uri(uri, headers: {User-Agent: Browser})
    AH->>Exo: setAudioSources([source], initialIndex: 0)
    AH->>Exo: play() (Fire-and-forget aman)
    AH->>AH: _publishMediaItem(id: item.videoId!)
    AH->>AH: _publishPlaybackState(Playing)
    AH-->>PC: Antrean terpasang (Queue loaded)
    deactivate AH

    Exo->>CDN: HTTP GET 206 Partial Content (Native C++/Java Stream)
    CDN-->>Exo: Aliran byte audio AAC
    Exo-->>User: Suara lagu terdengar di speaker / earphone

    par Pencatatan Riwayat & Statistik
        PC->>DB: recordPlayback(item) (Capped 100 entri)
        PC->>DB: recordListening(videoId, duration) (Jika >= 15s)
    end
```

---

## 2. Sequence Diagram: Ekstensi Add-on Proxy & Auto-Fallback

Diagram berikut menjelaskan ketahanan sistem ketika fitur Add-on proxy diaktifkan, serta bagaimana sistem secara mulus beralih ke mode mandiri jika server proxy mengalami kendala jaringan atau *timeout*:

```mermaid
sequenceDiagram
    autonumber
    actor User as Pengguna
    participant Screen as BrowseScreen
    participant Scope as SonoraScope
    participant Store as SettingsStore
    participant API as SonoraApi (Proxy Klien)
    participant Proxy as Server Sonora Node
    participant YTS as YouTubeMusicService

    User->>Screen: Buka halaman Playlist / Album
    Screen->>Scope: Ambil instance settings, api, dan ytService
    Screen->>Store: Cek isConfigured
    
    alt Add-on Proxy Aktif (isConfigured == true)
        Screen->>API: browse(browseId)
        activate API
        API->>Proxy: HTTP GET /browse?id=VL... (Timeout: 20s)
        
        alt Proxy Merespon Cepat (HTTP 200)
            Proxy-->>API: JSON MusicSection payload
            API-->>Screen: List<MusicSection>
            Screen->>Screen: Render daftar lagu dari Proxy
        else Proxy Timeout / Offline / Error 500
            Proxy--xAPI: Connection Failed / Timeout
            API-->>Screen: Lempar SonoraApiException
            deactivate API
            Note over Screen: Tangkap error & jalankan fallback mandiri otomatis!
            Screen->>YTS: browse(browseId, title: widget.title)
            activate YTS
            YTS->>YTS: Ekstraksi playlist via _yt.playlists.getVideos()
            YTS-->>Screen: List<MusicSection> mandiri
            deactivate YTS
            Screen->>Screen: Render daftar lagu dari YouTube langsung
        end

    else Add-on Proxy Nonaktif (Mode Mandiri Penuh)
        Screen->>YTS: browse(browseId, title: widget.title)
        activate YTS
        YTS->>YTS: Ekstraksi 50 trek playlist langsung dari YouTube
        YTS-->>Screen: List<MusicSection> mandiri
        deactivate YTS
        Screen->>Screen: Render daftar lagu tanpa menyentuh server proxy
    end
```

---

## 3. Sequence Diagram: Sinkronisasi Lirik Real-Time

Diagram berikut menggambarkan alur kerja modul lirik tersinkronisasi (*time-synced lyrics*) yang mengambil berkas `.lrc` langsung dari repositori LRCLIB:

```mermaid
sequenceDiagram
    autonumber
    actor User as Pengguna
    participant View as _LyricsView (Full Player)
    participant Repo as LyricsRepository
    participant LRCLIB as API LRCLIB (Direct Klien)
    participant Player as AudioPlayer (Position Stream)

    User->>View: Buka tab Lirik pada layar Full Player
    View->>Repo: find(track, artist, videoId, durationMs)
    activate Repo
    
    Repo->>LRCLIB: HTTP GET /api/get?track_name=...&artist_name=...
    LRCLIB-->>Repo: JSON respon lirik (syncedLyrics string)
    
    alt Lirik Sinkron Tersedia
        Repo->>Repo: parseSynced(lrcText) -> List<LrcLine> (timestamp & text)
        Repo-->>View: Kembalikan objek LrcLyrics (ready)
    else Lirik Tidak Ditemukan
        Repo-->>View: Kembalikan null (unavailable - no error thrown)
    end
    deactivate Repo

    View->>View: Render daftar baris lirik dengan efek blur latar

    loop Setiap Tick Posisi Pemutaran Lagu
        Player-->>View: Stream<Duration> positionStream
        View->>View: Bandingkan posisi audio dengan timestamp LrcLine
        View->>View: Sorot baris aktif (Teks besar aksen Crimson)
        View->>View: Jalankan animateTo auto-scroll baris aktif ke tengah layar
    end

    opt Pengguna Mengetuk Baris Lirik Tertentu
        User->>View: Ketuk baris lirik di menit 01:25
        View->>Player: seek(Duration(minutes: 1, seconds: 25))
    end
```

---

## 4. Flowchart: Algoritma Manajemen Cache Audio (LRU 500 MB)

Untuk menjaga performa ruang penyimpanan perangkat Android agar tidak penuh oleh file audio streaming sementara, `AudioCacheService` menerapkan algoritma pemangkasan otomatis berbasis waktu akses (*Least Recently Used*):

```mermaid
flowchart TD
    Trigger([Trigger: Startup Aplikasi ATAU Queue Applied]) --> GetTempDir["Dapatkan Direktori Cache Sementara\n(getTemporaryDirectory / just_audio_cache)"]
    
    GetTempDir --> ScanFiles["Pindai Semua Berkas dalam Direktori\n(Directory.list)"]
    ScanFiles --> CalcTotal["Hitung Total Ukuran Cache (bytes)\ndan Catat Waktu Akses Terakhir (lastModified)"]
    
    CalcTotal --> CheckThreshold{"Apakah Ukuran Total > 500 MB\n(524.288.000 Bytes)?"}
    
    CheckThreshold -- "Tidak (<= 500 MB)" --> SafeState["Ukuran Cache Aman\n(Operasi Selesai / No-op)"]
    SafeState --> End([Selesai])
    
    CheckThreshold -- "Ya (> 500 MB)" --> SortLRU["Urutkan Berkas Berdasarkan lastModified\nsecara Ascending (Terlama ke Terbaru)"]
    
    SortLRU --> LoopDelete["Iterasi Berkas Terlama (Oldest File)"]
    LoopDelete --> DeleteFile["Hapus Berkas dari Disk\n(file.delete())"]
    DeleteFile --> DeductSize["Kurangi Ukuran Total Berkas yang Dihapus"]
    
    DeductSize --> CheckTarget{"Apakah Ukuran Total Sekarang\n<= 400 MB (Target Pangkas)?"}
    
    CheckTarget -- "Belum" --> LoopDelete
    CheckTarget -- "Sudah Tercapai" --> PruneComplete["Pemangkasan Berhasil\nRuang Disk Pulih 100 MB+"]
    PruneComplete --> End

    subgraph Manual_Clear ["Jalur Pembersihan Manual"]
        UserBtn([Pengguna Tekan Tombol 'Bersihkan' di Pengaturan]) --> DeleteAll["Hapus Seluruh Berkas di just_audio_cache"]
        DeleteAll --> ResetCounter["Reset Ukuran Cache Menjadi 0 B\nUpdate Tampilan Progress Bar di UI"]
        ResetCounter --> End
    end
```
