# Pengujian Kotak Hitam (Black-Box Testing)

Dokumen ini memuat laporan dan matriks pengujian fungsional perangkat lunak menggunakan metode **Black-Box Testing** (*Equivalence Partitioning & Boundary Value Analysis*) pada aplikasi **Sonora Flutter**. Dokumen ini dirancang sebagai acuan bab pengujian dan evaluasi sistem dalam penyusunan laporan teknis atau makalah ilmiah rekayasa perangkat lunak.

---

## 1. Lingkungan & Konfigurasi Pengujian

* **Perangkat Keras (Hardware)**: Ponsel Android Fisik (Xiaomi / Pixel) & Android Emulator (API 34/35).
* **Sistem Operasi**: Android 14 (Media3 ExoPlayer runtime).
* **Versi Flutter**: Flutter 3.44+ / Dart 3.12+.
* **Metode Pengujian**: *Black-Box Testing* berfokus pada masukan (*input*) dan luaran (*output*) antarmuka pengguna tanpa mengamati struktur internal source code secara langsung.
* **Kategori Hasil**:
  * **Valid (Pass)**: Sistem merespon sesuai spesifikasi yang diharapkan.
  * **Gagal (Fail)**: Sistem mengalami crash, tidak merespon, atau menghasilkan keluaran yang salah.

---

## 2. Matriks Kasus Uji (Test Case Matrix)

### Modul 1: Pengaturan, Ekstensi Add-on, & Manajemen Cache (`TC-SET`)

| ID Kasus Uji | Skenario Pengujian | Langkah Pengujian & Data Masukan | Hasil yang Diharapkan | Hasil Aktual | Status |
| :--- | :--- | :--- | :--- | :--- | :---: |
| **TC-SET-01** | Validasi input URL proxy yang sah | 1. Buka menu Pengaturan.<br>2. Masukkan URL: `https://proxy.example.com:8787`.<br>3. Tekan tombol **Simpan**. | URL dinormalkan, disimpan ke `SharedPreferences`, muncul snackbar *'Endpoint tersimpan'*. | URL tersimpan di memory & disk, snackbar sukses tampil. | **Valid (Pass)** |
| **TC-SET-02** | Penolakan input URL dengan skema tidak valid | 1. Masukkan URL: `ftp://myhost:8787`.<br>2. Tekan tombol **Simpan**. | Sistem menolak dengan pesan error *'Skema URL proxy harus http atau https'*. | Banner error merah muncul di bawah input. | **Valid (Pass)** |
| **TC-SET-03** | Penolakan input URL memuat query atau fragment | 1. Masukkan URL: `https://host:8787/api?key=secret#part`.<br>2. Tekan tombol **Simpan**. | Sistem menolak dengan pesan error larangan query/fragment. | Validasi melempar error, URL tidak disimpan ke state. | **Valid (Pass)** |
| **TC-SET-04** | Pengujian tombol 'Tes koneksi' pada server online | 1. Masukkan URL proxy aktif.<br>2. Tekan tombol **Tes koneksi**. | Sistem memanggil `/healthz`, indikator loading berputar, lalu muncul banner hijau *'Terhubung'*. | Banner sukses hijau tampil dengan informasi host. | **Valid (Pass)** |
| **TC-SET-05** | Pengujian sakelar toggle Add-on dimatikan | 1. Nonaktifkan switch **Sonora Node Proxy**.<br>2. Amati antarmuka dan status pemutar. | URL aktif dikosongkan (mode mandiri aktif), audio lama dihentikan, teks URL tetap tersimpan sebagai draf. | Switch mati, form diciutkan (*collapsed*), mode mandiri aktif. | **Valid (Pass)** |
| **TC-SET-06** | Pengujian pembersihan cache audio manual | 1. Amati progress bar ukuran cache.<br>2. Tekan tombol **Bersihkan** di kartu cache audio. | Direktori `just_audio_cache` dihapus, indikator ukuran turun ke `0 B`, muncul snackbar konfirmasi. | Cache terhapus seketika, ukuran ter-reset menjadi 0 B. | **Valid (Pass)** |

---

### Modul 2: Pemutar Audio & Layanan Latar Belakang (`TC-PLY`)

| ID Kasus Uji | Skenario Pengujian | Langkah Pengujian & Data Masukan | Hasil yang Diharapkan | Hasil Aktual | Status |
| :--- | :--- | :--- | :--- | :--- | :---: |
| **TC-PLY-01** | Pemutaran lagu langsung (*Direct YouTube Streaming*) | 1. Pilih lagu di Beranda / Pencarian.<br>2. Ketuk kartu lagu. | Sistem mengekstrak stream AAC (itag 140), audio berbunyi dalam < 2 detik tanpa proxy. | Audio berputar mulus dengan bitrate jernih (128-192 kbps). | **Valid (Pass)** |
| **TC-PLY-02** | Fungsi kontrol transport pemutar (Play/Pause/Next/Prev) | 1. Buka Full Player.<br>2. Tekan Pause lalu Play.<br>3. Tekan tombol Next dan Previous. | Lagu terjeda seketika dan berlanjut mulus. Lagu berganti sesuai antrean playlist native. | Respon transport instan tanpa jeda buffer tambahan. | **Valid (Pass)** |
| **TC-PLY-03** | Penggeseran bilah durasi (*Seekbar Scrubbing*) | 1. Geser slider durasi dari menit 00:10 ke 02:30.<br>2. Lepaskan jari. | Posisi audio berpindah tepat ke menit 02:30 dengan transisi suara presisi. | Seeking responsif berkat atom atom MOOV pada stream AAC. | **Valid (Pass)** |
| **TC-PLY-04** | Mode pengulangan (*Repeat Mode*) | 1. Tekan tombol repeat hingga siklus: *Off $\rightarrow$ All $\rightarrow$ One*. | Ikon berubah sesuai mode. Pada mode *One*, lagu yang selesai otomatis berputar ulang dari awal. | Siklus repeat berfungsi normal pada antrean native. | **Valid (Pass)** |
| **TC-PLY-05** | Mode acak antrean (*Shuffle Mode*) | 1. Aktifkan tombol Shuffle pada antrean berisi 10 lagu. | Urutan antrean diacak tanpa menghentikan lagu yang sedang diputar. | Daftar antrean teracak dinamis. | **Valid (Pass)** |
| **TC-PLY-06** | Notifikasi kontrol latar belakang (*Foreground Service*) | 1. Putar lagu lalu tekan tombol Home (aplikasi diminimize/layar mati). | Notifikasi media Android muncul di lockscreen dengan artwork, judul, dan kontrol transport. | Kontrol media Android berfungsi dari panel notifikasi. | **Valid (Pass)** |
| **TC-PLY-07** | Penanganan interupsi audio (*Becoming Noisy*) | 1. Putar lagu menggunakan headset kabel.<br>2. Cabut kabel headset saat lagu berputar. | Musik otomatis dijeda (*auto-pause*) seketika demi privasi pengguna. | Event `audio_session` noisy tertangkap dan player ter-pause. | **Valid (Pass)** |

---

### Modul 3: Pencarian & Eksplorasi Musik (`TC-SRC`)

| ID Kasus Uji | Skenario Pengujian | Langkah Pengujian & Data Masukan | Hasil yang Diharapkan | Hasil Aktual | Status |
| :--- | :--- | :--- | :--- | :--- | :---: |
| **TC-SRC-01** | Pencarian lagu dengan kata kunci umum | 1. Buka tab Pencarian.<br>2. Masukkan kata kunci: `Indonesia Pusaka`. | Menampilkan daftar lagu hasil pencarian langsung dari YouTube dalam waktu < 2 detik. | Daftar lagu tampil lengkap dengan artwork dan artis. | **Valid (Pass)** |
| **TC-SRC-02** | Penggunaan filter kategori pencarian | 1. Pilih filter chip `Lagu`, `Video`, atau `Playlist`. | Hasil pencarian disaring sesuai kategori yang dipilih. | Konten terfilter akurat sesuai chip aktif. | **Valid (Pass)** |
| **TC-SRC-03** | Pencegahan query berlebih (*Debounce Filtering*) | 1. Ketik kata kunci dengan sangat cepat tanpa henti. | Request jaringan tidak ditembakkan per huruf, melainkan ditunda 400ms setelah ketukan berhenti. | Menghemat bandwidth dan mencegah spam request ke CDN. | **Valid (Pass)** |
| **TC-SRC-04** | Pencatatan riwayat pencarian ke database SQLite | 1. Cari sebuah kata kunci.<br>2. Hapus kolom pencarian. | Kata kunci muncul di seksi *Riwayat Pencarian* di bawah kolom input. | Kata kunci tersimpan di tabel `search_history`. | **Valid (Pass)** |
| **TC-SRC-05** | Penghapusan entri riwayat pencarian | 1. Tekan tombol `X` pada salah satu chip riwayat pencarian. | Kata kunci tersebut terhapus dari tampilan dan dari database SQLite. | Baris terhapus permanen dari SQLite. | **Valid (Pass)** |

---

### Modul 4: Koleksi, Playlist Lokal, & Statistik (`TC-LIB`)

| ID Kasus Uji | Skenario Pengujian | Langkah Pengujian & Data Masukan | Hasil yang Diharapkan | Hasil Aktual | Status |
| :--- | :--- | :--- | :--- | :--- | :---: |
| **TC-LIB-01** | Pembuatan playlist kustom lokal baru | 1. Buka tab Koleksi.<br>2. Tekan tombol `+` (Buat Playlist).<br>3. Beri nama: `Lagu Belajar`. | Playlist baru terbentuk dan langsung muncul pada tab Koleksi. | Entri tersimpan di tabel `user_playlists`. | **Valid (Pass)** |
| **TC-LIB-02** | Penambahan trek lagu ke playlist kustom | 1. Pada lagu yang sedang diputar, ketuk ikon opsi.<br>2. Pilih *Tambahkan ke Playlist* $\rightarrow$ `Lagu Belajar`. | Lagu tersimpan ke playlist, muncul snackbar sukses. | Relasi tersimpan di tabel `playlist_tracks`. | **Valid (Pass)** |
| **TC-LIB-03** | Penandaan lagu favorit (*Toggle Favorite*) | 1. Tekan ikon Hati pada Player.<br>2. Buka playlist bawaan *Lagu Favorit*. | Ikon hati berubah merah, lagu muncul di playlist Favorit. Menekan kembali membatalkan status suka. | Operasi insert/delete di tabel `favorite_tracks` sukses. | **Valid (Pass)** |
| **TC-LIB-04** | Analitik statistik mendengarkan (Bento Grid) | 1. Putar lagu lebih dari 15 detik.<br>2. Buka tab Koleksi dan amati kartu Bento Grid. | Durasi mendengarkan bertambah, lagu/artis masuk ke peringkat *Top Tracks* dan *Top Artists*. | Data tercatat di tabel `listening_stats` dan teragregasi. | **Valid (Pass)** |
| **TC-LIB-05** | Filter pengabaian lagu yang di-skip cepat (< 15s) | 1. Putar lagu lalu lewati (*skip*) pada detik ke-5. | Lagu yang di-skip tidak dihitung ke dalam statistik Bento Grid. | Database menolak pencatatan durasi di bawah 15 detik. | **Valid (Pass)** |

---

### Modul 5: Lirik Tersinkronisasi Waktu Nyata (`TC-LYR`)

| ID Kasus Uji | Skenario Pengujian | Langkah Pengujian & Data Masukan | Hasil yang Diharapkan | Hasil Aktual | Status |
| :--- | :--- | :--- | :--- | :--- | :---: |
| **TC-LYR-01** | Pemuatan lirik tersinkronisasi online | 1. Putar lagu populer (mis. *Bohemian Rhapsody*).<br>2. Buka tab Lirik di Full Player. | Sistem mengambil lirik sinkron dari LRCLIB, menampilkan teks baris per baris. | Lirik tampil dengan latar belakang blur artistik. | **Valid (Pass)** |
| **TC-LYR-02** | Penyorotan & auto-scroll baris aktif | 1. Dengarkan lagu saat lirik terbuka. | Baris lirik yang sedang dinyanyikan disorot teks besar merah dan otomatis bergeser ke tengah layar. | Sinkronisasi per milidetik berjalan akurat mengikuti vokal. | **Valid (Pass)** |
| **TC-LYR-03** | Interaktivitas lompat durasi via ketukan lirik | 1. Ketuk baris lirik pada menit `01:45`. | Pemutar langsung melompat (*seek*) ke menit `01:45` dan audio berlanjut dari titik tersebut. | Posisi audio dan baris aktif sinkron seketika. | **Valid (Pass)** |
| **TC-LYR-04** | Penanganan lagu tanpa lirik (*Graceful Degradation*) | 1. Putar trek instrumental tanpa lirik. | Menampilkan pesan halus *'Lirik belum tersedia'* tanpa melempar error atau crash. | Sistem menangani respon null secara aman (*never throws*). | **Valid (Pass)** |

---

### Modul 6: Halaman Browse & Ketahanan Jaringan (`TC-BRW`)

| ID Kasus Uji | Skenario Pengujian | Langkah Pengujian & Data Masukan | Hasil yang Diharapkan | Hasil Aktual | Status |
| :--- | :--- | :--- | :--- | :--- | :---: |
| **TC-BRW-01** | Pemuatan halaman album/playlist mode mandiri | 1. Pada kondisi proxy nonaktif, ketuk salah satu album di Beranda. | Halaman `BrowseScreen` terbuka dan menampilkan daftar hingga 50 lagu tanpa error proxy. | Resolusi YouTube mandiri sukses menampilkan seluruh trek. | **Valid (Pass)** |
| **TC-BRW-02** | Aksi tombol 'Putar Semua' pada halaman Browse | 1. Buka halaman Browse sebuah playlist.<br>2. Tekan tombol **Putar Semua**. | Seluruh lagu dalam album/playlist dimasukkan ke antrean pemutar dan lagu pertama berbunyi. | Antrean terpasang lengkap di `just_audio`. | **Valid (Pass)** |
| **TC-BRW-03** | Auto-fallback saat server proxy offline | 1. Aktifkan Add-on proxy dengan URL mati/dummy.<br>2. Buka Beranda / Browse. | Permintaan proxy timeout, sistem otomatis beralih memuat lagu via YouTube mandiri tanpa memunculkan layar error. | Transisi fallback transparan, lagu tetap tampil. | **Valid (Pass)** |

---

## 3. Kesimpulan Hasil Pengujian

Berdasarkan eksekusi seluruh skenario pengujian kotak hitam pada 6 modul fungsional di atas:
* **Total Kasus Uji**: 30 Kasus Uji.
* **Jumlah Berhasil (Pass)**: 30 Kasus Uji (100%).
* **Jumlah Gagal (Fail)**: 0 Kasus Uji (0%).
* **Kesimpulan Akhir**: Seluruh fitur utama aplikasi—mulai dari pemutaran audio mandiri, manajemen cache otomatis, pencarian reaktif, lirik sinkron, hingga persistensi offline—memenuhi spesifikasi fungsional dan siap digunakan untuk evaluasi makalah perangkat lunak.
