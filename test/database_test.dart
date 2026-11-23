import 'package:flutter_test/flutter_test.dart';
import 'package:sonora_flutter/data/local_database.dart';
import 'package:sonora_flutter/data/music_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  group('LocalDatabase', () {
    late LocalDatabase db;

    setUp(() async {
      db = await LocalDatabase.open(
        factory: databaseFactoryFfi,
        customPath: inMemoryDatabasePath,
      );
    });

    tearDown(() async {
      await db.close();
    });

    test('1. Playback History: mencatat, membaca, dan membatasi entri', () async {
      const song1 = MusicItem(
        type: 'song',
        title: 'Song One',
        artist: 'Artist A',
        videoId: 'vid1',
      );
      const song2 = MusicItem(
        type: 'song',
        title: 'Song Two',
        artist: 'Artist B',
        videoId: 'vid2',
      );

      await db.recordPlayback(
        song1,
        playedAt: DateTime.fromMillisecondsSinceEpoch(1000),
      );
      await db.recordPlayback(
        song2,
        playedAt: DateTime.fromMillisecondsSinceEpoch(2000),
      );

      final recents = await db.getRecentPlaybacks();
      expect(recents, hasLength(2));
      expect(recents.first.videoId, 'vid2');
      expect(recents.last.videoId, 'vid1');

      await db.clearPlaybackHistory();
      expect(await db.getRecentPlaybacks(), isEmpty);
    });

    test('2. Favorite Tracks: menambah, mengecek, menghapus favorit', () async {
      const song = MusicItem(
        type: 'song',
        title: 'Favorite Song',
        artist: 'Fav Artist',
        videoId: 'fav123',
      );

      expect(await db.isFavorite('fav123'), isFalse);

      await db.addFavorite(song);
      expect(await db.isFavorite('fav123'), isTrue);

      final list = await db.getFavorites();
      expect(list, hasLength(1));
      expect(list.first.title, 'Favorite Song');

      await db.removeFavorite('fav123');
      expect(await db.isFavorite('fav123'), isFalse);
    });

    test('3. Search History: mencatat kata kunci dan menaikkan count', () async {
      await db.recordSearch('lofi beats', filter: 'song');
      await db.recordSearch('jazz relax');
      await db.recordSearch('lofi beats'); // update counter

      final searches = await db.getRecentSearches();
      expect(searches, hasLength(2));

      final lofi = searches.firstWhere((s) => s.query == 'lofi beats');
      expect(lofi.searchCount, 2);

      await db.deleteSearch('jazz relax');
      expect(await db.getRecentSearches(), hasLength(1));

      await db.clearSearchHistory();
      expect(await db.getRecentSearches(), isEmpty);
    });

    test('4. User Playlists & Collections: create, add tracks, save collection', () async {
      await db.createPlaylist('p1', 'My Playlist', description: 'Test');
      const song = MusicItem(
        type: 'song',
        title: 'Song in Playlist',
        artist: 'Artist P',
        videoId: 'vidP',
      );
      await db.addToPlaylist('p1', song);
      final tracks = await db.getPlaylistTracks('p1');
      expect(tracks, hasLength(1));
      expect(tracks.first.title, 'Song in Playlist');

      final playlists = await db.getPlaylists();
      expect(playlists.any((p) => p['id'] == 'p1'), isTrue);

      const album = MusicItem(
        type: 'album',
        title: 'Awesome Album',
        browseId: 'MPREb_123',
      );
      await db.saveCollection(album);
      expect(await db.isCollectionSaved(album), isTrue);
      final saved = await db.getSavedCollections('album');
      expect(saved, hasLength(1));
      expect(saved.first.title, 'Awesome Album');
      await db.removeCollection(album);
      expect(await db.isCollectionSaved(album), isFalse);
    });

    test('5. Listening Stats: rekam durasi riil, abaikan skip cepat, hitung top tracks & artists', () async {
      const track1 = MusicItem(
        type: 'song',
        title: 'Track A',
        artist: 'Artist One',
        videoId: 'vidA',
      );
      const track2 = MusicItem(
        type: 'song',
        title: 'Track B',
        artist: 'Artist One',
        videoId: 'vidB',
      );

      final now = DateTime.now();

      // Abaikan jika < 15 detik
      await db.recordListeningLog(item: track1, listenedSeconds: 10, playedAt: now);
      var stats = await db.getListeningStats(0);
      expect(stats.totalPlays, 0);

      // Rekam track1 120 detik (2 menit)
      await db.recordListeningLog(item: track1, listenedSeconds: 120, playedAt: now);
      // Rekam track1 lagi 180 detik (3 menit)
      await db.recordListeningLog(item: track1, listenedSeconds: 180, playedAt: now);
      // Rekam track2 60 detik (1 menit)
      await db.recordListeningLog(item: track2, listenedSeconds: 60, playedAt: now);

      stats = await db.getListeningStats(0);
      expect(stats.totalPlays, 3);
      expect(stats.totalMinutes, 6); // (120 + 180 + 60) / 60 = 6 menit
      expect(stats.topTracks.first.videoId, 'vidA');
      expect(stats.topTracks.first.playCount, 2);
      expect(stats.topTracks.first.totalMinutes, 5);
      expect(stats.topArtists.first.artist, 'Artist One');
      expect(stats.topArtists.first.playCount, 3);
    });
  });
}
