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
      await for (final FileSystemEntity entity
          in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          total += await entity.length();
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  /// Menghapus seluruh berkas cache audio lokal yang tersimpan.
  static Future<void> clearCache() async {
    try {
      final Directory dir = await getCacheDirectory();
      if (!await dir.exists()) return;
      await for (final FileSystemEntity entity
          in dir.list(recursive: false, followLinks: false)) {
        try {
          if (entity is File) {
            await entity.delete();
          } else if (entity is Directory) {
            await entity.delete(recursive: true);
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
