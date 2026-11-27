/// Layanan pengelola berkas cache audio lokal Sonora.
///
/// Mengelola dan menghitung pemakaian ruang penyimpanan direktori cache
/// `just_audio_cache` di perangkat (getTemporaryDirectory).
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AudioCacheService {
  const AudioCacheService();

  /// Batas maksimal cache audio lokal (500 MB).
  static const int defaultMaxCacheSizeBytes = 500 * 1024 * 1024;

  /// Mengambil direktori cache `just_audio_cache`.
  static Future<Directory> getCacheDirectory() async {
    final Directory tempDir = await getTemporaryDirectory();
    return Directory(p.join(tempDir.path, 'just_audio_cache'));
  }

  /// Menghitung total ukuran berkas cache audio dalam byte.
  static Future<int> getCacheSizeBytes() async {
    try {
      final Directory dir = await getCacheDirectory();
      if (!await dir.exists()) return 0;
      int total = 0;
      await for (final FileSystemEntity entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          total += await entity.length();
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  /// Memeriksa dan memangkas berkas cache audio jika ukuran total melebihi [maxBytes].
  ///
  /// Menggunakan strategi LRU (Least Recently Used) dengan menghapus berkas paling
  /// lama dimodifikasi terlebih dahulu hingga ukuran total berada di ambang aman
  /// (80% dari batas maksimal, yaitu ~400 MB).
  static Future<void> pruneCache({
    int maxBytes = defaultMaxCacheSizeBytes,
  }) async {
    try {
      final Directory dir = await getCacheDirectory();
      if (!await dir.exists()) return;

      final List<File> files = <File>[];
      int total = 0;

      await for (final FileSystemEntity entity
          in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          files.add(entity);
          total += await entity.length();
        }
      }

      if (total <= maxBytes) return;

      final List<(File, DateTime, int)> fileStats = <(File, DateTime, int)>[];
      for (final File file in files) {
        try {
          final FileStat stat = await file.stat();
          fileStats.add((file, stat.modified, stat.size));
        } catch (_) {}
      }

      // Urutkan ascending berdasarkan waktu modifikasi (tertua di awal)
      fileStats.sort(
        ((File, DateTime, int) a, (File, DateTime, int) b) =>
            a.$2.compareTo(b.$2),
      );

      final int targetSize = (maxBytes * 0.8).toInt();
      int currentSize = total;

      for (final (File file, _, int size) in fileStats) {
        if (currentSize <= targetSize) break;
        try {
          await file.delete();
          currentSize -= size;
        } catch (_) {
          // File mungkin sedang dikunci oleh pemutar aktif; abaikan dan lanjutkan.
        }
      }
    } catch (_) {}
  }

  /// Menghapus seluruh berkas cache audio lokal yang tersimpan.
  static Future<void> clearCache() async {
    try {
      final Directory dir = await getCacheDirectory();
      if (!dir.existsSync()) return;
      for (final FileSystemEntity entity
          in dir.listSync(recursive: false, followLinks: false)) {
        try {
          if (entity is File) {
            entity.deleteSync();
          } else if (entity is Directory) {
            entity.deleteSync(recursive: true);
          }
        } catch (_) {
          // File mungkin sedang dikunci pemutar aktif; lewati berkas terkunci.
        }
      }
    } catch (_) {}
  }

  /// Format ukuran byte ke string yang mudah dibaca (contoh: "14.2 MB" atau "520 KB").
  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const List<String> suffixes = <String>['B', 'KB', 'MB', 'GB'];
    int i = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(i == 0 ? 0 : 1)} ${suffixes[i]}';
  }
}
