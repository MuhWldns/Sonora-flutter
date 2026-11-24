# 07. Login YouTube Music & Arsitektur Sesi

Dokumen ini menjelaskan fitur login YouTube Music: alur penangkapan sesi lewat WebView, model sesi `YoutubeSession`, mekanisme penandatanganan request innertube (`SAPISIDHASH`), desain validasi sesi berbasis status HTTP, serta dua jebakan produksi yang pernah ditemukan dan diperbaiki. Seluruh kode yang dirujuk berada di `lib/data/youtube_session.dart`, `lib/data/youtube_auth_service.dart`, `lib/data/youtube_music_service.dart`, dan `lib/ui/screens/login_screen.dart`.

---

## 1. Gambaran Umum

Login YouTube Music adalah fitur **opsional**. Tanpa sesi, aplikasi tetap berjalan penuh dalam mode mandiri (*standalone-first*). Dengan sesi aktif, aplikasi membuka:

- Kartu profil akun (nama, email, avatar) di Pengaturan.
- Koleksi **Disukai** (`FEmusic_liked_videos`) dan **Riwayat** (`FEmusic_history`) di tab Koleksi.
- Rak beranda personal (`FEmusic_home`) dan pencarian terpersonalisasi via `music.youtube.com`.

Kata sandi Google tidak pernah menyentuh kode Sonora: seluruh login terjadi di dalam WebView. Sonora hanya menangkap **cookie sesi** dan nilai `ytcfg` setelah pengguna diarahkan ke YouTube Music.

```
Pengaturan → Akun YouTube Music → Masuk
        → LoginScreen (WebView accounts.google.com)
        → diarahkan ke music.youtube.com
        → pengguna menekan "Gunakan Akun"
        → YoutubeAuthService.capture(...) → validasi → simpan terenkripsi
```

---

## 2. Alur Penangkapan Sesi (WebView Capture Flow)

`LoginScreen` (`lib/ui/screens/login_screen.dart`):

1. **Muat halaman login Google** (`accounts.google.com/ServiceLogin?...&continue=https://music.youtube.com/`) dengan `JavaScriptMode.unrestricted`.
2. **Navigasi dibiarkan berjalan** (`NavigationDecision.navigate`). Penanda "berada di Music" **tidak** diaktifkan saat navigasi dimulai — halaman bisa jadi belum selesai dimuat sehingga cookie/`ytcfg` belum lengkap.
3. **Tombol "Gunakan Akun" aktif hanya setelah `onPageFinished`** memastikan halaman `music.youtube.com` selesai dimuat penuh (lihat §7).
4. Saat tombol ditekan (`_captureSession`), dilakukan **satu percobaan**:
   - Ambil cookie domain `https://music.youtube.com` via `WebviewCookieManager` (fork `webview_cookie_manager_plus`), lalu susun header cookie `name=value; ...`.
   - Jalankan probe `ytcfg` (`_kYtcfgProbe`) untuk membaca `LOGGED_IN`, `DELEGATED_SESSION_ID` (pageId), `DATASYNC_ID`, `SESSION_INDEX` (authUser), `VISITOR_DATA`, dan `INNERTUBE_CLIENT_VERSION`.
   - Serahkan hasilnya ke `SonoraScope.of(context).auth.capture(...)`.
5. **Tidak ada percobaan otomatis / polling.** Bila gagal, pengguna cukup menekan tombol lagi. Snackbar sukses `Berhasil masuk` → halaman ditutup; gagal → `Sesi tidak valid, coba lagi`.

### Diagnostik aman

Log debug hanya mencatat **nama/keberadaan** cookie keluarga SAPISID dan **status terisi (boolean)** tiap kolom probe — **nilai cookie dan isi respons tidak pernah dicatat**.

---

## 3. Model Sesi: `YoutubeSession`

`YoutubeSession` (`lib/data/youtube_session.dart`) adalah nilai sesi yang disimpan:

| Field | Tipe | Sumber `ytcfg` | Kegunaan |
| :--- | :--- | :--- | :--- |
| `cookie` | `String` | Cookie WebView | Header `Cookie` + sumber SAPISID |
| `pageId` | `String?` | `DELEGATED_SESSION_ID` | Header `X-Goog-PageId` (opsional) |
| `dataSyncId` | `String` | `DATASYNC_ID` | `context.user.onBehalfOfUser` (lihat §6) |
| `authUser` | `String` | `SESSION_INDEX` | Header `X-Goog-AuthUser` (default `"0"`) |
| `visitorData` | `String` | `VISITOR_DATA` | Header `X-Goog-Visitor-Id` |
| `clientVersion` | `String` | `INNERTUBE_CLIENT_VERSION` | Header `X-YouTube-Client-Version` & `context.client.clientVersion` |

- **`YoutubeSession.sapisidFromCookie(cookie)`** mengambil nilai SAPISID dengan urutan prioritas `SAPISID` → `__Secure-3PAPISID` → `__Secure-1PAPISID`. `null` berarti sesi tidak dianggap masuk.
- **`fromJson`** menolak (`null`) JSON yang tidak lengkap atau cookie tanpa keluarga SAPISID — dasar pembuangan sesi rusak saat restore.
- **`AccountInfo`** (`name`, `email?`, `avatarUrl?`) adalah hasil parsing `account_menu`; field yang tidak ditemukan bernilai `null`, `name` kosong berarti nama tak terbaca.

### Penyimpanan terenkripsi (`SessionStore`)

`SessionStore` adalah abstraksi tulis/baca/hapus string JSON:

- **`FlutterSecureSessionStore`** (produksi): `flutter_secure_storage` dengan kunci `sonora.ytmusic_session` — nilai dienkripsi perangkat.
- **`InMemorySessionStore`** (pengujian): penyimpanan memori, dipakai juga sebagai sesi anonim fallback di `SonoraScope`.

---

## 4. Penandatanganan Request innertube (`SAPISIDHASH`)

`YouTubeMusicService._postMusicInnertube` mengirim POST ke `https://music.youtube.com/youtubei/v1/<endpoint>` dengan header gaya klien web **WEB_REMIX** (BitChord `Innertube.kt`):

- `Authorization: SAPISIDHASH <timestamp>_<hash>`
- `X-YouTube-Client-Name: 67` (WEB_REMIX), `X-YouTube-Client-Version`, `X-Goog-Visitor-Id`, `X-Goog-AuthUser`, `X-Goog-PageId` (bila ada), `Cookie`, `Origin`/`X-Origin`/`Referer` = `https://music.youtube.com`.
- Body `context.client` memakai `clientName: WEB_REMIX` + `clientVersion` sesi (fallback `1.20250331.01.00` bila anonim).

**Rumus hash** (fungsi bebas `sapisidHash` di `youtube_session.dart`, mudah diuji dengan jam tiruan):

```
sha1("{timestamp} {sapisid} {origin}")  →  heksadesimal huruf kecil
```

`timestamp` adalah detik Unix (`millisecondsSinceEpoch ~/ 1000`), `origin` = `https://music.youtube.com`.

### Endpoint yang dipakai

| Endpoint | Metode | Fungsi |
| :--- | :--- | :--- |
| `account/account_menu` | POST | Validasi sesi + profil (`fetchAccountInfo`) |
| `browse` (`FEmusic_liked_videos`) | POST | Daftar Disukai (`fetchLiked`) |
| `browse` (`FEmusic_history`) | POST | Riwayat (`fetchHistory`) |
| `browse` (`FEmusic_home`) | POST | Rak beranda personal (`fetchHomeSections`) |
| `search` | POST | Pencarian terotorisasi (`_searchSignedIn`) |
| `like/like` | POST | Menyukai video (`likeVideo`) |
| `playlist/create` | POST | Membuat playlist privat (`createPlaylist`) |

Tanpa sesi aktif, request tetap dikirim sebagai anonim tanpa `Cookie`/`Authorization`, dan pencarian jatuh ke jalur `www.youtube.com` (WEB) seperti sebelumnya.

---

## 5. `YoutubeAuthService` & Desain Validasi Berbasis Status

`YoutubeAuthService` (`lib/data/youtube_auth_service.dart`) adalah `ChangeNotifier` yang dipasang di `SonoraScope.auth` (tidak pernah `null`):

- **`capture(...)`** — membangun `YoutubeSession`, menolak bila cookie tanpa keluarga SAPISID, menjalankan validator opsional, lalu menyimpan JSON terenkripsi. Mengembalikan `false` (tanpa mengubah state) bila ditolak/gagal tulis.
- **`restore()`** — dipanggil saat startup; sesi rusak/kosong dibuang diam-diam; kegagalan jaringan saat mengisi profil tidak menggagalkan pemulihan.
- **`signOut()`** — menghapus sesi dari penyimpanan dan memori.
- **`validate`** di `main.dart` diarahkan ke `YouTubeMusicService.validateSession`.

**Validasi berbasis status (bukan parsing nama):** `validateSession` menganggap sesi valid **cukup bila `account/account_menu` mengembalikan HTTP 200**, tanpa bergantung pada bentuk JSON respons. Perubahan struktur respons Google tidak lagi menolak cookie yang sebenarnya masih aktif. Pengambilan nama/email/avatar (`fetchAccountInfo`) bersifat pelengkap — kegagalannya tidak pernah membatalkan sesi.

---

## 6. Dua Jebakan Produksi

### 6a. Probe `ytcfg` ter-encode ganda (Android)

**Gejala:** login tampak sukses tetapi sesi ditolak / field probe kosong.
**Akar masalah:** `WebViewController.runJavaScriptReturningResult` di Android mengembalikan String JSON yang **ter-encode dua kali** (`"\"{\\\"loggedIn\\\":\\\"1\\\"}\""`).
**Perbaikan:** `_parseProbe` men-decode berulang (maksimal dua kali) sampai berbentuk `Map`; hasil non-peta dianggap gagal dan mengembalikan peta kosong.

### 6b. Sufiks `||` pada `DATASYNC_ID` → HTTP 500

**Gejala:** `account/account_menu` (dan request innertube lain) mengembalikan **HTTP 500** walau cookie valid.
**Akar masalah:** `DATASYNC_ID` dari `ytcfg` berformat `"<id>||<timestamp>"`. Mengirim nilai lengkap sebagai `context.user.onBehalfOfUser` ditolak Google.
**Perbaikan:** kirim hanya bagian sebelum `||` → `active.dataSyncId.split('||').first`.

---

## 7. Keputusan UX: Tombol "Gunakan Akun" Manual

Penangkapan **tidak** dilakukan otomatis saat halaman Music selesai dimuat. Sebagai gantinya:

- Tombol **Gunakan Akun** baru aktif setelah `onPageFinished` memastikan halaman `music.youtube.com` benar-benar selesai dimuat (cookie + `ytcfg` lengkap).
- Penangkapan hanya berjalan saat pengguna menekan tombol — satu percobaan per tekan.

Alasan: menghindari notifikasi gagal yang muncul sendiri saat cookie/`ytcfg` belum siap, dan memberi kendali penuh ke pengguna atas kapan sesi disimpan. Kegagalan cukup diulang dengan menekan tombol lagi.

---

## 8. Ketahanan (Graceful Degradation)

Seluruh fitur akun bersifat opsional dan tidak boleh membuat UI error:

- `fetchLiked` / `fetchHistory` / `fetchHomeSections` mengembalikan daftar kosong bila gagal atau belum masuk → seksi terkait disembunyikan.
- `_searchSignedIn` mengembalikan `null` bila gagal → pencarian jatuh ke jalur anonim.
- `fetchAccountInfo` tidak pernah melempar exception; kegagalan jaringan hanya mengosongkan field profil.
- Pemulihan sesi saat startup dibungkus `try/catch` di `main.dart` — kegagalan tidak menggagalkan start aplikasi.