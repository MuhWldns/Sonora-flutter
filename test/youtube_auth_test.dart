library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sonora_flutter/data/music_models.dart';
import 'package:sonora_flutter/data/youtube_auth_service.dart';
import 'package:sonora_flutter/data/youtube_music_service.dart';
import 'package:sonora_flutter/data/youtube_session.dart';

const String _validCookie =
    'VISITOR_INFO1_LIVE=abc; SAPISID=sapisid123; __Secure-1PAPISID=alt123';

/// Respons browse innertube minimal dengan dua bentuk renderer sekaligus.
const String _browseJson = '''
{
  "contents": [
    {
      "musicTwoRowItemRenderer": {
        "navigationEndpoint": {"watchEndpoint": {"videoId": "vidTwo"}},
        "title": {"runs": [{"text": "Lagu Grid"}]},
        "subtitle": {"runs": [{"text": "Artis Grid"}]},
        "thumbnailRenderer": {
          "musicThumbnailRenderer": {
            "thumbnail": {
              "thumbnails": [{"url": "https://i.ytimg.com/vi/vidTwo/hq.jpg"}]
            }
          }
        }
      }
    },
    {
      "musicResponsiveListItemRenderer": {
        "playlistItemData": {"videoId": "vidList"},
        "flexColumns": [
          {
            "musicResponsiveListItemFlexColumnRenderer": {
              "text": {"runs": [{"text": "Lagu Daftar"}]}
            }
          },
          {
            "musicResponsiveListItemFlexColumnRenderer": {
              "text": {"runs": [{"text": "Artis Daftar"}]}
            }
          }
        ],
        "fixedColumns": [
          {
            "musicResponsiveListItemFixedColumnRenderer": {
              "text": {"runs": [{"text": "3:21"}]}
            }
          }
        ],
        "thumbnail": {
          "musicThumbnailRenderer": {
            "thumbnail": {
              "thumbnails": [{"url": "//i.ytimg.com/vi/vidList/hq.jpg"}]
            }
          }
        }
      }
    }
  ]
}
''';

/// Respons account_menu innertube minimal.
const String _accountMenuJson = '''
{
  "actions": [
    {
      "accountMenuRenderer": {
        "multiPageMenuRenderer": {
          "sections": [
            {
              "accountSectionRenderer": {
                "contents": [
                  {
                    "accountItemRenderer": {
                      "accountName": {"simpleText": "Budi"},
                      "email": {"simpleText": "budi@example.com"}
                    }
                  }
                ]
              }
            }
          ]
        }
      }
    }
  ]
}
''';

YoutubeSession _session({String? pageId}) => YoutubeSession(
      cookie: _validCookie,
      pageId: pageId,
      dataSyncId: 'data-sync-1',
      authUser: '0',
      visitorData: 'visitor-1',
      clientVersion: '1.20250101.01.00',
    );

http.Response _jsonResponse(String body, [int status = 200]) =>
    http.Response.bytes(
      utf8.encode(body),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  group('sapisidHash', () {
    test('mengikuti rumus sha1("{timestamp} {sapisid} {origin}")', () {
      // Jam tiruan tetap agar hasil hash bisa dihitung ulang di tes.
      const int fakeClockSeconds = 1700000000;
      const String sapisid = 'sapisid123';
      const String origin = 'https://music.youtube.com';
      final String expected = sha1
          .convert(utf8.encode('$fakeClockSeconds $sapisid $origin'))
          .toString();
      expect(
        sapisidHash(sapisid, origin, fakeClockSeconds),
        expected,
      );
    });
  });

  group('YoutubeSession.sapisidFromCookie', () {
    test('memilih SAPISID lebih dulu, lalu __Secure-3PAPISID', () {
      expect(
        YoutubeSession.sapisidFromCookie(
            '__Secure-3PAPISID=tiga; SAPISID=satu; __Secure-1PAPISID=satu1'),
        'satu',
      );
      expect(
        YoutubeSession.sapisidFromCookie(
            '__Secure-1PAPISID=satu1; __Secure-3PAPISID=tiga'),
        'tiga',
      );
    });

    test('mengembalikan null bila tidak ada keluarga SAPISID', () {
      expect(
        YoutubeSession.sapisidFromCookie('PREF=hl=en; VISITOR_INFO1_LIVE=x'),
        isNull,
      );
      expect(YoutubeSession.sapisidFromCookie('SAPISID='), isNull);
    });
  });

  group('YoutubeAuthService.capture', () {
    test('menolak cookie tanpa keluarga SAPISID tanpa notifikasi', () async {
      final InMemorySessionStore store = InMemorySessionStore();
      final YoutubeAuthService auth = YoutubeAuthService(store: store);
      int notified = 0;
      auth.addListener(() => notified++);

      final bool ok = await auth.capture(
        cookie: 'PREF=hl=en; VISITOR_INFO1_LIVE=abc',
        dataSyncId: 'ds',
        authUser: '0',
        visitorData: 'v',
        clientVersion: '1.0.0',
      );

      expect(ok, isFalse);
      expect(auth.signedIn, isFalse);
      expect(notified, 0);
      expect(await store.read(), isNull);
    });

    test('menolak saat validator menolak dan tidak menyimpan', () async {
      final InMemorySessionStore store = InMemorySessionStore();
      final YoutubeAuthService auth = YoutubeAuthService(
        store: store,
        validate: (YoutubeSession session) async => false,
      );
      int notified = 0;
      auth.addListener(() => notified++);

      final bool ok = await auth.capture(
        cookie: _validCookie,
        dataSyncId: 'ds',
        authUser: '0',
        visitorData: 'v',
        clientVersion: '1.0.0',
      );

      expect(ok, isFalse);
      expect(auth.signedIn, isFalse);
      expect(notified, 0);
      expect(await store.read(), isNull);
    });

    test('menerima cookie valid, menyimpan sesi, dan memberi tahu', () async {
      final InMemorySessionStore store = InMemorySessionStore();
      int validateCalls = 0;
      final YoutubeAuthService auth = YoutubeAuthService(
        store: store,
        validate: (YoutubeSession session) async {
          validateCalls++;
          expect(session.cookie, _validCookie);
          return true;
        },
        fetchAccountName: (YoutubeSession session) async => 'Akun Uji',
      );
      int notified = 0;
      auth.addListener(() => notified++);

      final bool ok = await auth.capture(
        cookie: _validCookie,
        pageId: 'page-1',
        dataSyncId: 'ds-1',
        authUser: '0',
        visitorData: 'v-1',
        clientVersion: '1.20250101.01.00',
      );

      expect(ok, isTrue);
      expect(validateCalls, 1);
      expect(notified, 1);
      expect(auth.signedIn, isTrue);
      expect(auth.accountName, 'Akun Uji');
      expect(auth.session?.dataSyncId, 'ds-1');
      expect(auth.session?.pageId, 'page-1');

      final String? stored = await store.read();
      expect(stored, isNotNull);
      final Object? decoded = jsonDecode(stored!);
      expect(decoded, isA<Map<dynamic, dynamic>>());
      final Map<dynamic, dynamic> map = decoded! as Map<dynamic, dynamic>;
      expect(map['dataSyncId'], 'ds-1');
      expect(map['cookie'], _validCookie);
      expect(map['clientVersion'], '1.20250101.01.00');
    });

    test('signOut menghapus penyimpanan dan state', () async {
      final InMemorySessionStore store = InMemorySessionStore();
      final YoutubeAuthService auth = YoutubeAuthService(store: store);
      await auth.capture(
        cookie: _validCookie,
        dataSyncId: 'ds',
        authUser: '0',
        visitorData: 'v',
        clientVersion: '1.0.0',
      );
      expect(auth.signedIn, isTrue);

      int notified = 0;
      auth.addListener(() => notified++);
      await auth.signOut();

      expect(notified, 1);
      expect(auth.signedIn, isFalse);
      expect(auth.session, isNull);
      expect(auth.accountName, isNull);
      expect(await store.read(), isNull);
    });

    test('restore memulihkan sesi valid dari penyimpanan', () async {
      final InMemorySessionStore store = InMemorySessionStore();
      await store.write(jsonEncode(_session().toJson()));
      final YoutubeAuthService auth = YoutubeAuthService(store: store);

      await auth.restore();

      expect(auth.signedIn, isTrue);
      expect(auth.session?.dataSyncId, 'data-sync-1');
      expect(auth.session?.clientVersion, '1.20250101.01.00');
    });

    test('restore membuang sesi rusak atau tanpa SAPISID', () async {
      final InMemorySessionStore store = InMemorySessionStore();
      await store.write('{json rusak');
      final YoutubeAuthService auth = YoutubeAuthService(store: store);
      await auth.restore();
      expect(auth.signedIn, isFalse);
      expect(await store.read(), isNull);

      await store.write(jsonEncode(<String, dynamic>{
        'cookie': 'PREF=hl=en',
        'dataSyncId': 'ds',
        'authUser': '0',
        'visitorData': 'v',
        'clientVersion': '1.0.0',
      }));
      final YoutubeAuthService auth2 = YoutubeAuthService(store: store);
      await auth2.restore();
      expect(auth2.signedIn, isFalse);
      expect(await store.read(), isNull);
    });
  });

  group('YouTubeMusicService header sesi', () {
    test('melampirkan Cookie/Authorization/X-Goog saat sesi ada', () async {
      http.Request? captured;
      final YouTubeMusicService service = YouTubeMusicService(
        httpClient: MockClient((http.Request request) async {
          captured = request;
          return _jsonResponse(_browseJson);
        }),
      );
      final YoutubeSession session = _session();
      service.sessionProvider = () async => session;

      final List<MusicItem> items = await service.fetchLiked();

      expect(captured, isNotNull);
      final http.Request request = captured!;
      expect(request.url.host, 'music.youtube.com');
      expect(request.url.path, '/youtubei/v1/browse');
      expect(request.url.queryParameters['prettyPrint'], 'false');
      expect(request.url.queryParameters['hl'], 'en');

      expect(request.headers['cookie'], session.cookie);
      final String authorization = request.headers['authorization']!;
      final RegExpMatch match = RegExp(r'^SAPISIDHASH (\d+)_([0-9a-f]{40})$')
          .firstMatch(authorization)!;
      final int timestamp = int.parse(match.group(1)!);
      expect(
        authorization,
        'SAPISIDHASH ${timestamp}_'
        '${sapisidHash('sapisid123', youtubeMusicOrigin, timestamp)}',
      );
      expect(request.headers['x-youtube-client-name'], '67');
      expect(request.headers['x-youtube-client-version'],
          session.clientVersion);
      expect(request.headers['x-goog-visitor-id'], session.visitorData);
      expect(request.headers['x-goog-authuser'], session.authUser);
      expect(request.headers.containsKey('x-goog-pageid'), isFalse);
      expect(request.headers['x-origin'], youtubeMusicOrigin);
      expect(request.headers['origin'], youtubeMusicOrigin);
      expect(request.headers['referer'], '$youtubeMusicOrigin/');

      final Map<String, dynamic> body =
          jsonDecode(request.body) as Map<String, dynamic>;
      final Map<String, dynamic> client =
          (body['context'] as Map<String, dynamic>)['client']
              as Map<String, dynamic>;
      expect(client['clientName'], 'WEB_REMIX');
      expect(client['clientVersion'], session.clientVersion);
      final Map<String, dynamic> user =
          (body['context'] as Map<String, dynamic>)['user']
              as Map<String, dynamic>;
      expect(user['onBehalfOfUser'], 'data-sync-1');
      expect(body['browseId'], 'FEmusic_liked_videos');

      // Hasil parsing tetap dikembalikan meski fokus tes ada di header.
      expect(items, hasLength(2));
      expect(items[0].title, 'Lagu Grid');
      expect(items[0].videoId, 'vidTwo');
      expect(items[0].artist, 'Artis Grid');
      expect(items[0].duration, isNull);
      expect(items[1].title, 'Lagu Daftar');
      expect(items[1].videoId, 'vidList');
      expect(items[1].duration, '3:21');
      expect(items[1].thumbnail, 'https://i.ytimg.com/vi/vidList/hq.jpg');
      service.dispose();
    });

    test('melampirkan X-Goog-PageId bila pageId ada', () async {
      http.Request? captured;
      final YouTubeMusicService service = YouTubeMusicService(
        httpClient: MockClient((http.Request request) async {
          captured = request;
          return _jsonResponse(_browseJson);
        }),
      );
      service.sessionProvider = () async => _session(pageId: 'page-9');

      await service.fetchHistory();

      expect(captured!.headers['x-goog-pageid'], 'page-9');
      expect(captured!.url.path, '/youtubei/v1/browse');
      service.dispose();
    });

    test('tidak melampirkan Authorization/Cookie saat sesi tidak ada',
        () async {
      http.Request? captured;
      final YouTubeMusicService service = YouTubeMusicService(
        httpClient: MockClient((http.Request request) async {
          captured = request;
          return _jsonResponse(_browseJson);
        }),
      );
      // Tidak menyetel sessionProvider — setara pengguna anonim.

      final List<MusicItem> items = await service.fetchLiked();

      expect(captured, isNotNull);
      expect(captured!.headers.containsKey('authorization'), isFalse);
      expect(captured!.headers.containsKey('cookie'), isFalse);
      expect(captured!.headers.containsKey('x-goog-visitor-id'), isFalse);
      expect(captured!.headers['x-youtube-client-name'], '67');
      final Map<String, dynamic> body =
          jsonDecode(captured!.body) as Map<String, dynamic>;
      expect(
        (body['context'] as Map<String, dynamic>).containsKey('user'),
        isFalse,
      );
      expect(items, hasLength(2));
      service.dispose();
    });

    test('fetchAccountName mengambil nama akun dan null saat gagal', () async {
      http.Request? captured;
      final YouTubeMusicService service = YouTubeMusicService(
        httpClient: MockClient((http.Request request) async {
          captured = request;
          return _jsonResponse(_accountMenuJson);
        }),
      );
      service.sessionProvider = () async => _session();

      expect(await service.fetchAccountName(), 'Budi');
      expect(captured!.url.path, '/youtubei/v1/account/account_menu');
      service.dispose();

      // Respons tidak valid → null, bukan exception.
      final YouTubeMusicService failing = YouTubeMusicService(
        httpClient: MockClient((http.Request request) async =>
            _jsonResponse('{"error": "server"}', 500)),
      );
      expect(await failing.fetchAccountName(), isNull);
      failing.dispose();
    });

    test('likeVideo dan createPlaylist memakai endpoint serta body benar',
        () async {
      final List<http.Request> requests = <http.Request>[];
      final YouTubeMusicService service = YouTubeMusicService(
        httpClient: MockClient((http.Request request) async {
          requests.add(request);
          return _jsonResponse('{}');
        }),
      );

      expect(await service.likeVideo('abc123'), isTrue);
      expect(await service.createPlaylist('Playlistku'), isTrue);

      final Map<String, dynamic> likeBody =
          jsonDecode(requests[0].body) as Map<String, dynamic>;
      expect(requests[0].url.path, '/youtubei/v1/like/like');
      expect((likeBody['target'] as Map<String, dynamic>)['videoId'],
          'abc123');
      expect(likeBody['action'], 'like/like');

      final Map<String, dynamic> createBody =
          jsonDecode(requests[1].body) as Map<String, dynamic>;
      expect(requests[1].url.path, '/youtubei/v1/playlist/create');
      expect(createBody['title'], 'Playlistku');
      expect(createBody['privacyStatus'], 'PRIVATE');
      service.dispose();
    });
  });

  group('YouTubeMusicService.validateSession', () {
    test('true saat HTTP 200 meski isi respons tidak memuat nama akun',
        () async {
      final YouTubeMusicService service = YouTubeMusicService(
        httpClient: MockClient((http.Request request) async =>
            _jsonResponse('{"struktur": "berubah"}')),
      );
      service.sessionProvider = () async => _session();

      // Validasi berbasis status: isi respons tidak perlu diparse.
      expect(await service.validateSession(), isTrue);
      // Nama akun tetap best-effort: null bila tidak ditemukan.
      expect(await service.fetchAccountName(), isNull);
      service.dispose();
    });

    test('false saat HTTP 401 atau 403', () async {
      final YouTubeMusicService unauthorized = YouTubeMusicService(
        httpClient: MockClient((http.Request request) async =>
            _jsonResponse('{"error": "unauthorized"}', 401)),
      );
      unauthorized.sessionProvider = () async => _session();
      expect(await unauthorized.validateSession(), isFalse);
      unauthorized.dispose();

      final YouTubeMusicService forbidden = YouTubeMusicService(
        httpClient: MockClient((http.Request request) async =>
            _jsonResponse('{"error": "forbidden"}', 403)),
      );
      forbidden.sessionProvider = () async => _session();
      expect(await forbidden.validateSession(), isFalse);
      forbidden.dispose();
    });

    test('false saat request gagal (kesalahan jaringan)', () async {
      final YouTubeMusicService service = YouTubeMusicService(
        httpClient: MockClient((http.Request request) async =>
            throw Exception('jaringan putus')),
      );
      service.sessionProvider = () async => _session();
      expect(await service.validateSession(), isFalse);
      service.dispose();
    });

    test('authUser kosong memakai default 0; dataSyncId kosong tanpa '
        'context.user', () async {
      final List<http.Request> requests = <http.Request>[];
      final YouTubeMusicService service = YouTubeMusicService(
        httpClient: MockClient((http.Request request) async {
          requests.add(request);
          return _jsonResponse(_accountMenuJson);
        }),
      );
      service.sessionProvider = () async => YoutubeSession(
            cookie: _validCookie,
            dataSyncId: '',
            authUser: '',
            visitorData: 'visitor-1',
            clientVersion: '1.20250101.01.00',
          );

      expect(await service.validateSession(), isTrue);

      expect(requests, hasLength(1));
      expect(requests[0].url.path, '/youtubei/v1/account/account_menu');
      expect(requests[0].headers['x-goog-authuser'], '0');
      expect(requests[0].headers.containsKey('x-goog-visitor-id'), isTrue);
      final Map<String, dynamic> body =
          jsonDecode(requests[0].body) as Map<String, dynamic>;
      expect(
        (body['context'] as Map<String, dynamic>).containsKey('user'),
        isFalse,
      );
      service.dispose();
    });

    test('sesi dengan nilai probe kosong tetap divalidasi memakai cookie, '
        'SAPISIDHASH, dan x-goog-authuser 0', () async {
      http.Request? captured;
      final YouTubeMusicService service = YouTubeMusicService(
        httpClient: MockClient((http.Request request) async {
          captured = request;
          return _jsonResponse('{}');
        }),
      );
      // Sesi hasil probe ytcfg yang gagal dibaca: hanya cookie yang pasti ada.
      service.sessionProvider = () async => YoutubeSession(
            cookie: _validCookie,
            dataSyncId: '',
            authUser: '',
            visitorData: '',
            clientVersion: '',
          );

      expect(await service.validateSession(), isTrue);

      final http.Request request = captured!;
      expect(request.url.path, '/youtubei/v1/account/account_menu');
      expect(request.headers['cookie'], _validCookie);
      expect(request.headers['x-goog-authuser'], '0');
      final String authorization = request.headers['authorization']!;
      final RegExpMatch match =
          RegExp(r'^SAPISIDHASH (\d+)_([0-9a-f]{40})$')
              .firstMatch(authorization)!;
      final int timestamp = int.parse(match.group(1)!);
      expect(
        authorization,
        'SAPISIDHASH ${timestamp}_'
        '${sapisidHash('sapisid123', youtubeMusicOrigin, timestamp)}',
      );
      service.dispose();
    });

    test('sesi dengan nilai probe kosong tetap ditolak saat HTTP 401',
        () async {
      final YouTubeMusicService service = YouTubeMusicService(
        httpClient: MockClient((http.Request request) async =>
            _jsonResponse('{"error": "unauthorized"}', 401)),
      );
      service.sessionProvider = () async => YoutubeSession(
            cookie: _validCookie,
            dataSyncId: '',
            authUser: '',
            visitorData: '',
            clientVersion: '',
          );

      expect(await service.validateSession(), isFalse);
      service.dispose();
    });
  });
}
