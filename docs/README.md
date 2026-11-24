# Dokumentasi Teknis Sonora Flutter

Selamat datang di repositori dokumentasi teknis **Sonora Flutter**. Direktori ini memuat seluruh perancangan sistem, diagram alur (*flowcharts*), pemodelan basis data (*ERD & schemas*), diagram sekuens (*sequence diagrams*), dan analisis algoritma rekayasa perangkat lunak untuk keperluan penyusunan laporan teknis atau makalah ilmiah.

---

## Daftar Isi Dokumen Teknis

Dokumentasi dipecah menjadi modul-modul mandiri berikut:

| Berkas Dokumen | Topik & Cakupan Materi | Diagram Utama |
| :--- | :--- | :--- |
| **[01. Arsitektur & Desain Sistem](01-arsitektur-dan-desain-sistem.md)** | • Paradigma *Standalone-First Direct Streaming*<br>• Aturan batas lapisan (*Layering Rules*)<br>• Manajemen *State* mandiri tanpa pustaka pihak ketiga<br>• Alur bootstrap aplikasi di `main.dart`<br>• Prioritas format audio (AAC itag 140 / Opus itag 251) | • `flowchart TD` (Arsitektur Sistem)<br>• `flowchart LR` (Bootstrap Lifecycle)<br>• `flowchart TD` (Resolusi Format Audio) |
| **[02. Desain Basis Data & ERD](02-database-design-dan-erd.md)** | • Skema relasional 7 tabel SQLite (versi 4)<br>• Kamus data lengkap (kolom, tipe, index, PK, FK)<br>• Aturan integritas (*Capped History 100*, *Skip Filter 15s*, *Cascade Delete*)<br>• Pola ketahanan *Graceful Degradation* (`LocalDatabase?`)<br>• Penyimpanan *Key-Value* (`SharedPreferences`: proxy & draft) | • `erDiagram` (Relasi 7 Tabel Database) |
| **[03. Alur Proses & Sequence Diagram](03-alur-proses-dan-sequence-diagram.md)** | • Alur interaksi pemutaran lagu langsung dari YouTube CDN<br>• Alur aktivasi dan *auto-fallback* Add-on proxy Sonora Node<br>• Alur sinkronisasi lirik waktu-nyata (*time-synced lyrics*) LRCLIB<br>• Alur manajemen dan pembersihan disk cache audio (500 MB) | • `sequenceDiagram` (Direct Streaming)<br>• `sequenceDiagram` (Add-on Proxy Fallback)<br>• `sequenceDiagram` (Sinkronisasi Lirik)<br>• `flowchart TD` (Pembersihan Cache LRU) |
| **[04. Analisis Teknis & Algoritma](04-analisis-teknis-dan-algoritma.md)** | • Analisis pemblokiran HTTP 403 Google CDN vs solusi native Media3 ExoPlayer<br>• Algoritma kontrol konkurensi antrean (*Monotonic Counter + Future Chain*)<br>• Pemisahan lifecycle `AudioPlayer.play()` dari serial queue (*anti-lock pattern*)<br>• Kompleksitas algoritma pemangkasan cache disk LRU<br>• Logika ekstraksi regex penanda waktu lirik LRC | • Cuplikan kode logika inti & pseudocode algoritma |

---

## Panduan Visual Tambahan

Selain berkas Markdown di atas, direktori ini juga menyediakan:
* **[code_documentation.html](code_documentation.html)**: Dokumentasi interaktif berbasis web dengan tema gelap Nocturne Audio, navigasi sidebar, dan panduan kode baris-demi-baris untuk *junior developer*.
* **[mockups/](mockups/)**: Prototipe antarmuka HTML dan aset desain visual UI (*Home, Search, Browse, Settings, Player, Queue, Lyrics*).
