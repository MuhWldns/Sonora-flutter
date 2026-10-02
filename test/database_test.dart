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
  });
}
