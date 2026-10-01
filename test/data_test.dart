/// Tes fokus untuk lapisan data Task 1: model, penyimpanan preferensi, dan
/// klien proxy.
///
/// Payload yang dipakai di sini adalah **respons asli proxy Sonora** (hasil
/// tangkapan live pada 2026-10-01), bukan fixture sintetis. Varian rusak
/// diturunkan dari payload asli dengan mengubah tipe field untuk membuktikan
/// parsing defensif.
///
/// Grup `live proxy` hanya berjalan bila environment `SONORA_PROXY_BASE` diisi,
/// sehingga verifikasi HTTP nyata bisa dilakukan tanpa membuat CI bergantung
/// pada jaringan.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sonora_flutter/data/music_models.dart';
import 'package:sonora_flutter/data/settings_store.dart';
import 'package:sonora_flutter/data/sonora_api.dart';

// ---------------------------------------------------------------------------
// Payload asli (verbatim dari tangkapan proxy)
// ---------------------------------------------------------------------------

const String _healthzJson = '''
{"ok": true, "ts": 1790869951773}
''';

const String _homeJson = '''
{
 "sections": [
  {
   "title": "Quick picks",
   "items": [
    {
     "type": "song",
     "title": "Shape of My Heart",
     "subtitle": "Backstreet Boys • 729M plays • Black & Blue",
     "videoId": "BLhIcQMaaTI",
     "thumbnail": "https://yt3.googleusercontent.com/6nSKYCjwCp1f1GfgYejDk9l-3_65Qgc-sVtfeDyuAk1tSqeuTSnN6h-Z4cBeshn16kP_JIRs9whqlvQt6A=w544-h544-l90-rj",
     "artists": [
      {"name": "Backstreet Boys", "browseId": "UCQsJi7L4_zXzYRN2X0Fw3Zg"}
     ],
     "album": {"name": "Black & Blue", "browseId": "MPREb_vZuWGAa0zeb"}
    },
    {
     "type": "song",
     "title": "IDOL IDOL",
     "subtitle": "Laila Ayu & Simpatik Music • 615K plays • IDOL IDOL",
     "videoId": "Wp1bxnzLpzA",
     "thumbnail": "https://yt3.googleusercontent.com/oklkvbbfR-1C7QCCcbkM6dqPy5hnqYoM1IlFTz8BsZnL3vYx85dgSgrNHWn9pQ0sVhAocMy93M0Nl_ci=w544-h544-l90-rj",
     "artists": [
      {"name": "Laila Ayu", "browseId": "UCZcRzxzEtQ0S73frDcIrLDQ"},
      {"name": "Simpatik Music", "browseId": "UC1kPFwEUi_QQ7wM_lIq8qLQ"}
     ],
     "album": {"name": "IDOL IDOL", "browseId": "MPREb_V8S1wjqWn6u"}
    }
   ]
  },
  {
   "title": "Trending community playlists",
   "items": [
    {
     "type": "playlist",
     "title": "Kompilasi Lagu Pop Indonesia 90an",
     "subtitle": "Dadang Rustiawan • 17M views",
     "thumbnail": "https://yt3.ggpht.com/2908vJ0ZJUho_pXI5ZdX1068GnxX9sp2G8uFN7FqWTsKUNsxuMnCMo8FITvAI7Hapw0ebmmA6Q=s576",
     "artists": [
      {"name": "Dadang Rustiawan", "browseId": "UCnGvEucMqFKWn2fSHeL7afA"}
     ],
     "browseId": "VLPLw3xXmiGk7179fZ_q7f3YgmuD05U7ClHr",
     "browseType": "playlist"
    }
   ]
  }
 ]
}
''';

const String _searchJson = '''
{
 "sections": [
  {
   "title": "Songs",
   "items": [
    {
     "type": "song",
     "title": "Rainforest",
     "subtitle": "Saib • Mangroves • 5:24 • 18M plays",
     "videoId": "Arx6UcDo0T0",
     "thumbnail": "https://yt3.googleusercontent.com/WDbDycgqbaDKDaXcd-FvSoKtlPGjwgqsDJhYNSPqt3E_aZhCGgOjjnOg9S6eWmyfi8-B5taMJJqLnUi9=w544-h544-l90-rj",
     "artists": [
      {"name": "Saib", "browseId": "UCw02oGFeqYXl14LcyKhOTYw"}
     ],
     "album": {"name": "Mangroves", "browseId": "MPREb_oV1p1G9NOe4"}
    },
    {
     "type": "song",
     "title": "3 Hours of Chill Lofi Music for DEEP Sleep or Study Session",
     "subtitle": "Lumosound • 3 Hours of Chill Lofi Music for DEEP Sleep or Study Session • 3:03:37 • 155K plays",
     "videoId": "kAw9xGI8vgk",
     "thumbnail": "https://yt3.googleusercontent.com/Bx7K_CPa195NNoHTdC18w3oip9PPnt7TMChxTrWk3ZpDEqaQqqUyK-TWM1lmJrIjAL8ILp5-n9FrTc2Y=w544-h544-l90-rj",
     "artists": [
      {"name": "Lumosound", "browseId": "UCHyTDJszs60I7FwvJ-2OE4Q"}
     ],
     "album": {"name": "3 Hours of Chill Lofi Music for DEEP Sleep or Study Session", "browseId": "MPREb_RbvsarzzPG0"}
    }
   ],
   "list": true
  }
 ]
}
''';

const String _browseJson = '''
{
 "sections": [
  {
   "title": "",
   "items": [
    {
     "type": "song",
     "title": "Whale Call",
     "subtitle": "3.8M plays",
     "videoId": "zIo1kXQuVz0",
     "thumbnail": null,
     "artists": [],
     "album": null,
     "duration": "3:49"
    },
    {
     "type": "song",
     "title": "Coral Dreams",
     "subtitle": "386K plays",
     "videoId": "bZwLGwOwG6U",
     "thumbnail": null,
     "artists": [],
     "album": null,
     "duration": "2:52"
    }
   ],
   "list": true
  },
  {
   "title": "Releases for you",
   "items": [
    {
     "type": "album",
     "title": "Moonlit Tales",
     "subtitle": "Album • Kalaido",
     "thumbnail": "https://yt3.googleusercontent.com/IMM-Zm4vPqzCwSnJWt2lggUm9eMwWtjSMgDDXrzMnRWcsbYr-08Hr1leITLYW2HjLJUOAdzRConlKsq9=w544-h544-l90-rj",
     "artists": [
      {"name": "Kalaido", "browseId": "UCnX3dJnTo1kf0zZuPcED_FA"}
     ],
     "browseId": "MPREb_NR3FkEE6ZLK",
     "browseType": "album"
    },
    {
     "type": "album",
     "title": "Directions",
     "subtitle": "Album • Blue Wednesday & Shopan",
     "thumbnail": "https://yt3.googleusercontent.com/KMA0wiSLkLnXHvpZ1qihIG727Uktxz7bFCqiVGMZ35XcrcQbePJ38IPD5fuET5wO_kP_BbZv9z0LGT01=w544-h544-l90-rj",
     "artists": [
      {"name": "Blue Wednesday", "browseId": "UCH5Ryy6Kqv89TFDBS6T4bNg"},
      {"name": "Shopan", "browseId": "UCQbhqL8y5I7gfN0zHGNP9WA"}
     ],
     "browseId": "MPREb_kWejpP97RHs",
     "browseType": "album"
    }
   ]
  }
 ]
}
''';

const String _nextJson = '''
{
 "queue": [
  {
   "videoId": "Arx6UcDo0T0",
   "title": "Rainforest",
   "artist": "Saib",
   "duration": "5:24",
   "thumbnail": "https://yt3.googleusercontent.com/WDbDycgqbaDKDaXcd-FvSoKtlPGjwgqsDJhYNSPqt3E_aZhCGgOjjnOg9S6eWmyfi8-B5taMJJqLnUi9=w544-h544-l90-rj",
   "selected": true
  },
  {
   "videoId": "bD9rcSUF4aA",
   "title": "Porto Leone (feat. FloFilz)",
   "artist": "Saib",
   "duration": "2:47",
   "thumbnail": "https://yt3.googleusercontent.com/MX0dcoG8J2i6yCAxBWnknGmQCCV3W1elVj3jnJZuC_nbwu1qipPgUZj1lVZEJT_Z0IlG7VoB0Zg1BaL_MA=w544-h544-l90-rj",
   "selected": false
  }
 ]
}
''';

Object? _decode(String json) => jsonDecode(json);

/// Respons HTTP dengan body UTF-8, meniru proxy nyata (mis. `•`, `Ø`).
http.Response _jsonResponse(String body, [int status = 200]) =>
    http.Response.bytes(
      utf8.encode(body),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('parseDurationMs', () {
    test('durasi m:ss dan h:mm:ss', () {
      expect(parseDurationMs('3:49'), 229000);
      expect(parseDurationMs('2:52'), 172000);
      expect(parseDurationMs('5:24'), 324000);
      expect(parseDurationMs('3:03:37'), 11017000);
      expect(parseDurationMs('0:00'), 0);
      expect(parseDurationMs(' 1:00 '), 60000);
    });

    test('menolak nilai kosong/format tak dikenal', () {
      expect(parseDurationMs(null), isNull);
      expect(parseDurationMs(''), isNull);
      expect(parseDurationMs('   '), isNull);
      expect(parseDurationMs('abc'), isNull);
      expect(parseDurationMs('12'), isNull);
      expect(parseDurationMs('-1:00'), isNull);
      expect(parseDurationMs('1:2:3:4'), isNull);
    });
  });

  group('MusicFeed parsing (payload proxy asli)', () {
    test('healthz', () {
      final status = HealthStatus.fromJson(_decode(_healthzJson));
      expect(status.ok, isTrue);
      expect(status.ts, 1790869951773);
    });

    test('home: sections, lagu dengan artis & album, playlist', () {
      final feed = MusicFeed.fromJson(_decode(_homeJson));
      expect(feed.sections, hasLength(2));

      final quick = feed.sections.first;
      expect(quick.title, 'Quick picks');
      expect(quick.list, isFalse);
      expect(quick.items, hasLength(2));

      final song = quick.items.first;
      expect(song.type, 'song');
      expect(song.title, 'Shape of My Heart');
      expect(song.videoId, 'BLhIcQMaaTI');
      expect(song.isSong, isTrue);
      expect(song.isPlayable, isTrue);
      expect(song.artists, hasLength(1));
      expect(song.artists.first.name, 'Backstreet Boys');
      expect(song.artists.first.browseId, 'UCQsJi7L4_zXzYRN2X0Fw3Zg');
      expect(song.album?.name, 'Black & Blue');
      expect(song.album?.browseId, 'MPREb_vZuWGAa0zeb');

      final multi = quick.items[1];
      expect(multi.artists, hasLength(2));
      expect(multi.artists[1].name, 'Simpatik Music');

      final playlist = feed.sections[1].items.first;
      expect(playlist.isPlaylist, isTrue);
      expect(playlist.browseType, 'playlist');
      expect(playlist.browseId, 'VLPLw3xXmiGk7179fZ_q7f3YgmuD05U7ClHr');
      expect(playlist.browseTarget, 'VLPLw3xXmiGk7179fZ_q7f3YgmuD05U7ClHr');
      expect(playlist.album, isNull);

      expect(feed.isEmpty, isFalse);
      expect(feed.items, hasLength(3));
    });

    test('search: flag list dan subtitle dengan durasi', () {
      final feed = MusicFeed.fromJson(_decode(_searchJson));
      final section = feed.sections.single;
      expect(section.title, 'Songs');
      expect(section.list, isTrue);
      expect(section.items, hasLength(2));

      final long = section.items[1];
      expect(long.title, contains('3 Hours of Chill Lofi'));
      expect(
        long.duration,
        isNull,
      ); // durasi ada di subtitle, bukan field durasi
      expect(long.subtitle, contains('3:03:37'));
    });

    test('browse: thumbnail null, artis kosong, album', () {
      final browse = BrowseResult.fromJson(_decode(_browseJson));
      expect(browse.playlist, isNull);
      expect(browse.sections, hasLength(2));

      final song = browse.sections.first.items.first;
      expect(song.type, 'song');
      expect(song.thumbnail, isNull);
      expect(song.artists, isEmpty);
      expect(song.album, isNull);
      expect(song.duration, '3:49');
      expect(song.durationMs, 229000);

      final album = browse.sections[1].items.first;
      expect(album.isAlbum, isTrue);
      expect(album.browseType, 'album');
      expect(album.browseId, 'MPREb_NR3FkEE6ZLK');
      expect(album.artists.single.name, 'Kalaido');
      expect(album.isPlayable, isFalse);
    });

    test('next: queue, selected, tanpa continuation', () {
      final queue = PlaybackQueue.fromJson(_decode(_nextJson));
      expect(queue.queue, hasLength(2));
      expect(queue.continuation, isNull);
      expect(queue.isEmpty, isFalse);

      final selected = queue.selected;
      expect(selected, isNotNull);
      expect(selected!.videoId, 'Arx6UcDo0T0');
      expect(selected.title, 'Rainforest');
      expect(selected.artist, 'Saib');
      expect(selected.durationMs, 324000);
      expect(queue.queue[1].selected, isFalse);
    });

    test('next: continuation dipertahankan bila ada', () {
      final queue = PlaybackQueue.fromJson({
        'queue': <Object?>[],
        'continuation': 'CBQSABgB',
      });
      expect(queue.continuation, 'CBQSABgB');
      expect(queue.isEmpty, isTrue);
      expect(queue.selected, isNull);
    });
  });

  group('Parsing defensif (payload rusak)', () {
    test('feed non-map / null menjadi kosong', () {
      for (final bad in <Object?>[null, 'bukan json', 42, <Object?>[]]) {
        final feed = MusicFeed.fromJson(bad);
        expect(feed.sections, isEmpty);
        expect(feed.isEmpty, isTrue);
      }
    });

    test('sections bukan list diabaikan', () {
      final feed = MusicFeed.fromJson({'sections': 'oops'});
      expect(feed.sections, isEmpty);
    });

    test('item dengan tipe salah tetap aman', () {
      final item = MusicItem.fromJson({
        'type': 123,
        'title': 456,
        'subtitle': true,
        'thumbnail': 789,
        'artists': 'bukan list',
        'album': 'bukan map',
        'duration': 999,
        'videoId': 111,
        'watchPlaylist': 'true',
      });
      expect(item.type, '123');
      expect(item.title, '456');
      expect(item.subtitle, 'true');
      expect(item.thumbnail, '789');
      expect(item.artists, isEmpty);
      expect(item.album, isNull);
      expect(item.duration, '999');
      expect(item.videoId, '111');
      expect(item.watchPlaylist, isTrue);
    });

    test('entri artis rusak difilter, nama kosong dianggap absen', () {
      final item = MusicItem.fromJson({
        'type': 'song',
        'title': 'X',
        'artists': <Object?>[
          null,
          42,
          <String, Object?>{},
          <String, Object?>{'name': ''},
          <String, Object?>{'name': 'Valid', 'browseId': 'UC1'},
        ],
      });
      expect(item.artists, hasLength(1));
      expect(item.artists.single.name, 'Valid');
    });

    test('durationMs null bila field durasi tidak ada', () {
      final item = MusicItem.fromJson({'type': 'album', 'title': 'A'});
      expect(item.duration, isNull);
      expect(item.durationMs, isNull);
    });

    test('queue item rusak tetap menghasilkan videoId string', () {
      final item = QueueItem.fromJson({'videoId': 42, 'selected': 'yes'});
      expect(item.videoId, '42');
      expect(item.selected, isFalse);
      expect(item.thumbnail, isNull);
    });
  });

  group('SettingsStore.normalizeProxyBase', () {
    test('mempertahankan base path dan menghapus slash ujung', () {
      expect(
        SettingsStore.normalizeProxyBase('https://host:8787/'),
        'https://host:8787',
      );
      expect(
        SettingsStore.normalizeProxyBase('https://host/api/'),
        'https://host/api',
      );
      expect(
        SettingsStore.normalizeProxyBase('  https://host/api/v1///  '),
        'https://host/api/v1',
      );
    });

    test('kosong menjadi null (tidak dikonfigurasi)', () {
      expect(SettingsStore.normalizeProxyBase(null), isNull);
      expect(SettingsStore.normalizeProxyBase(''), isNull);
      expect(SettingsStore.normalizeProxyBase('   '), isNull);
    });

    test('menolak URL tidak valid', () {
      expect(
        () => SettingsStore.normalizeProxyBase('bukan url'),
        throwsArgumentError,
      );
      expect(
        () => SettingsStore.normalizeProxyBase('ftp://host'),
        throwsArgumentError,
      );
      expect(
        () => SettingsStore.normalizeProxyBase('https://host?x=1'),
        throwsArgumentError,
      );
      expect(
        () => SettingsStore.normalizeProxyBase('https://host#frag'),
        throwsArgumentError,
      );
    });
  });

  group('SettingsStore persistence', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    test('load default kosong', () async {
      final store = await SettingsStore.load();
      expect(store.proxyBase, '');
      expect(store.cookie, isNull);
      expect(store.hasProxyBase, isFalse);
      expect(store.hasCookie, isFalse);
      store.dispose();
    });

    test('set/get proxy dan cookie bertahan setelah reload', () async {
      final store = await SettingsStore.load();
      var notified = 0;
      store.addListener(() => notified++);

      await store.setProxyBase('https://host:8787/api/');
      expect(store.proxyBase, 'https://host:8787/api');
      expect(store.hasProxyBase, isTrue);

      await store.setCookie('  SID=abc; HSID=def  ');
      expect(store.cookie, 'SID=abc; HSID=def');
      expect(store.hasCookie, isTrue);
      expect(notified, 2);

      final reloaded = await SettingsStore.load();
      expect(reloaded.proxyBase, 'https://host:8787/api');
      expect(reloaded.cookie, 'SID=abc; HSID=def');
      store.dispose();
      reloaded.dispose();
    });

    test('setProxyBase kosong menghapus konfigurasi', () async {
      final store = await SettingsStore.load();
      await store.setProxyBase('https://host');
      await store.setProxyBase('   ');
      expect(store.proxyBase, '');
      expect(store.hasProxyBase, isFalse);
      final reloaded = await SettingsStore.load();
      expect(reloaded.proxyBase, '');
      store.dispose();
      reloaded.dispose();
    });

    test('setCookie kosong ditolak', () async {
      final store = await SettingsStore.load();
      await expectLater(store.setCookie('   '), throwsArgumentError);
      store.dispose();
    });

    test('clearCookie dan clear', () async {
      final store = await SettingsStore.load();
      await store.setProxyBase('https://host');
      await store.setCookie('SID=1');
      await store.clearCookie();
      expect(store.hasCookie, isFalse);
      expect(store.proxyBase, 'https://host');

      await store.clear();
      expect(store.proxyBase, '');
      expect(store.cookie, isNull);

      final reloaded = await SettingsStore.load();
      expect(reloaded.proxyBase, '');
      expect(reloaded.cookie, isNull);
      store.dispose();
      reloaded.dispose();
    });

    test('nilai korup di penyimpanan diturunkan ke default', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'sonora.proxyBase': 'bukan-url',
        'sonora.cookie': '   ',
      });
      final store = await SettingsStore.load();
      expect(store.proxyBase, '');
      expect(store.cookie, isNull);
      store.dispose();
    });
  });

  group('SonoraApi', () {
    Future<SettingsStore> storeWith({String? proxyBase, String? cookie}) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = await SettingsStore.load();
      if (proxyBase != null) await store.setProxyBase(proxyBase);
      if (cookie != null) await store.setCookie(cookie);
      return store;
    }

    test('mempertahankan base path proxy', () async {
      final store = await storeWith(proxyBase: 'https://host:8787/api');
      final api = SonoraApi(
        store,
        client: MockClient((request) async {
          expect(request.url.path, '/api/healthz');
          return _jsonResponse(_healthzJson, 200);
        }),
      );

      final status = await api.healthz();
      expect(status.ok, isTrue);
      api.close();
      store.dispose();
    });

    test(
      'streamUri mempertahankan base path dan meng-encode videoId',
      () async {
        final store = await storeWith(proxyBase: 'https://host/api/');
        final api = SonoraApi(store);
        final uri = api.streamUri('Arx6UcDo0T0');
        expect(uri.path, '/api/stream');
        expect(uri.queryParameters['videoId'], 'Arx6UcDo0T0');
        api.close();
        store.dispose();
      },
    );

    test(
      'proxy belum dikonfigurasi melempar SonoraConfigurationException',
      () async {
        final store = await storeWith();
        final api = SonoraApi(store);
        expect(api.isConfigured, isFalse);
        await expectLater(
          api.home(),
          throwsA(isA<SonoraConfigurationException>()),
        );
        api.close();
        store.dispose();
      },
    );

    test('mengirim x-yt-cookie hanya untuk endpoint akun', () async {
      final store = await storeWith(
        proxyBase: 'https://host',
        cookie: 'SID=secret',
      );
      final seenHeaders = <String, Map<String, String>>{};
      final api = SonoraApi(
        store,
        client: MockClient((request) async {
          seenHeaders[request.url.path] = request.headers;
          if (request.url.path == '/library') {
            return _jsonResponse(_homeJson, 200);
          }
          return _jsonResponse(_healthzJson, 200);
        }),
      );

      await api.healthz();
      await api.library();

      expect(seenHeaders['/healthz']!.containsKey('x-yt-cookie'), isFalse);
      expect(seenHeaders['/library']!['x-yt-cookie'], 'SID=secret');
      api.close();
      store.dispose();
    });

    test('endpoint akun tanpa cookie langsung 401 tanpa request', () async {
      final store = await storeWith(proxyBase: 'https://host');
      var called = false;
      final api = SonoraApi(
        store,
        client: MockClient((request) async {
          called = true;
          return _jsonResponse('{}', 200);
        }),
      );

      await expectLater(
        api.library(),
        throwsA(
          isA<SonoraApiException>().having(
            (e) => e.isUnauthorized,
            'isUnauthorized',
            isTrue,
          ),
        ),
      );
      expect(called, isFalse);
      api.close();
      store.dispose();
    });

    test('feed asli diparse lewat klien HTTP', () async {
      final store = await storeWith(proxyBase: 'https://host');
      final api = SonoraApi(
        store,
        client: MockClient((request) async {
          switch (request.url.path) {
            case '/home':
              return _jsonResponse(_homeJson, 200);
            case '/search':
              expect(request.url.queryParameters['q'], 'lofi');
              expect(request.url.queryParameters['filter'], 'song');
              return _jsonResponse(_searchJson, 200);
            case '/browse':
              expect(request.url.queryParameters['id'], 'MPREb_NR3FkEE6ZLK');
              return _jsonResponse(_browseJson, 200);
            case '/next':
              return _jsonResponse(_nextJson, 200);
            case '/lyrics':
              return _jsonResponse('{"lyrics": null}', 200);
            default:
              return _jsonResponse('{}', 404);
          }
        }),
      );

      final home = await api.home();
      expect(home.sections.first.items.first.title, 'Shape of My Heart');

      final search = await api.search('lofi', filter: 'song');
      expect(search.sections.single.title, 'Songs');

      final browse = await api.browse('MPREb_NR3FkEE6ZLK');
      expect(browse.sections[1].items.first.isAlbum, isTrue);

      final queue = await api.next('Arx6UcDo0T0');
      expect(queue.selected?.title, 'Rainforest');

      expect(await api.lyrics('Arx6UcDo0T0'), isNull);

      api.close();
      store.dispose();
    });

    test('validasi videoId dan query kosong', () async {
      final store = await storeWith(proxyBase: 'https://host');
      final api = SonoraApi(store);
      await expectLater(api.next('pendek'), throwsArgumentError);
      await expectLater(api.player(''), throwsArgumentError);
      await expectLater(api.search('   '), throwsArgumentError);
      api.close();
      store.dispose();
    });

    test('error HTTP dipetakan aman', () async {
      final store = await storeWith(proxyBase: 'https://host');

      Future<SonoraApiException> capture(http.Response response) async {
        final api = SonoraApi(store, client: MockClient((_) async => response));
        try {
          await api.home();
        } finally {
          api.close();
        }
        throw StateError('seharusnya melempar SonoraApiException');
      }

      await expectLater(
        capture(
          _jsonResponse(
            '{"error":"login required (send x-yt-cookie header)"}',
            401,
          ),
        ),
        throwsA(
          isA<SonoraApiException>()
              .having((e) => e.isUnauthorized, 'isUnauthorized', isTrue)
              .having((e) => e.message, 'message', contains('login required')),
        ),
      );

      await expectLater(
        capture(_jsonResponse('{"error":"missing q"}', 400)),
        throwsA(
          isA<SonoraApiException>()
              .having((e) => e.statusCode, 'statusCode', 400)
              .having((e) => e.message, 'message', 'missing q'),
        ),
      );

      await expectLater(
        capture(_jsonResponse('<html>boom</html>', 500)),
        throwsA(
          isA<SonoraApiException>()
              .having((e) => e.statusCode, 'statusCode', 500)
              .having((e) => e.message, 'message', contains('500')),
        ),
      );

      await expectLater(
        capture(_jsonResponse('bukan json', 200)),
        throwsA(
          isA<SonoraApiException>().having(
            (e) => e.message,
            'message',
            contains('tidak dapat dibaca'),
          ),
        ),
      );

      await expectLater(
        capture(_jsonResponse('', 0)),
        throwsA(isA<SonoraApiException>()),
      );

      store.dispose();
    });

    test('kegagalan jaringan menjadi SonoraApiException', () async {
      final store = await storeWith(proxyBase: 'https://host');
      final api = SonoraApi(
        store,
        client: MockClient((_) async {
          throw http.ClientException('connection refused');
        }),
      );
      await expectLater(
        api.home(),
        throwsA(
          isA<SonoraApiException>().having(
            (e) => e.statusCode,
            'statusCode',
            isNull,
          ),
        ),
      );
      api.close();
      store.dispose();
    });

    test('close bersifat idempoten dan menolak request berikutnya', () async {
      final store = await storeWith(proxyBase: 'https://host');
      final api = SonoraApi(
        store,
        client: MockClient((_) async {
          return _jsonResponse('{}', 200);
        }),
      );
      api.close();
      api.close();
      await expectLater(api.home(), throwsA(isA<SonoraApiException>()));
      store.dispose();
    });
  });

  group('live proxy (opsional)', () {
    final base = Platform.environment['SONORA_PROXY_BASE']?.trim();
    final skip = base == null || base.isEmpty
        ? 'SONORA_PROXY_BASE tidak diisi'
        : null;

    test('healthz dan home dari proxy nyata', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = await SettingsStore.load();
      await store.setProxyBase(base!);
      final api = SonoraApi(store);

      final status = await api.healthz();
      expect(status.ok, isTrue);

      final home = await api.home();
      expect(home.sections, isNotEmpty);

      api.close();
      store.dispose();
    }, skip: skip);
  });
}
