/// Pengelola SQLite untuk Sonora: riwayat pemutaran, lagu favorit,
/// riwayat pencarian, playlist pengguna, koleksi tersimpan, dan statistik mendengarkan.
///
/// Disusun dengan prinsip persist-first dan degradasi anggun:
/// kegagalan inisialisasi basis data tidak boleh menggagalkan jalannya
/// aplikasi Sonora.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'music_models.dart';

/// Satu entri riwayat pencarian dari basis data lokal.
@immutable
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
      query: map['query']! as String,
      filter: map['filter'] as String?,
      searchedAt: DateTime.fromMillisecondsSinceEpoch(
        map['searched_at']! as int,
      ),
      searchCount: (map['search_count'] as int?) ?? 1,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
    'query': query,
    'filter': filter,
    'searched_at': searchedAt.millisecondsSinceEpoch,
    'search_count': searchCount,
  };
}

/// Agregasi statistik mendengarkan pengguna.
@immutable
class ListeningStats {
  const ListeningStats({
    required this.totalMinutes,
    required this.totalPlays,
    required this.topTracks,
    required this.topArtists,
  });

  final int totalMinutes;
  final int totalPlays;
  final List<TopTrackStat> topTracks;
  final List<TopArtistStat> topArtists;
}

/// Statistik lagu teratas yang paling sering didengarkan.
@immutable
class TopTrackStat {
  const TopTrackStat({
    required this.videoId,
    required this.title,
    required this.artist,
    this.thumbnail,
    required this.playCount,
    required this.totalMinutes,
  });

  final String videoId;
  final String title;
  final String artist;
  final String? thumbnail;
  final int playCount;
  final int totalMinutes;
}

/// Statistik artis teratas yang paling sering didengarkan.
@immutable
class TopArtistStat {
  const TopArtistStat({
    required this.artist,
    required this.playCount,
    required this.totalMinutes,
  });

  final String artist;
  final int playCount;
  final int totalMinutes;
}

/// Pengelola SQLite untuk Sonora.
class LocalDatabase {
  LocalDatabase(this._db);

  final Database _db;

  static const String dbName = 'sonora_local.db';
  static const int dbVersion = 5;

  static const String tablePlaybackHistory = 'playback_history';
  static const String tableFavoriteTracks = 'favorite_tracks';
  static const String tableSearchHistory = 'search_history';
  static const String tablePlaylists = 'user_playlists';
  static const String tablePlaylistTracks = 'playlist_tracks';
  static const String tableSavedCollections = 'saved_collections';
  static const String tableListeningLogs = 'listening_logs';

  /// Membuka atau membuat database lokal Sonora.
  static Future<LocalDatabase> open({
    DatabaseFactory? factory,
    String? customPath,
  }) async {
    final effectiveFactory = factory ?? databaseFactory;
    final String path =
        customPath ?? p.join(await effectiveFactory.getDatabasesPath(), dbName);

    final db = await effectiveFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: dbVersion,
        onCreate: (db, version) async {
          await _createTables(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) await _createPlaylistTables(db);
          if (oldVersion < 3) await _addPlaylistArtwork(db);
          if (oldVersion < 4) await _createSavedCollections(db);
          if (oldVersion < 5) await _createListeningLogsTable(db);
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

    // 4. Playlist & Koleksi
    await _createPlaylistTables(db);
    await _createSavedCollections(db);

    // 5. Statistik Mendengarkan
    await _createListeningLogsTable(db);
    await _ensureFavoritesPlaylist(db);
  }

  static Future<void> _ensureFavoritesPlaylist(DatabaseExecutor db) async {
    await db.insert(tablePlaylists, <String, Object?>{
      'id': 'favorites',
      'name': 'Favorit',
      'description': 'Lagu yang kamu sukai',
      'created_at': 0,
      'updated_at': 0,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.execute('''
      INSERT OR IGNORE INTO $tablePlaylistTracks
      (playlist_id, video_id, title, artist, thumbnail, duration, added_at)
      SELECT 'favorites', video_id, title, artist, thumbnail, duration, added_at
      FROM $tableFavoriteTracks
    ''');
  }

  static Future<void> _createPlaylistTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tablePlaylists (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        artwork_url TEXT,
        artwork_path TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tablePlaylistTracks (
        playlist_id TEXT NOT NULL,
        video_id TEXT NOT NULL,
        title TEXT NOT NULL,
        artist TEXT NOT NULL DEFAULT '',
        thumbnail TEXT,
        duration TEXT,
        added_at INTEGER NOT NULL,
        PRIMARY KEY (playlist_id, video_id),
        FOREIGN KEY (playlist_id) REFERENCES $tablePlaylists(id) ON DELETE CASCADE
      )
    ''');
  }

  static Future<void> _addPlaylistArtwork(DatabaseExecutor db) async {
    final columns = await db.rawQuery('PRAGMA table_info($tablePlaylists)');
    final names = columns.map((row) => row['name']).toSet();
    if (!names.contains('artwork_url')) {
      await db.execute(
        'ALTER TABLE $tablePlaylists ADD COLUMN artwork_url TEXT',
      );
    }
    if (!names.contains('artwork_path')) {
      await db.execute(
        'ALTER TABLE $tablePlaylists ADD COLUMN artwork_path TEXT',
      );
    }
  }

  static Future<void> _createSavedCollections(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableSavedCollections (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        title TEXT NOT NULL,
        browse_id TEXT,
        thumbnail TEXT,
        added_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_saved_collections_type
      ON $tableSavedCollections(type, added_at DESC)
    ''');
  }

  static Future<void> _createListeningLogsTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableListeningLogs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        video_id TEXT NOT NULL,
        title TEXT NOT NULL,
        artist TEXT NOT NULL DEFAULT '',
        thumbnail TEXT,
        duration_seconds INTEGER NOT NULL DEFAULT 0,
        listened_seconds INTEGER NOT NULL DEFAULT 0,
        played_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_listening_logs_played_at
      ON $tableListeningLogs(played_at DESC)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_listening_logs_video
      ON $tableListeningLogs(video_id)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_listening_logs_artist
      ON $tableListeningLogs(artist)
    ''');
  }

  // ---------------------------------------------------------------------------
  // 1. Playlists
  // ---------------------------------------------------------------------------

  Future<void> createPlaylist(
    String id,
    String name, {
    String description = '',
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.insert(tablePlaylists, <String, Object?>{
      'id': id,
      'name': name.trim(),
      'description': description.trim(),
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<void> updatePlaylist(
    String id, {
    required String name,
    required String description,
    String? artworkUrl,
    String? artworkPath,
  }) async => _db.update(
    tablePlaylists,
    <String, Object?>{
      'name': name.trim(),
      'description': description.trim(),
      'artwork_url': artworkUrl,
      'artwork_path': artworkPath,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    },
    where: 'id = ?',
    whereArgs: <Object>[id],
  );

  Future<void> deletePlaylist(String id) async => _db.transaction((txn) async {
    await txn.delete(
      tablePlaylistTracks,
      where: 'playlist_id = ?',
      whereArgs: <Object>[id],
    );
    await txn.delete(tablePlaylists, where: 'id = ?', whereArgs: <Object>[id]);
  });

  Future<List<Map<String, Object?>>> getPlaylists() async {
    final rows = await _db.rawQuery(
      '''
      SELECT p.*, COUNT(t.video_id) AS track_count
      FROM $tablePlaylists p
      LEFT JOIN $tablePlaylistTracks t ON p.id = t.playlist_id
      GROUP BY p.id
      ORDER BY p.updated_at DESC
      ''',
    );
    return rows;
  }

  Future<void> addToPlaylist(String playlistId, MusicItem item) async {
    final id = item.videoId?.trim() ?? '';
    if (id.isEmpty) return;
    await _db.insert(tablePlaylistTracks, <String, Object?>{
      'playlist_id': playlistId,
      'video_id': id,
      'title': item.title,
      'artist': item.artist,
      'thumbnail': item.thumbnail,
      'duration': item.duration,
      'added_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await _db.update(
      tablePlaylists,
      <String, Object?>{'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: <Object>[playlistId],
    );
  }

  Future<void> removeFromPlaylist(String playlistId, String videoId) async =>
      _db.delete(
        tablePlaylistTracks,
        where: 'playlist_id = ? AND video_id = ?',
        whereArgs: <Object>[playlistId, videoId],
      );

  Future<List<MusicItem>> getPlaylistTracks(String playlistId) async {
    final rows = await _db.query(
      tablePlaylistTracks,
      where: 'playlist_id = ?',
      whereArgs: <Object>[playlistId],
      orderBy: 'added_at DESC',
    );
    return rows
        .map(
          (row) => MusicItem(
            type: 'song',
            title: row['title'] as String? ?? '',
            artist: row['artist'] as String? ?? '',
            thumbnail: row['thumbnail'] as String?,
            videoId: row['video_id'] as String?,
            duration: row['duration'] as String?,
          ),
        )
        .toList(growable: false);
  }

  // ---------------------------------------------------------------------------
  // 2. Saved Collections
  // ---------------------------------------------------------------------------

  Future<void> saveCollection(MusicItem item) async {
    final id = item.browseTarget ?? item.playlistId ?? item.title;
    if (id.trim().isEmpty) return;
    await _db.insert(tableSavedCollections, <String, Object?>{
      'id': '${item.type}:$id',
      'type': item.type,
      'title': item.title,
      'browse_id': item.browseTarget,
      'thumbnail': item.thumbnail,
      'added_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> removeCollection(MusicItem item) async {
    final id = item.browseTarget ?? item.playlistId ?? item.title;
    await _db.delete(
      tableSavedCollections,
      where: 'id = ?',
      whereArgs: <Object>['${item.type}:$id'],
    );
  }

  Future<bool> isCollectionSaved(MusicItem item) async {
    final id = item.browseTarget ?? item.playlistId ?? item.title;
    final rows = await _db.query(
      tableSavedCollections,
      where: 'id = ?',
      whereArgs: <Object>['${item.type}:$id'],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<List<MusicItem>> getSavedCollections(String type) async {
    final rows = await _db.query(
      tableSavedCollections,
      where: 'type = ?',
      whereArgs: <Object>[type],
      orderBy: 'added_at DESC',
    );
    return rows
        .map(
          (row) => MusicItem(
            type: row['type'] as String? ?? type,
            title: row['title'] as String? ?? '',
            browseId: row['browse_id'] as String?,
            thumbnail: row['thumbnail'] as String?,
          ),
        )
        .toList(growable: false);
  }

  // ---------------------------------------------------------------------------
  // 3. Playback History
  // ---------------------------------------------------------------------------

  /// Mencatat lagu yang baru diputar. Membatasi riwayat maksimal 100 entri.
  Future<void> recordPlayback(MusicItem item, {DateTime? playedAt}) async {
    final videoId = item.videoId?.trim() ?? '';
    if (videoId.isEmpty) return;

    final timestamp = (playedAt ?? DateTime.now()).millisecondsSinceEpoch;

    await _db.insert(tablePlaybackHistory, <String, Object?>{
      'video_id': videoId,
      'title': item.title,
      'artist': item.artist,
      'thumbnail': item.thumbnail,
      'duration': item.duration,
      'played_at': timestamp,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

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

    return rows
        .map((row) {
          return MusicItem(
            type: 'song',
            title: row['title'] as String? ?? '',
            artist: row['artist'] as String? ?? '',
            thumbnail: row['thumbnail'] as String?,
            videoId: row['video_id'] as String?,
            duration: row['duration'] as String?,
          );
        })
        .toList(growable: false);
  }

  /// Mengambil lagu yang diputar sejak awal hari lokal.
  Future<List<MusicItem>> getTodayPlaybacks() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
    return getPlaybacksSince(start);
  }

  /// Mengambil riwayat pemutaran setelah timestamp tertentu.
  Future<List<MusicItem>> getPlaybacksSince(
    int timestamp, {
    int limit = 100,
  }) async {
    final rows = await _db.query(
      tablePlaybackHistory,
      where: 'played_at >= ?',
      whereArgs: <Object>[timestamp],
      orderBy: 'played_at DESC',
      limit: limit,
    );
    return rows
        .map(
          (row) => MusicItem(
            type: 'song',
            title: row['title'] as String? ?? '',
            artist: row['artist'] as String? ?? '',
            thumbnail: row['thumbnail'] as String?,
            videoId: row['video_id'] as String?,
            duration: row['duration'] as String?,
          ),
        )
        .toList(growable: false);
  }

  /// Menghapus semua riwayat pemutaran.
  Future<void> clearPlaybackHistory() async {
    await _db.delete(tablePlaybackHistory);
  }

  // ---------------------------------------------------------------------------
  // 4. Favorite Tracks
  // ---------------------------------------------------------------------------

  /// Menandai lagu sebagai favorit lokal.
  Future<void> addFavorite(MusicItem item, {DateTime? addedAt}) async {
    final videoId = item.videoId?.trim() ?? '';
    if (videoId.isEmpty) return;

    final timestamp = (addedAt ?? DateTime.now()).millisecondsSinceEpoch;

    await _db.insert(tableFavoriteTracks, <String, Object?>{
      'video_id': videoId,
      'title': item.title,
      'artist': item.artist,
      'thumbnail': item.thumbnail,
      'duration': item.duration,
      'added_at': timestamp,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    await _db.insert(tablePlaylists, <String, Object?>{
      'id': 'favorites',
      'name': 'Favorit',
      'description': 'Lagu yang kamu sukai',
      'created_at': timestamp,
      'updated_at': timestamp,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);

    await addToPlaylist('favorites', item);
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
    await removeFromPlaylist('favorites', trimmed);
  }

  /// Mengecek apakah lagu difavoritkan.
  Future<bool> isFavorite(String videoId) async {
    final trimmed = videoId.trim();
    if (trimmed.isEmpty) return false;

    final rows = await _db.query(
      tableFavoriteTracks,
      columns: <String>['video_id'],
      where: 'video_id = ?',
      whereArgs: <Object>[trimmed],
      limit: 1,
    );

    return rows.isNotEmpty;
  }

  /// Mengambil daftar semua lagu favorit, terurut dari yang terbaru ditambahkan.
  Future<List<MusicItem>> getFavorites({int limit = 100}) async {
    final rows = await _db.query(
      tableFavoriteTracks,
      orderBy: 'added_at DESC',
      limit: limit,
    );

    return rows
        .map((row) {
          return MusicItem(
            type: 'song',
            title: row['title'] as String? ?? '',
            artist: row['artist'] as String? ?? '',
            thumbnail: row['thumbnail'] as String?,
            videoId: row['video_id'] as String?,
            duration: row['duration'] as String?,
          );
        })
        .toList(growable: false);
  }

  // ---------------------------------------------------------------------------
  // 5. Search History
  // ---------------------------------------------------------------------------

  /// Mencatat kata kunci pencarian. Jika query sudah ada, naikkan
  /// [searchCount] dan perbarui timestamp.
  Future<void> recordSearch(String query, {String? filter}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    final timestamp = DateTime.now().millisecondsSinceEpoch;

    final existing = await _db.query(
      tableSearchHistory,
      columns: <String>['query', 'search_count'],
      where: 'query = ?',
      whereArgs: <Object>[trimmed],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      final currentCount = (existing.first['search_count'] as int?) ?? 1;
      await _db.update(
        tableSearchHistory,
        <String, Object?>{
          'filter': filter,
          'searched_at': timestamp,
          'search_count': currentCount + 1,
        },
        where: 'query = ?',
        whereArgs: <Object>[trimmed],
      );
    } else {
      await _db.insert(tableSearchHistory, <String, Object?>{
        'query': trimmed,
        'filter': filter,
        'searched_at': timestamp,
        'search_count': 1,
      });
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

  /// Mengambil riwayat pencarian terbaru.
  Future<List<SearchHistoryItem>> getRecentSearches({int limit = 10}) async {
    final rows = await _db.query(
      tableSearchHistory,
      orderBy: 'searched_at DESC',
      limit: limit,
    );

    return rows.map(SearchHistoryItem.fromMap).toList(growable: false);
  }

  /// Menghapus satu entri riwayat pencarian berdasarkan query.
  Future<void> deleteSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    await _db.delete(
      tableSearchHistory,
      where: 'query = ?',
      whereArgs: <Object>[trimmed],
    );
  }

  /// Menghapus seluruh riwayat pencarian.
  Future<void> clearSearchHistory() async {
    await _db.delete(tableSearchHistory);
  }

  // ---------------------------------------------------------------------------
  // 6. Listening Stats & Sessions
  // ---------------------------------------------------------------------------

  /// Mencatat sesi mendengarkan riil ke statistik.
  /// Diabaikan bila [listenedSeconds] kurang dari 15 detik (skip cepat).
  Future<void> recordListeningLog({
    required MusicItem item,
    required int listenedSeconds,
    int durationSeconds = 0,
    DateTime? playedAt,
  }) async {
    final videoId = item.videoId?.trim() ?? '';
    if (videoId.isEmpty || listenedSeconds < 15) return;

    final timestamp = (playedAt ?? DateTime.now()).millisecondsSinceEpoch;

    await _db.insert(
      tableListeningLogs,
      <String, Object?>{
        'video_id': videoId,
        'title': item.title,
        'artist': item.artist,
        'thumbnail': item.thumbnail,
        'duration_seconds': durationSeconds,
        'listened_seconds': listenedSeconds,
        'played_at': timestamp,
      },
    );
  }

  /// Mengambil agregasi statistik mendengarkan sejak [startTimestamp].
  Future<ListeningStats> getListeningStats(
    int startTimestamp, {
    int limit = 10,
  }) async {
    final summaryRows = await _db.rawQuery(
      '''
      SELECT COUNT(*) AS total_plays,
             COALESCE(SUM(listened_seconds), 0) AS total_seconds
      FROM $tableListeningLogs
      WHERE played_at >= ?
      ''',
      <Object>[startTimestamp],
    );

    int totalPlays = 0;
    int totalMinutes = 0;
    if (summaryRows.isNotEmpty) {
      final row = summaryRows.first;
      totalPlays = (row['total_plays'] as num?)?.toInt() ?? 0;
      final totalSec = (row['total_seconds'] as num?)?.toInt() ?? 0;
      totalMinutes = (totalSec / 60).round();
    }

    final trackRows = await _db.rawQuery(
      '''
      SELECT video_id, title, artist, thumbnail,
             COUNT(*) AS play_count,
             COALESCE(SUM(listened_seconds), 0) AS total_seconds
      FROM $tableListeningLogs
      WHERE played_at >= ?
      GROUP BY video_id
      ORDER BY play_count DESC, total_seconds DESC
      LIMIT ?
      ''',
      <Object>[startTimestamp, limit],
    );

    final topTracks = trackRows.map((row) {
      final sec = (row['total_seconds'] as num?)?.toInt() ?? 0;
      return TopTrackStat(
        videoId: row['video_id'] as String? ?? '',
        title: row['title'] as String? ?? '',
        artist: row['artist'] as String? ?? '',
        thumbnail: row['thumbnail'] as String?,
        playCount: (row['play_count'] as num?)?.toInt() ?? 0,
        totalMinutes: (sec / 60).round(),
      );
    }).toList(growable: false);

    final artistRows = await _db.rawQuery(
      '''
      SELECT artist,
             COUNT(*) AS play_count,
             COALESCE(SUM(listened_seconds), 0) AS total_seconds
      FROM $tableListeningLogs
      WHERE played_at >= ? AND TRIM(artist) != ''
      GROUP BY artist
      ORDER BY play_count DESC, total_seconds DESC
      LIMIT ?
      ''',
      <Object>[startTimestamp, limit],
    );

    final topArtists = artistRows.map((row) {
      final sec = (row['total_seconds'] as num?)?.toInt() ?? 0;
      return TopArtistStat(
        artist: row['artist'] as String? ?? '',
        playCount: (row['play_count'] as num?)?.toInt() ?? 0,
        totalMinutes: (sec / 60).round(),
      );
    }).toList(growable: false);

    return ListeningStats(
      totalMinutes: totalMinutes,
      totalPlays: totalPlays,
      topTracks: topTracks,
      topArtists: topArtists,
    );
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Menutup koneksi database.
  Future<void> close() async {
    await _db.close();
  }
}
