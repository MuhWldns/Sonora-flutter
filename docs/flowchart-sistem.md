# Flowchart Sistem Sonora Flutter

Dokumen ini merangkum alur utama aplikasi Sonora Flutter berdasarkan arsitektur
standalone-first, direct streaming YouTube, add-on proxy opsional, penyimpanan
lokal, login YouTube Music, cache audio, dan lirik LRCLIB.

> Diagram menggunakan sintaks Mermaid dan dapat dirender oleh GitHub,
> GitLab, serta editor Markdown yang mendukung Mermaid.

## 1. Gambaran Umum Sistem

```mermaid
flowchart TD
    User([Pengguna]) --> UI[Sonora Flutter UI]
    UI --> Actions[PlayerActions / Screen Actions]
    Actions --> Controller[PlayerController]
    Controller --> Handler[SonoraAudioHandler]

    Handler --> YT[YouTubeMusicService]
    YT --> CDN[(GoogleVideo CDN)]
    CDN --> Exo[just_audio / Media3 ExoPlayer]
    Exo --> Speaker([Speaker / Earphone])

    UI --> Local[LocalDatabase SQLite]
    Local --> History[Riwayat]
    Local --> Favorites[Favorit]
    Local --> Playlists[Playlist Pribadi]
    Local --> Collections[Koleksi Tersimpan]
    Local --> Stats[Listening Stats]

    UI -. Add-on opsional .-> API[SonoraApi]
    API -. HTTP JSON .-> Proxy[(Sonora Node Proxy)]
    Proxy -. fallback bila tersedia .-> YT

    FullPlayer[Full Player] --> Lyrics[LyricsRepository]
    Lyrics --> LRCLIB[(LRCLIB)]
```

## 2. Bootstrap Aplikasi

```mermaid
flowchart LR
    Start([Aplikasi dimulai])
    Start --> Binding[WidgetsFlutterBinding.ensureInitialized]
    Binding --> Settings[Load SettingsStore]
    Settings --> API[Inisialisasi SonoraApi]
    API --> YT[Inisialisasi YouTubeMusicService]
    YT --> Auth[Restore sesi YouTube Music opsional]
    Auth --> Audio[Inisialisasi AudioSession dan AudioService]
    Audio --> DB{Buka LocalDatabase}
    DB -->|Berhasil| DBReady[Database tersedia]
    DB -->|Gagal| DBNull[Database null / graceful degradation]
    DBReady --> Cache[Pangkas cache audio di background]
    DBNull --> Cache
    Cache --> Scope[Pasang SonoraScope]
    Scope --> App[Render SonoraApp]
    App --> Ready([Aplikasi siap digunakan])
```

## 3. Alur Memutar Lagu Direct YouTube

```mermaid
flowchart TD
    Tap([Pengguna menekan Putar]) --> Item{MusicItem punya videoId?}
    Item -->|Tidak| Ignore[Tidak dimasukkan ke antrean]
    Item -->|Ya| Queue[PlayerController membuat antrean]
    Queue --> Serialize[SonoraAudioHandler serialisasi operasi]
    Serialize --> Generation{Request masih generasi terbaru?}
    Generation -->|Tidak| Cancel[Operasi lama dibatalkan]
    Generation -->|Ya| Cache{URI stream ada di cache dan belum 4 jam?}
    Cache -->|Ya| URI[Gunakan URI tersimpan]
    Cache -->|Tidak| Manifest[YouTubeMusicService mengambil StreamManifest]
    Manifest --> AAC{Ada AAC/M4A itag 140?}
    AAC -->|Ya| SelectAAC[Pilih AAC bitrate tertinggi]
    AAC -->|Tidak| Opus{Ada Opus/WebM itag 251?}
    Opus -->|Ya| SelectOpus[Pilih Opus bitrate tertinggi]
    Opus -->|Tidak| Muxed{Ada muxed MP4?}
    Muxed -->|Ya| SelectMuxed[Pilih muxed MP4 sebagai safety net]
    Muxed -->|Tidak| ResolveFail[Gagal resolusi stream]
    SelectAAC --> Save[Cache URI selama 4 jam]
    SelectOpus --> Save
    SelectMuxed --> Save
    Save --> URI
    URI --> Source[Buat AudioSource.uri dengan User-Agent]
    Source --> Load[setAudioSources]
    Load --> Play[AudioPlayer.play fire-and-forget]
    Play --> Native[Media3 ExoPlayer meminta byte stream CDN]
    Native --> Playing([Audio diputar])
    Playing --> Record[Catat riwayat dan statistik lokal]
    ResolveFail --> Error[Error generik ditampilkan ke UI]
```

## 4. Alur Browse dengan Proxy Opsional

```mermaid
flowchart TD
    Open([Pengguna membuka album / artis / playlist]) --> Config{Proxy dikonfigurasi?}
    Config -->|Tidak| Direct[YouTubeMusicService browse langsung]
    Config -->|Ya| ProxyRequest[SonoraApi browse ke proxy]
    ProxyRequest --> Response{Proxy HTTP 200?}
    Response -->|Ya| ProxyData[Gunakan MusicSection dari proxy]
    Response -->|Tidak / timeout / offline| Fallback[Fallback ke YouTubeMusicService]
    Direct --> Render[Render halaman Browse]
    ProxyData --> Render
    Fallback --> Render
    Render --> Actions[Putar semua / Acak / Simpan koleksi]
```

## 5. Alur Pencarian

```mermaid
flowchart TD
    Query([Pengguna memasukkan kata kunci]) --> Empty{Kata kunci kosong?}
    Empty -->|Ya| Clear[Hapus atau abaikan hasil]
    Empty -->|Tidak| Session{Ada sesi YouTube Music?}
    Session -->|Ya| Signed[Search signed Innertube WEB_REMIX]
    Signed --> SignedOK{Request berhasil?}
    SignedOK -->|Ya| Results[Render hasil personal]
    SignedOK -->|Tidak| Anonymous[Jalur pencarian anonim]
    Session -->|Tidak| Anonymous
    Anonymous --> Proxy{Proxy opsional tersedia?}
    Proxy -->|Ya| ProxySearch[Coba SonoraApi search]
    Proxy -->|Tidak| Public[Search YouTube publik]
    ProxySearch --> ProxyOK{Berhasil?}
    ProxyOK -->|Ya| Results
    ProxyOK -->|Tidak| Public
    Public --> Results
    Results --> SaveHistory[Simpan kata kunci ke search_history]
```

## 6. Login dan Pemulihan Sesi YouTube Music

```mermaid
flowchart TD
    Settings([Pengaturan]) --> Login[Masuk YouTube Music]
    Login --> WebView[Buka WebView accounts.google.com]
    WebView --> Music[Pengguna diarahkan ke music.youtube.com]
    Music --> Finished{Halaman selesai dimuat?}
    Finished -->|Belum| Wait[Tombol Gunakan Akun belum aktif]
    Finished -->|Ya| Capture[Pengguna menekan Gunakan Akun]
    Capture --> Cookies[Ambil cookie domain music.youtube.com]
    Cookies --> Probe[Jalankan probe ytcfg]
    Probe --> Parse[Parse cookie dan field sesi]
    Parse --> Valid{Cookie SAPISID dan field wajib valid?}
    Valid -->|Tidak| Reject[Tampilkan sesi tidak valid]
    Valid -->|Ya| Verify[Validasi account/account_menu]
    Verify --> HTTP{HTTP 200?}
    HTTP -->|Tidak| Reject
    HTTP -->|Ya| Encrypt[Simpan JSON terenkripsi]
    Encrypt --> Active[Sesi aktif]
    Active --> SignedRequest[Request Innertube memakai SAPISIDHASH]
    SignedRequest --> Personal[Profil, Disukai, Riwayat,
    Home personal, Search personal]

    Startup([Startup aplikasi]) --> Restore[Baca sesi terenkripsi]
    Restore --> RestoreOK{Sesi valid?}
    RestoreOK -->|Ya| Active
    RestoreOK -->|Tidak| AnonymousMode[Mode anonim / standalone]
```

## 7. Alur Lirik Tersinkronisasi

```mermaid
flowchart TD
    OpenLyrics([Pengguna membuka Lirik]) --> Request[LyricsRepository.find]
    Request --> LRCLIB[HTTP request ke LRCLIB]
    LRCLIB --> Found{syncedLyrics tersedia?}
    Found -->|Tidak| Empty[Render lirik tidak tersedia]
    Found -->|Ya| Parse[Parse timestamp LRC]
    Parse --> Lines[List<LrcLine>]
    Lines --> Position[Ambil positionStream player]
    Position --> Compare[Bandingkan posisi dengan timestamp]
    Compare --> Active[Highlight baris aktif crimson]
    Active --> Scroll[Auto-scroll ke baris aktif]
    UserTap([Pengguna mengetuk baris]) --> Seek[Player seek ke timestamp]
```

## 8. Alur Cache Audio

```mermaid
flowchart TD
    Trigger([Startup / cache update / manual clear]) --> Directory[Ambil direktori temporary cache]
    Directory --> Scan[Pindai file cache]
    Scan --> Total[Hitung ukuran dan lastModified]
    Total --> Limit{Melebihi batas cache?}
    Limit -->|Tidak| Done([Selesai])
    Limit -->|Ya| Sort[Urutkan file dari paling lama]
    Sort --> Delete[Hapus file tertua]
    Delete --> Recount[Kurangi total ukuran]
    Recount --> Target{Sudah di bawah target?}
    Target -->|Belum| Delete
    Target -->|Ya| Done
    Manual([Pengguna tekan Bersihkan]) --> DeleteAll[Hapus semua file cache]
    DeleteAll --> Done
```

## 9. Alur Graceful Degradation

```mermaid
flowchart TD
    Failure([Kegagalan komponen]) --> Kind{Jenis kegagalan}
    Kind -->|SQLite| HideLocal[Sembunyikan fitur lokal yang bergantung DB]
    Kind -->|Proxy| DirectFallback[Gunakan jalur direct YouTube]
    Kind -->|Login / sesi| Anonymous[Gunakan mode anonim]
    Kind -->|Lirik| NoLyrics[Render status lirik tidak tersedia]
    Kind -->|Stream| PlaybackError[Hentikan item gagal dan tampilkan error generik]
    HideLocal --> Continue([UI utama tetap berjalan])
    DirectFallback --> Continue
    Anonymous --> Continue
    NoLyrics --> Continue
    PlaybackError --> Continue
```
