/// Basis data lokal SQLite untuk Sonora Flutter.
///
/// Menyediakan 3 tabel penyimpanan lokal:
/// 1. `playback_history`: Riwayat lagu yang diputar di perangkat.
/// 2. `favorite_tracks`: Daftar lagu favorit yang disimpan lokal oleh pengguna.
/// 3. `search_history`: Riwayat kata kunci pencarian terakhir beserta frekuensi cari.
library;

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'music_models.dart';

/// Item riwayat pencarian.
class SearchHistoryItem {
  const SearchHistoryItem({
    required this.query,
    this.filter,
    required this.searchedAt,
    this.searchCount = 1,
  });

  final String query;
  final String? filter;
  final DateTime searchedAt;
  final int searchCount;

  factory SearchHistoryItem.fromMap(Map<String, Object?> map) {
    return SearchHistoryItem(
      query: map['query'] as String,
      filter: map['filter'] as String?,
      searchedAt: DateTime.fromMillisecondsSinceEpoch(
        map['searched_at'] as int? ?? 0,
      ),
      searchCount: map['search_count'] as int? ?? 1,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'query': query,
        'filter': filter,
        'searched_at': searchedAt.millisecondsSinceEpoch,
        'search_count': searchCount,
      };
}

/// Pengelola SQLite untuk Sonora.
class LocalDatabase {
  LocalDatabase(this._db);

  final Database _db;

  static const String dbName = 'sonora_local.db';
  static const int dbVersion = 1;

  static const String tablePlaybackHistory = 'playback_history';
  static const String tableFavoriteTracks = 'favorite_tracks';
  static const String tableSearchHistory = 'search_history';

  /// Membuka atau membuat database lokal Sonora.
  static Future<LocalDatabase> open({
    DatabaseFactory? factory,
    String? customPath,
  }) async {
    final effectiveFactory = factory ?? databaseFactory;
    final String path = customPath ??
        p.join(await effectiveFactory.getDatabasesPath(), dbName);

    final db = await effectiveFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: dbVersion,
        onCreate: (db, version) async {
          await _createTables(db);
        },
      ),
    );

    return LocalDatabase(db);
  }

  static Future<void> _createTables(DatabaseExecutor db) async {
    // 1. Tabel riwayat pemutaran lagu
    await db.execute('''
      CREATE TABLE $tablePlaybackHistory (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        video_id TEXT NOT NULL,
        title TEXT NOT NULL,
        artist TEXT NOT NULL,
        thumbnail TEXT,
        duration TEXT,
        played_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE INDEX idx_playback_history_played_at
      ON $tablePlaybackHistory(played_at DESC)
    ''');
    await db.execute('''
      CREATE INDEX idx_playback_history_video_id
      ON $tablePlaybackHistory(video_id)
    ''');

    // 2. Tabel lagu favorit lokal
    await db.execute('''
      CREATE TABLE $tableFavoriteTracks (
        video_id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        artist TEXT NOT NULL,
        thumbnail TEXT,
        duration TEXT,
        added_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE INDEX idx_favorite_tracks_added_at
      ON $tableFavoriteTracks(added_at DESC)
    ''');

    // 3. Tabel riwayat pencarian
    await db.execute('''
      CREATE TABLE $tableSearchHistory (
        query TEXT PRIMARY KEY,
        filter TEXT,
        searched_at INTEGER NOT NULL,
        search_count INTEGER NOT NULL DEFAULT 1
      )
    ''');
    await db.execute('''
      CREATE INDEX idx_search_history_searched_at
      ON $tableSearchHistory(searched_at DESC)
    ''');
  }

  // ---------------------------------------------------------------------------
  // 1. Playback History
  // ---------------------------------------------------------------------------

  /// Mencatat lagu yang baru diputar. Membatasi riwayat maksimal 100 entri.
  Future<void> recordPlayback(MusicItem item, {DateTime? playedAt}) async {
    final videoId = item.videoId?.trim() ?? '';
    if (videoId.isEmpty) return;

    final timestamp = (playedAt ?? DateTime.now()).millisecondsSinceEpoch;

    await _db.insert(
      tablePlaybackHistory,
      <String, Object?>{
        'video_id': videoId,
        'title': item.title,
        'artist': item.artist,
        'thumbnail': item.thumbnail,
        'duration': item.duration,
        'played_at': timestamp,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // Bersihkan entri lama jika melebihi 100
    await _db.execute('''
      DELETE FROM $tablePlaybackHistory
      WHERE id NOT IN (
        SELECT id FROM $tablePlaybackHistory
        ORDER BY played_at DESC
        LIMIT 100
      )
    ''');
  }

  /// Mengambil riwayat lagu yang baru diputar, diurutkan dari yang paling baru.
  Future<List<MusicItem>> getRecentPlaybacks({int limit = 20}) async {
    final rows = await _db.query(
      tablePlaybackHistory,
      orderBy: 'played_at DESC',
      limit: limit,
    );

    return rows.map((row) {
      return MusicItem(
        type: 'song',
        title: row['title'] as String? ?? '',
        artist: row['artist'] as String? ?? '',
        thumbnail: row['thumbnail'] as String?,
        videoId: row['video_id'] as String?,
        duration: row['duration'] as String?,
      );
    }).toList(growable: false);
  }

  /// Menghapus semua riwayat pemutaran.
  Future<void> clearPlaybackHistory() async {
    await _db.delete(tablePlaybackHistory);
  }

  // ---------------------------------------------------------------------------
  // 2. Favorite Tracks
  // ---------------------------------------------------------------------------

  /// Menandai lagu sebagai favorit lokal.
  Future<void> addFavorite(MusicItem item, {DateTime? addedAt}) async {
    final videoId = item.videoId?.trim() ?? '';
    if (videoId.isEmpty) return;

    final timestamp = (addedAt ?? DateTime.now()).millisecondsSinceEpoch;

    await _db.insert(
      tableFavoriteTracks,
      <String, Object?>{
        'video_id': videoId,
        'title': item.title,
        'artist': item.artist,
        'thumbnail': item.thumbnail,
        'duration': item.duration,
        'added_at': timestamp,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Menghapus lagu dari favorit lokal.
  Future<void> removeFavorite(String videoId) async {
    final trimmed = videoId.trim();
    if (trimmed.isEmpty) return;
    await _db.delete(
      tableFavoriteTracks,
      where: 'video_id = ?',
      whereArgs: <Object>[trimmed],
    );
  }

  /// Mengecek apakah lagu difavoritkan.
  Future<bool> isFavorite(String videoId) async {
    final trimmed = videoId.trim();
    if (trimmed.isEmpty) return false;

    final count = Sqflite.firstIntValue(
      await _db.rawQuery(
        'SELECT COUNT(*) FROM $tableFavoriteTracks WHERE video_id = ?',
        <Object>[trimmed],
      ),
    );
    return (count ?? 0) > 0;
  }

  /// Mengambil semua lagu favorit lokal terbaru.
  Future<List<MusicItem>> getFavorites({int limit = 50}) async {
    final rows = await _db.query(
      tableFavoriteTracks,
      orderBy: 'added_at DESC',
      limit: limit,
    );

    return rows.map((row) {
      return MusicItem(
        type: 'song',
        title: row['title'] as String? ?? '',
        artist: row['artist'] as String? ?? '',
        thumbnail: row['thumbnail'] as String?,
        videoId: row['video_id'] as String?,
        duration: row['duration'] as String?,
      );
    }).toList(growable: false);
  }

  // ---------------------------------------------------------------------------
  // 3. Search History
  // ---------------------------------------------------------------------------

  /// Mencatat riwayat kata kunci pencarian.
  Future<void> recordSearch(
    String rawQuery, {
    String? filter,
    DateTime? searchedAt,
  }) async {
    final query = rawQuery.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (query.isEmpty) return;

    final timestamp = (searchedAt ?? DateTime.now()).millisecondsSinceEpoch;

    // Periksa apakah query sudah ada
    final existing = await _db.query(
      tableSearchHistory,
      columns: <String>['search_count'],
      where: 'query = ?',
      whereArgs: <Object>[query],
    );

    if (existing.isNotEmpty) {
      final currentCount = existing.first['search_count'] as int? ?? 1;
      await _db.update(
        tableSearchHistory,
        <String, Object?>{
          'filter': filter,
          'searched_at': timestamp,
          'search_count': currentCount + 1,
        },
        where: 'query = ?',
        whereArgs: <Object>[query],
      );
    } else {
      await _db.insert(
        tableSearchHistory,
        <String, Object?>{
          'query': query,
          'filter': filter,
          'searched_at': timestamp,
          'search_count': 1,
        },
      );
    }

    // Batasi riwayat pencarian hingga 30 entri terbaru
    await _db.execute('''
      DELETE FROM $tableSearchHistory
      WHERE query NOT IN (
        SELECT query FROM $tableSearchHistory
        ORDER BY searched_at DESC
        LIMIT 30
      )
    ''');
  }

  /// Mengambil daftar riwayat pencarian terbaru.
  Future<List<SearchHistoryItem>> getRecentSearches({int limit = 10}) async {
    final rows = await _db.query(
      tableSearchHistory,
      orderBy: 'searched_at DESC',
      limit: limit,
    );

    return rows.map(SearchHistoryItem.fromMap).toList(growable: false);
  }

  /// Menghapus satu kata kunci pencarian.
  Future<void> deleteSearch(String query) async {
    await _db.delete(
      tableSearchHistory,
      where: 'query = ?',
      whereArgs: <Object>[query.trim()],
    );
  }

  /// Mengosongkan seluruh riwayat pencarian.
  Future<void> clearSearchHistory() async {
    await _db.delete(tableSearchHistory);
  }

  /// Menutup koneksi database.
  Future<void> close() async {
    if (_db.isOpen) {
      await _db.close();
    }
  }
}
