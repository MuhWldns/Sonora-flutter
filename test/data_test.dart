/// Tes fokus boundary konsumen untuk lapisan data MVP.
///
/// Payload memakai bentuk respons proxy yang sebenarnya (bukan fixture besar),
/// dan semua request diuji lewat `MockClient` deterministik. Tidak ada endpoint
/// live yang di-hardcode.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sonora_flutter/data/music_models.dart';
import 'package:sonora_flutter/data/settings_store.dart';
import 'package:sonora_flutter/data/sonora_api.dart';

const String _feedJson = '''
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
     "thumbnail": "https://img.example/x.jpg",
     "artists": [
      {"name": "Backstreet Boys", "browseId": "UC1"}
     ],
     "album": {"name": "Black & Blue", "browseId": "MPREb_1"}
    }
   ]
  },
  {
   "title": "Playlists",
   "items": [
    {
     "type": "playlist",
     "title": "Indo 90an",
     "subtitle": "17M views",
     "playlistId": "PLw3xXmiGk7179fZ_q7f3YgmuD05U7ClHr",
     "browseId": "VLPLw3xXmiGk7179fZ_q7f3YgmuD05U7ClHr",
     "artists": [{"name": "Dadang", "browseId": "UC2"}]
    }
   ]
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
    }
   ]
  }
 ]
}
''';

Map<String, dynamic> _map(String json) =>
    (jsonDecode(json) as Map).cast<String, dynamic>();

http.Response _jsonResponse(String body, [int status = 200]) =>
    http.Response.bytes(
      utf8.encode(body),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

Future<SettingsStore> _store(String? base) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final store = await SettingsStore.load();
  if (base != null) await store.setProxyBase(base);
  return store;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MusicItem.fromJson', () {
    test('membaca field wajib dan opsional dari payload nyata', () {
      final section = _map(_feedJson)['sections'] as List;
      final song = MusicItem.fromJson(
        ((section.first as Map)['items'] as List).first as Map<String, dynamic>,
      );
      expect(song.type, 'song');
      expect(song.title, 'Shape of My Heart');
      expect(song.subtitle, 'Backstreet Boys • 729M plays • Black & Blue');
      expect(song.thumbnail, 'https://img.example/x.jpg');
      expect(song.videoId, 'BLhIcQMaaTI');
      expect(song.artist, 'Backstreet Boys');
      expect(song.isPlayable, isTrue);
      expect(song.browseTarget, isNull); // tanpa browseId/playlistId
    });

    test('artist digabung dengan koma, fallback subtitle, lalu kosong', () {
      expect(
        MusicItem.fromJson({
          'type': 'song',
          'title': 'X',
          'artists': [
            {'name': 'A'},
            {'name': 'B'},
          ],
        }).artist,
        'A, B',
      );
      expect(
        MusicItem.fromJson({
          'type': 'song',
          'title': 'X',
          'subtitle': 'Fallback',
        }).artist,
        'Fallback',
      );
      expect(MusicItem.fromJson({'type': 'song', 'title': 'X'}).artist, '');
    });

    test('browseTarget memprioritaskan browseId', () {
      final item = MusicItem.fromJson({
        'type': 'playlist',
        'title': 'P',
        'browseId': 'VLAAA',
        'playlistId': 'PLBBB',
      });
      expect(item.browseTarget, 'VLAAA');
    });

    test('playlistId dinormalkan ke prefix VL', () {
      expect(
        MusicItem.fromJson({
          'type': 'playlist',
          'title': 'P',
          'playlistId': 'PLBBB',
        }).browseTarget,
        'VLPLBBB',
      );
      expect(
        MusicItem.fromJson({
          'type': 'playlist',
          'title': 'P',
          'playlistId': 'VLPLBBB',
        }).browseTarget,
        'VLPLBBB',
      );
    });

    test('isPlayable false tanpa videoId atau videoId kosong', () {
      expect(MusicItem.fromJson({'type': 'album', 'title': 'A'}).isPlayable,
          isFalse);
      expect(
        MusicItem.fromJson({'type': 'song', 'title': 'S', 'videoId': ''})
            .isPlayable,
        isFalse,
      );
    });

    test('nilai salah tipe tidak melempar', () {
      final item = MusicItem.fromJson({
        'type': 123,
        'title': 456,
        'subtitle': true,
        'thumbnail': 789,
        'videoId': 111,
        'artists': 'bukan list',
      });
      expect(item.type, '123');
      expect(item.title, '456');
      expect(item.subtitle, 'true');
      expect(item.thumbnail, '789');
      expect(item.videoId, '111');
      expect(item.artist, '');
    });
  });

  group('MusicSection.fromJson', () {
    test('membaca judul dan daftar item', () {
      final sections = _map(_feedJson)['sections'] as List;
      final first = MusicSection.fromJson(sections.first as Map<String, dynamic>);
      expect(first.title, 'Quick picks');
      expect(first.items, hasLength(1));
      expect(first.items.single.title, 'Shape of My Heart');
    });

    test('items hilang menjadi daftar kosong', () {
      final section = MusicSection.fromJson({'title': 'X'});
      expect(section.items, isEmpty);
    });
  });

  group('SettingsStore', () {
    test('normalisasi mempertahankan prefix path, menghapus slash ujung', () {
      expect(
        SettingsStore.normalizeProxyBase('https://host:8787/'),
        'https://host:8787',
      );
      expect(
        SettingsStore.normalizeProxyBase('https://host/api/v1///'),
        'https://host/api/v1',
      );
    });

    test('kosong menjadi null; URL tidak valid ditolak', () {
      expect(SettingsStore.normalizeProxyBase(''), isNull);
      expect(() => SettingsStore.normalizeProxyBase('bukan url'),
          throwsArgumentError);
      expect(() => SettingsStore.normalizeProxyBase('ftp://host'),
          throwsArgumentError);
      expect(() => SettingsStore.normalizeProxyBase('https://u:p@host'),
          throwsArgumentError);
      expect(() => SettingsStore.normalizeProxyBase('https://host?x=1'),
          throwsArgumentError);
      expect(() => SettingsStore.normalizeProxyBase('https://host#frag'),
          throwsArgumentError);
    });

    test('load default kosong lalu set/clear bertahan', () async {
      final store = await _store(null);
      expect(store.proxyBase, '');
      expect(store.isConfigured, isFalse);

      var notified = 0;
      store.addListener(() => notified++);

      await store.setProxyBase('https://host:8787/api/');
      expect(store.proxyBase, 'https://host:8787/api');
      expect(store.isConfigured, isTrue);

      final reloaded = await SettingsStore.load();
      expect(reloaded.proxyBase, 'https://host:8787/api');

      await store.setProxyBase('   ');
      expect(store.proxyBase, '');
      expect(store.isConfigured, isFalse);
      expect(notified, 2);

      store.dispose();
      reloaded.dispose();
    });

    test('nilai korup di penyimpanan menjadi default', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'sonora.proxyBase': 'bukan-url',
      });
      final store = await SettingsStore.load();
      expect(store.proxyBase, '');
      store.dispose();
    });
  });

  group('SonoraApi', () {
    test('home/search/browse mengembalikan List<MusicSection>', () async {
      final store = await _store('https://host');
      final api = SonoraApi(
        store,
        client: MockClient((request) async {
          switch (request.url.path) {
            case '/home':
              return _jsonResponse(_feedJson);
            case '/search':
              expect(request.url.queryParameters['q'], 'lofi');
              expect(request.url.queryParameters['filter'], 'song');
              return _jsonResponse(_feedJson);
            case '/browse':
              expect(request.url.queryParameters['id'], 'MPREb_1');
              return _jsonResponse(_browseJson);
            default:
              return _jsonResponse('{}', 404);
          }
        }),
      );

      final home = await api.home();
      expect(home, hasLength(2));
      expect(home.first.items.single.artist, 'Backstreet Boys');

      final search = await api.search('lofi', filter: 'song');
      expect(search.first.title, 'Quick picks');

      final browse = await api.browse('MPREb_1');
      expect(browse.single.items.single.thumbnail, isNull);
      expect(browse.single.items.single.isPlayable, isTrue);

      api.close();
      store.dispose();
    });

    test('mempertahankan prefix base path', () async {
      final store = await _store('https://host:8787/api');
      final api = SonoraApi(
        store,
        client: MockClient((request) async {
          expect(request.url.path, '/api/home');
          return _jsonResponse(_feedJson);
        }),
      );
      await api.home();
      api.close();
      store.dispose();
    });

    test('base URL ditangkap saat request dimulai', () async {
      final store = await _store('https://one');
      final gate = Completer<void>();
      late Uri requested;
      final api = SonoraApi(
        store,
        client: MockClient((request) async {
          requested = request.url;
          await gate.future;
          return _jsonResponse(_feedJson);
        }),
      );

      final pending = api.home(); // menangkap base 'https://one' secara sinkron
      await store.setProxyBase('https://two');
      gate.complete();
      await pending;

      expect(requested.host, 'one');
      api.close();
      store.dispose();
    });

    test('sections hilang/tak dikenal menjadi daftar kosong', () async {
      final store = await _store('https://host');
      final api = SonoraApi(
        store,
        client: MockClient((_) async => _jsonResponse('{"sections":"x"}')),
      );
      expect(await api.home(), isEmpty);
      api.close();
      store.dispose();
    });

    test('proxy belum dikonfigurasi melempar konfigurasi', () async {
      final store = await _store(null);
      final api = SonoraApi(store);
      expect(api.isConfigured, isFalse);
      await expectLater(api.home(), throwsA(isA<SonoraConfigurationException>()));
      api.close();
      store.dispose();
    });

    test('validasi query dan id kosong', () async {
      final store = await _store('https://host');
      final api = SonoraApi(store);
      await expectLater(api.search('   '), throwsArgumentError);
      await expectLater(api.browse(''), throwsArgumentError);
      expect(() => api.streamUri(''), throwsArgumentError);
      api.close();
      store.dispose();
    });

    test('streamUri memakai relay /stream dan prefix path', () async {
      final store = await _store('https://host/api/');
      final api = SonoraApi(store);
      final uri = api.streamUri('Arx6UcDo0T0');
      expect(uri.path, '/api/stream');
      expect(uri.queryParameters['videoId'], 'Arx6UcDo0T0');
      api.close();
      store.dispose();
    });

    test('error HTTP dipetakan aman', () async {
      final store = await _store('https://host');

      Future<void> capture(http.Response response) async {
        final api = SonoraApi(store, client: MockClient((_) async => response));
        try {
          await api.home();
        } finally {
          api.close();
        }
      }

      await expectLater(
        capture(_jsonResponse('{"error":"missing q"}', 400)),
        throwsA(isA<SonoraApiException>()
            .having((e) => e.statusCode, 'statusCode', 400)
            .having((e) => e.message, 'message', 'missing q')),
      );
      await expectLater(
        capture(_jsonResponse('<html>boom</html>', 502)),
        throwsA(isA<SonoraApiException>()
            .having((e) => e.statusCode, 'statusCode', 502)),
      );
      await expectLater(
        capture(_jsonResponse('bukan json')),
        throwsA(isA<SonoraApiException>()),
      );

      store.dispose();
    });

    test('kegagalan jaringan menjadi SonoraApiException', () async {
      final store = await _store('https://host');
      final api = SonoraApi(
        store,
        client: MockClient((_) async {
          throw http.ClientException('connection refused');
        }),
      );
      await expectLater(
        api.home(),
        throwsA(isA<SonoraApiException>()
            .having((e) => e.statusCode, 'statusCode', isNull)),
      );
      api.close();
      store.dispose();
    });

    test('checkConnection sukses dan gagal', () async {
      final store = await _store(null);
      final okApi = SonoraApi(
        store,
        client: MockClient((request) async {
          expect(request.url.path, '/healthz');
          return _jsonResponse('{"ok":true}');
        }),
      );
      await okApi.checkConnection('https://host:8787/');
      okApi.close();

      final badApi = SonoraApi(
        store,
        client: MockClient((_) async => _jsonResponse('{"error":"down"}', 502)),
      );
      await expectLater(
        badApi.checkConnection('https://host'),
        throwsA(isA<SonoraApiException>()
            .having((e) => e.statusCode, 'statusCode', 502)),
      );
      badApi.close();

      await expectLater(
        okApi.checkConnection('bukan url'),
        throwsArgumentError,
      );
      store.dispose();
    });

    test('close idempoten dan menolak request berikutnya', () async {
      final store = await _store('https://host');
      final api = SonoraApi(
        store,
        client: MockClient((_) async => _jsonResponse(_feedJson)),
      );
      api.close();
      api.close();
      await expectLater(api.home(), throwsA(isA<SonoraApiException>()));
      store.dispose();
    });
  });
}
