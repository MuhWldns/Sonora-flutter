# Analisis Teknis, Algoritma, & Ketahanan Sistem

Dokumen ini memaparkan analisis mendalam dari sudut pandang rekayasa perangkat lunak (*software engineering*) mengenai tantangan teknis, algoritma konkurensi, mitigasi *network streaming*, dan pencegahan *anti-pattern* pada aplikasi **Sonora Flutter**. Dokumen ini dirancang sebagai bahan rujukan bab pembahasan dan analisis teknis untuk laporan atau makalah akademis.

---

## 1. Analisis Kegagalan `LockCachingAudioSource` vs Solusi Native ExoPlayer

Salah satu tantangan kritis dalam pemutaran audio langsung dari CDN YouTube (*GoogleVideo*) adalah kebijakan *anti-bot / anti-scraping* yang ketat dari Google.

### Akar Masalah Kegagalan `LockCachingAudioSource`:
1. **Isolasi Dart VM vs Native Engine**:
   - Pustaka `just_audio` menyediakan kelas `LockCachingAudioSource` yang bertindak sebagai *proxy HTTP internal* di dalam Dart VM.
   - Request HTTP untuk mengambil berkas `.mp4/.m4a` dieksekusi oleh pustaka `dart:io HttpClient` di *background isolate*, bukan oleh stack jaringan native sistem operasi Android.
2. **Respon HTTP 403 Forbidden dari GoogleVideo CDN**:
   - Google CDN menganalisis TLS fingerprint, header HTTP, dan pola transmisi data dari Dart `HttpClient`.
   - Karena Dart `HttpClient` tidak mengirimkan cipher suites native Android atau header browser resmi, CDN GoogleVideo langsung memblokir koneksi dengan status **HTTP 403 Forbidden**.
   - Server lokal `just_audio` kemudian meneruskan error 403 tersebut ke ExoPlayer sebagai **HTTP 500 (`InvalidResponseCodeException: Response code: 500`)**, menyebabkan pemutaran terhenti seketika.

### Solusi Rekayasa: `AudioSource.uri` Native Android Media3
Sistem dialihkan kembali ke implementasi `AudioSource.uri` native dengan konfigurasi header:
```dart
return AudioSource.uri(
  uri,
  tag: item,
  headers: const <String, String>{
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  },
);
```

#### Mengapa Solusi Ini Berhasil 100%?
- Request HTTP tidak lagi ditangani oleh Dart VM, melainkan diserahkan langsung ke komponen C++/Java Android Media3 ExoPlayer (`DefaultHttpDataSource`).
- Stack native Android Media3 mengeksekusi request stream byte-range (`Range: bytes=0-...`) dengan respon standar `206 Partial Content`.
- Dilengkapi header browser modern, CDN mengenali request sebagai akses pemutar media resmi sehingga pemutaran berjalan mulus tanpa pemblokiran.

---

## 2. Algoritma Konkurensi Antrean Audio: Monotonic Counter & Future Chaining

Dalam aplikasi pemutar musik mobile, pengguna sering kali mengetuk lagu secara berulang-ulang (*rapid tapping*). Jika setiap ketukan langsung memicu pembaruan antrean audio secara paralel, akan timbul kondisi balapan (*race condition*) di mana lagu lama menimpa lagu baru.

### 1. Serialized Future Chain
Semua mutasi antrean (`playItems`, `addItem`) dirantai ke satu antrean *Future* tunggal (`_operations`):
```dart
Future<void> _enqueue(Future<void> Function() operation) {
  final next = _operations.then((_) => operation());
  _operations = next.catchError((_) {});
  return next;
}
```
Setiap operasi baru dijamin baru mulai dieksekusi setelah operasi sebelumnya selesai, mencegah tabrakan *state* di dalam engine playlist `just_audio`.

### 2. Monotonic Generation Counter
Meskipun operasi dirantai secara serial, proses pengambilan URL stream dari jaringan membutuhkan waktu (I/O bound). Bila pengguna menekan lagu A lalu 100 milidetik kemudian menekan lagu B, request lagu A yang sedang berjalan harus dibatalkan sebelum menyentuh pemutar audio.

```dart
int _requestCounter = 0;

Future<bool> playItems(List<MusicItem> items, {int startIndex = 0}) {
  final int requestId = ++_requestCounter; // Monotonic counter
  
  return _enqueue(() async {
    // 1. Validasi awal: Jika ada request lebih baru, batalkan operasi ini
    if (requestId != _requestCounter) return false;

    // 2. Eksekusi resolusi URL stream secara paralel
    final sources = await Future.wait(playable.map(...));

    // 3. Validasi akhir: Sebelum dipasang ke player, cek kembali nomor counter
    if (requestId != _requestCounter) return false;

    await _player.setAudioSources(sources, initialIndex: startIndex);
    return true;
  });
}
```
*Prinsip*: **Request terbaru selalu menang (*latest request wins*)**, dan request lama yang tersusul secara otomatis menjadi operasi *no-op* tanpa efek samping.

---

## 3. Pemisahan Siklus Hidup `AudioPlayer.play()` dari Serial Queue

Sebuah jebakan arsitektur umum (*common gotcha*) pada pustaka `just_audio` adalah kontrak pemanggilan fungsi `player.play()`:

> **⚠️ Peringatan Teknis**: Pada pustaka `just_audio`, fungsi `await player.play()` **TIDAK** selesai (tidak *resolve*) saat pemutaran dimulai, melainkan **tetap menggantung (*pending*) selama lagu diputar**, dan baru selesai saat lagu di-pause, di-stop, atau berakhir!

Bila developer menulis kode seperti berikut di dalam antrean pemuatan:
```dart
// KODE SALAH (ANTI-PATTERN):
await _player.setAudioSources(sources);
await _player.play(); // ANTIL-LOCK: Menggantung selama 4 menit durasi lagu!
_publishQueue();      // Tidak akan pernah terpanggil sampai lagu selesai!
```
Maka rantai *Future* `_operations` akan terkunci selama durasi lagu, menyebabkan pengguna tidak dapat mengganti lagu berikutnya!

### Solusi Rekayasa: Pola Fire-and-Forget Aman
Fungsi `_player.play()` dieksekusi secara terpisah tanpa di-await di dalam antrean pemuatan:
```dart
// KODE BENAR (SONORA IMPLEMENTATION):
await _player.setAudioSources(sources, initialIndex: startIndex);
_publishQueue();
_publishMediaItem();

// Jalankan play secara non-blocking; tangani error via stream listener terpisah
unawaited(_player.play().catchError((e) {
  if (e is! PlayerInterruptedException) {
    _publishError(_describe(e));
  }
}));
```

---

## 4. Algoritma Pembersihan Disk Cache LRU (Least Recently Used)

`AudioCacheService.pruneCache` bertugas menjaga penggunaan ruang penyimpanan perangkat di bawah batas 500 MB.

### Pseudocode Algoritma:
```text
Algoritma PruneCache(maxBytes = 500 MB, targetBytes = 400 MB):
1.  Dapatkan direktori cache lokal: dir = getTemporaryDirectory() + "/just_audio_cache"
2.  Jika dir tidak ada -> Keluar (return)
3.  Inisialisasi totalBytes = 0
4.  Inisialisasi fileList = []
5.  Untuk setiap file f di dalam dir:
        Jika f adalah File:
            size = f.length()
            modified = f.lastModified()
            Tambahkan (f, size, modified) ke fileList
            totalBytes += size
6.  Jika totalBytes <= maxBytes:
        Keluar (Ukuran aman, tidak perlu pembersihan)
7.  Urutkan fileList berdasarkan modified secara ASCENDING (file terlama di awal)
8.  Untuk setiap item (f, size, modified) dalam fileList:
        Hapus file: f.delete()
        totalBytes -= size
        Jika totalBytes <= targetBytes:
            Keluar dari loop (Target pemangkasan tercapai)
9.  Selesai
```

### Analisis Kompleksitas:
- **Kompleksitas Waktu**: $\mathcal{O}(N \log N)$, di mana $N$ adalah jumlah berkas berkas cache audio pada disk. Pengurutan menggunakan algoritma Dual-Pivot Quicksort bawaan Dart untuk menyortir timestamp `lastModified`.
- **Kompleksitas Ruang**: $\mathcal{O}(N)$ untuk menyimpan referensi berkas di memori sementara.
- **Efisiensi Ambang Batas Buffer**: Memangkas hingga **400 MB** saat menyentuh **500 MB** memberikan *headroom* sebesar **100 MB** (~20-25 lagu berdurasi 3-4 menit), sehingga operasi pembersihan disk I/O tidak perlu berjalan terus-menerus di setiap lagu.

---

## 5. Parser Lirik Tersinkronisasi (*LRC Regex Parser*)

Format LRC standar menyimpan teks baris lagu dengan penanda waktu (*timestamp*) dalam kurung siku:
`[01:23.45]Lirik lagu yang sedang dinyanyikan`

### Logika Ekstraksi:
`LyricsRepository.parseSynced` mengurai format ini menggunakan ekspresi reguler (*regular expression*):
```dart
static final RegExp _lrcPattern = RegExp(r'^\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\](.*)$');
```

1. **Grup 1**: Menit (`mm`) $\rightarrow$ dikonversi ke milidetik: `int.parse(match[1]) * 60 * 1000`.
2. **Grup 2**: Detik (`ss`) $\rightarrow$ dikonversi ke milidetik: `int.parse(match[2]) * 1000`.
3. **Grup 3**: Pecahan detik (centidetik/milidetik) $\rightarrow$ dinormalkan ke milidetik riil (jika 2 digit dikali 10, jika 3 digit diambil langsung).
4. **Grup 4**: Teks baris lirik lagu.

Hasilnya diurutkan secara kronologis ke dalam `List<LrcLine>`. Saat lagu diputar, UI membandingkan posisi *current duration* dengan daftar timestamp ini untuk menentukan baris aktif dan memicu animasi auto-scroll secara instan.
