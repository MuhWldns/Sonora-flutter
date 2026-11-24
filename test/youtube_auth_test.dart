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

/// Respons account_menu lengkap: nama, email (runs), dan avatar bertingkat
/// untuk menguji pemilihan thumbnail terbesar.
const String _accountMenuFullJson = '''
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
                      "accountName": {"simpleText": "Siti"},
                      "email": {"runs": [{"text": "siti@example.com"}]},
                      "accountPhoto": {
                        "thumbnails": [
                          {
                            "url": "https://lh3.googleusercontent.com/a/s32",
                            "width": 32,
                            "height": 32
                          },
                          {
                            "url": "https://lh3.googleusercontent.com/a/s256",
                            "width": 256,
                            "height": 256
                          }
                        ]
                      }
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

/// Respons account_menu tanpa email dan avatar — keduanya harus null.
const String _accountMenuSparseJson = '''
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
                      "accountName": {"simpleText": "Budi"}
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

/// Respons browse FEmusic_home: rak carousel berjudul, rak tanpa judul
/// (kartu riwayat MPED), rak biasa (baris responsif), dan rak kosong.
const String _homeJson = '''
{
  "contents": {
    "singleColumnBrowseResultsRenderer": {
      "tabs": [
        {
          "tabRenderer": {
            "content": {
              "sectionListRenderer": {
                "contents": [
                  {
                    "musicCarouselShelfRenderer": {
                      "header": {
                        "musicCarouselShelfBasicHeaderRenderer": {
                          "title": {"runs": [{"text": "Quick picks"}]}
                        }
                      },
                      "contents": [
                        {
                          "musicTwoRowItemRenderer": {
                            "navigationEndpoint": {
                              "watchEndpoint": {"videoId": "homeVid"}
                            },
                            "title": {"runs": [{"text": "Lagu Utama"}]},
                            "subtitle": {"runs": [{"text": "Artis Utama"}]},
                            "thumbnailRenderer": {
                              "musicThumbnailRenderer": {
                                "thumbnail": {
                                  "thumbnails": [
                                    {
                                      "url": "https://i.ytimg.com/vi/homeVid/hq.jpg",
                                      "width": 480,
                                      "height": 480
                                    }
                                  ]
                                }
                              }
                            }
                          }
                        },
                        {
                          "musicTwoRowItemRenderer": {
                            "navigationEndpoint": {
                              "browseEndpoint": {"browseId": "VLpl123"}
                            },
                            "title": {"runs": [{"text": "Playlist Andalan"}]},
                            "subtitle": {"runs": [{"text": "Sonora"}]},
                            "thumbnailRenderer": {
                              "musicThumbnailRenderer": {
                                "thumbnail": {
                                  "thumbnails": [
                                    {
                                      "url": "https://i.ytimg.com/pl.jpg",
                                      "width": 480,
                                      "height": 480
                                    }
                                  ]
                                }
                              }
                            }
                          }
                        }
                      ]
                    }
                  },
                  {
                    "musicCarouselShelfRenderer": {
                      "header": {"musicCarouselShelfBasicHeaderRenderer": {}},
                      "contents": [
                        {
                          "musicTwoRowItemRenderer": {
                            "navigationEndpoint": {
                              "browseEndpoint": {"browseId": "MPEDhistVid1"}
                            },
                            "title": {"runs": [{"text": "Lagu Riwayat"}]},
                            "subtitle": {"runs": [{"text": "Artis Riwayat"}]},
                            "thumbnailRenderer": {
                              "musicThumbnailRenderer": {
                                "thumbnail": {
                                  "thumbnails": [
                                    {
                                      "url": "https://i.ytimg.com/vi/histVid1/hq.jpg",
                                      "width": 480,
                                      "height": 480
                                    }
                                  ]
                                }
                              }
                            }
                          }
                        }
                      ]
                    }
                  },
                  {
                    "musicShelfRenderer": {
                      "title": {"runs": [{"text": "Listen again"}]},
                      "contents": [
                        {
                          "musicResponsiveListItemRenderer": {
                            "playlistItemData": {"videoId": "homeRow"},
                            "flexColumns": [
                              {
                                "musicResponsiveListItemFlexColumnRenderer": {
                                  "text": {"runs": [{"text": "Lagu Rak"}]}
                                }
                              },
                              {
                                "musicResponsiveListItemFlexColumnRenderer": {
                                  "text": {"runs": [{"text": "Artis Rak"}]}
                                }
                              }
                            ],
                            "fixedColumns": [
                              {
                                "musicResponsiveListItemFixedColumnRenderer": {
                                  "text": {"runs": [{"text": "4:05"}]}
                                }
                              }
                            ],
                            "thumbnail": {
                              "musicThumbnailRenderer": {
                                "thumbnail": {
                                  "thumbnails": [
                                    {"url": "//i.ytimg.com/vi/homeRow/hq.jpg"}
                                  ]
                                }
                              }
                            }
                          }
                        }
                      ]
                    }
                  },
                  {
                    "musicShelfRenderer": {
                      "title": {"runs": [{"text": "Rak kosong"}]},
                      "contents": []
                    }
                  }
                ]
              }
            }
          }
        }
      ]
    }
  }
}
''';

/// Respons search music.youtube.com: baris musicResponsiveListItemRenderer.
const String _musicSearchJson = '''
{
  "contents": {
    "sectionListRenderer": {
      "contents": [
        {
          "musicShelfRenderer": {
            "contents": [
              {
                "musicResponsiveListItemRenderer": {
                  "playlistItemData": {"videoId": "searchVid"},
                  "flexColumns": [
                    {
                      "musicResponsiveListItemFlexColumnRenderer": {
                        "text": {"runs": [{"text": "Lagu Cari"}]}
                      }
                    },
                    {
                      "musicResponsiveListItemFlexColumnRenderer": {
                        "text": {"runs": [{"text": "Artis Cari"}]}
                      }
                    }
                  ]
                }
              }
            ]
          }
        }
      ]
    }
  }
}
''';

/// Respons search www.youtube.com anonim: videoRenderer.
const String _anonymousSearchJson = '''
{
  "contents": {
    "twoColumnSearchResultsRenderer": {
      "primaryContents": {
        "sectionListRenderer": {
          "contents": [
            {
              "itemSectionRenderer": {
                "contents": [
                  {
                    "videoRenderer": {
                      "videoId": "anonVid",
                      "title": {"runs": [{"text": "Lagu Anonim"}]},
                      "ownerText": {"runs": [{"text": "Artis Anonim"}]},
                      "lengthText": {"simpleText": "3:10"},
                      "thumbnail": {
                        "thumbnails": [
                          {"url": "https://i.ytimg.com/vi/anonVid/hq.jpg"}
                        ]
                      }
                    }
                  }
                ]
              }
            }
          ]
        }
      }
    }
  }
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

    test('onBehalfOfUser hanya memakai bagian sebelum || dari dataSyncId',
        () async {
      http.Request? captured;
      final YouTubeMusicService service = YouTubeMusicService(
        httpClient: MockClient((http.Request request) async {
          captured = request;
          return _jsonResponse('{}');
        }),
      );
      // DATASYNC_ID ytcfg berformat "<id>||<timestamp>"; nilai lengkap
      // membuat account_menu menjawab HTTP 500.
      service.sessionProvider = () async => YoutubeSession(
            cookie: _validCookie,
            dataSyncId: 'ds-abc%3D%3D||1732500000',
            authUser: '0',
            visitorData: 'visitor-1',
            clientVersion: '1.20250101.01.00',
          );

      await service.validateSession();

      final Map<String, dynamic> body =
          jsonDecode(captured!.body) as Map<String, dynamic>;
      final Map<String, dynamic> user =
          (body['context'] as Map<String, dynamic>)['user']
              as Map<String, dynamic>;
      expect(user['onBehalfOfUser'], 'ds-abc%3D%3D');
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
  group('YouTubeMusicService.fetchAccountInfo', () {
    test('mengambil nama, email, dan avatar terbesar dari account_menu',
        () async {
      http.Request? captured;
      final YouTubeMusicService service = YouTubeMusicService(
        httpClient: MockClient((http.Request request) async {
          captured = request;
          return _jsonResponse(_accountMenuFullJson);
        }),
      );
      service.sessionProvider = () async => _session();

      final AccountInfo? info = await service.fetchAccountInfo();

      expect(captured!.url.path, '/youtubei/v1/account/account_menu');
      expect(info, isNotNull);
      expect(info!.name, 'Siti');
      expect(info.email, 'siti@example.com');
      // Thumbnail terbesar (width 256) yang dipilih, bukan yang 32px.
      expect(info.avatarUrl, 'https://lh3.googleusercontent.com/a/s256');
      service.dispose();
    });

    test('email dan avatar yang hilang menjadi null tanpa melempar',
        () async {
      final YouTubeMusicService service = YouTubeMusicService(
        httpClient: MockClient((http.Request request) async =>
            _jsonResponse(_accountMenuSparseJson)),
      );
      service.sessionProvider = () async => _session();

      final AccountInfo? info = await service.fetchAccountInfo();

      expect(info, isNotNull);
      expect(info!.name, 'Budi');
      expect(info.email, isNull);
      expect(info.avatarUrl, isNull);
      service.dispose();
    });

    test('mengembalikan null saat HTTP gagal atau respons rusak', () async {
      final YouTubeMusicService failing = YouTubeMusicService(
        httpClient: MockClient((http.Request request) async =>
            _jsonResponse('{"error": "server"}', 500)),
      );
      failing.sessionProvider = () async => _session();
      expect(await failing.fetchAccountInfo(), isNull);
      failing.dispose();

      final YouTubeMusicService broken = YouTubeMusicService(
        httpClient: MockClient((http.Request request) async =>
            _jsonResponse('bukan json')),
      );
      broken.sessionProvider = () async => _session();
      expect(await broken.fetchAccountInfo(), isNull);
      broken.dispose();
    });

    test('fetchAccountName tetap bekerja lewat fetchAccountInfo', () async {
      final YouTubeMusicService service = YouTubeMusicService(
        httpClient: MockClient((http.Request request) async =>
            _jsonResponse(_accountMenuFullJson)),
      );
      service.sessionProvider = () async => _session();
      expect(await service.fetchAccountName(), 'Siti');
      service.dispose();
    });
  });

  group('YoutubeAuthService info akun (email + avatar)', () {
    test('capture mengisi email dan avatar dari fetchAccountInfo', () async {
      final InMemorySessionStore store = InMemorySessionStore();
      final YoutubeAuthService auth = YoutubeAuthService(
        store: store,
        fetchAccountInfo: (YoutubeSession session) async => AccountInfo(
          name: 'Budi',
          email: 'budi@example.com',
          avatarUrl: 'https://example.com/budi.png',
        ),
      );

      final bool ok = await auth.capture(
        cookie: _validCookie,
        dataSyncId: 'ds',
        authUser: '0',
        visitorData: 'v',
        clientVersion: '1.0.0',
      );

      expect(ok, isTrue);
      expect(auth.signedIn, isTrue);
      expect(auth.accountName, 'Budi');
      expect(auth.accountEmail, 'budi@example.com');
      expect(auth.accountAvatarUrl, 'https://example.com/budi.png');
    });

    test('restore mengisi email dan avatar dari fetchAccountInfo', () async {
      final InMemorySessionStore store = InMemorySessionStore();
      await store.write(jsonEncode(_session().toJson()));
      int calls = 0;
      final YoutubeAuthService auth = YoutubeAuthService(
        store: store,
        fetchAccountInfo: (YoutubeSession session) async {
          calls++;
          return AccountInfo(
            name: 'Siti',
            email: 'siti@example.com',
            avatarUrl: 'https://example.com/siti.png',
          );
        },
      );

      await auth.restore();

      expect(calls, 1);
      expect(auth.signedIn, isTrue);
      expect(auth.accountName, 'Siti');
      expect(auth.accountEmail, 'siti@example.com');
      expect(auth.accountAvatarUrl, 'https://example.com/siti.png');
    });

    test('fetchAccountInfo yang gagal tidak menggagalkan capture', () async {
      final InMemorySessionStore store = InMemorySessionStore();
      final YoutubeAuthService auth = YoutubeAuthService(
        store: store,
        fetchAccountInfo: (YoutubeSession session) async =>
            throw Exception('jaringan putus'),
      );

      final bool ok = await auth.capture(
        cookie: _validCookie,
        dataSyncId: 'ds',
        authUser: '0',
        visitorData: 'v',
        clientVersion: '1.0.0',
      );

      expect(ok, isTrue);
      expect(auth.signedIn, isTrue);
      expect(auth.accountName, isNull);
      expect(auth.accountEmail, isNull);
      expect(auth.accountAvatarUrl, isNull);
    });

    test('signOut mengosongkan email dan avatar akun', () async {
      final InMemorySessionStore store = InMemorySessionStore();
      final YoutubeAuthService auth = YoutubeAuthService(
        store: store,
        fetchAccountInfo: (YoutubeSession session) async => AccountInfo(
          name: 'Budi',
          email: 'budi@example.com',
          avatarUrl: 'https://example.com/budi.png',
        ),
      );
      await auth.capture(
        cookie: _validCookie,
        dataSyncId: 'ds',
        authUser: '0',
        visitorData: 'v',
        clientVersion: '1.0.0',
      );
      expect(auth.accountEmail, isNotNull);

      await auth.signOut();

      expect(auth.signedIn, isFalse);
      expect(auth.accountName, isNull);
      expect(auth.accountEmail, isNull);
      expect(auth.accountAvatarUrl, isNull);
    });

    test('fetchAccountInfo dipakai tanpa memanggil fetchAccountName',
        () async {
      final InMemorySessionStore store = InMemorySessionStore();
      int nameCalls = 0;
      int infoCalls = 0;
      final YoutubeAuthService auth = YoutubeAuthService(
        store: store,
        fetchAccountName: (YoutubeSession session) async {
          nameCalls++;
          return 'Nama Lama';
        },
        fetchAccountInfo: (YoutubeSession session) async {
          infoCalls++;
          return const AccountInfo(
            name: 'Nama Baru',
            email: 'baru@example.com',
          );
        },
      );

      await auth.capture(
        cookie: _validCookie,
        dataSyncId: 'ds',
        authUser: '0',
        visitorData: 'v',
        clientVersion: '1.0.0',
      );

      expect(infoCalls, 1);
      expect(nameCalls, 0);
      expect(auth.accountName, 'Nama Baru');
      expect(auth.accountEmail, 'baru@example.com');
      expect(auth.accountAvatarUrl, isNull);
    });
  });

  group('YouTubeMusicService.fetchHomeSections', () {
    test('memarsek rak carousel, rak biasa, kartu MPED, dan judul kosong',
        () async {
      http.Request? captured;
      final YouTubeMusicService service = YouTubeMusicService(
        httpClient: MockClient((http.Request request) async {
          captured = request;
          return _jsonResponse(_homeJson);
        }),
      );
      service.sessionProvider = () async => _session();

      final List<MusicSection> sections = await service.fetchHomeSections();

      // Request browse yang benar.
      expect(captured, isNotNull);
      expect(captured!.url.host, 'music.youtube.com');
      expect(captured!.url.path, '/youtubei/v1/browse');
      final Map<String, dynamic> body =
          jsonDecode(captured!.body) as Map<String, dynamic>;
      expect(body['browseId'], 'FEmusic_home');

      // Rak kosong dilewati; sisanya 3 rak.
      expect(sections, hasLength(3));
      expect(sections[0].title, 'Quick picks');
      expect(sections[1].title, 'For you');
      expect(sections[2].title, 'Listen again');

      // Kartu trek + kartu koleksi pada rak pertama.
      expect(sections[0].items, hasLength(2));
      expect(sections[0].items[0].type, 'song');
      expect(sections[0].items[0].videoId, 'homeVid');
      expect(sections[0].items[0].title, 'Lagu Utama');
      expect(sections[0].items[1].type, 'playlist');
      expect(sections[0].items[1].browseId, 'VLpl123');
      expect(sections[0].items[1].videoId, isNull);

      // Kartu riwayat MPED menjadi trek dengan videoId dari awalan.
      expect(sections[1].items, hasLength(1));
      expect(sections[1].items[0].type, 'song');
      expect(sections[1].items[0].videoId, 'histVid1');
      expect(sections[1].items[0].browseId, isNull);

      // Baris responsif pada rak biasa.
      expect(sections[2].items, hasLength(1));
      expect(sections[2].items[0].videoId, 'homeRow');
      expect(sections[2].items[0].duration, '4:05');
      expect(
        sections[2].items[0].thumbnail,
        'https://i.ytimg.com/vi/homeRow/hq.jpg',
      );
      service.dispose();
    });

    test('belum masuk mengembalikan daftar kosong tanpa request', () async {
      int calls = 0;
      final YouTubeMusicService service = YouTubeMusicService(
        httpClient: MockClient((http.Request request) async {
          calls++;
          return _jsonResponse(_homeJson);
        }),
      );
      // Tanpa sessionProvider — setara pengguna anonim.

      expect(await service.fetchHomeSections(), isEmpty);
      expect(calls, 0);
      service.dispose();
    });

    test('kegagalan HTTP atau respons rusak mengembalikan daftar kosong',
        () async {
      final YouTubeMusicService failing = YouTubeMusicService(
        httpClient: MockClient((http.Request request) async =>
            _jsonResponse('{"error": "server"}', 500)),
      );
      failing.sessionProvider = () async => _session();
      expect(await failing.fetchHomeSections(), isEmpty);
      failing.dispose();

      final YouTubeMusicService broken = YouTubeMusicService(
        httpClient: MockClient(
            (http.Request request) async => _jsonResponse('bukan json')),
      );
      broken.sessionProvider = () async => _session();
      expect(await broken.fetchHomeSections(), isEmpty);
      broken.dispose();
    });

    test('membatasi jumlah rak dan item per rak', () async {
      // 12 rak × 40 item; hasil harus dipangkas menjadi 10 rak × 30 item.
      final List<Map<String, Object?>> shelves = <Map<String, Object?>>[];
      for (var s = 0; s < 12; s++) {
        shelves.add(<String, Object?>{
          'musicShelfRenderer': <String, Object?>{
            'title': <String, Object?>{
              'runs': <Object?>[
                <String, Object?>{'text': 'Rak $s'},
              ],
            },
            'contents': List<Map<String, Object?>>.generate(40, (int i) {
              return <String, Object?>{
                'musicResponsiveListItemRenderer': <String, Object?>{
                  'playlistItemData': <String, Object?>{
                    'videoId': 'v${s}_$i',
                  },
                  'flexColumns': <Object?>[
                    <String, Object?>{
                      'musicResponsiveListItemFlexColumnRenderer':
                          <String, Object?>{
                        'text': <String, Object?>{
                          'runs': <Object?>[
                            <String, Object?>{'text': 'Lagu ${s}_$i'},
                          ],
                        },
                      },
                    },
                  ],
                },
              };
            }),
          },
        });
      }
      final String cappedJson = jsonEncode(<String, dynamic>{
        'contents': <String, dynamic>{
          'singleColumnBrowseResultsRenderer': <String, dynamic>{
            'tabs': <Object?>[
              <String, dynamic>{
                'tabRenderer': <String, dynamic>{
                  'content': <String, dynamic>{
                    'sectionListRenderer': <String, dynamic>{
                      'contents': shelves,
                    },
                  },
                },
              },
            ],
          },
        },
      });
      final YouTubeMusicService service = YouTubeMusicService(
        httpClient: MockClient(
            (http.Request request) async => _jsonResponse(cappedJson)),
      );
      service.sessionProvider = () async => _session();

      final List<MusicSection> sections = await service.fetchHomeSections();

      expect(sections, hasLength(10));
      for (final MusicSection section in sections) {
        expect(section.items, hasLength(30));
      }
      expect(sections.last.title, 'Rak 9');
      service.dispose();
    });
  });

  group('YouTubeMusicService.search sesi masuk', () {
    test('rute ke music.youtube.com dengan Cookie dan Authorization',
        () async {
      http.Request? captured;
      final YouTubeMusicService service = YouTubeMusicService(
        httpClient: MockClient((http.Request request) async {
          captured = request;
          return _jsonResponse(_musicSearchJson);
        }),
      );
      final YoutubeSession session = _session();
      service.sessionProvider = () async => session;

      final List<MusicItem> items = await service.search('lagu uji');

      expect(captured, isNotNull);
      expect(captured!.url.host, 'music.youtube.com');
      expect(captured!.url.path, '/youtubei/v1/search');
      expect(captured!.headers['cookie'], session.cookie);
      expect(captured!.headers.containsKey('authorization'), isTrue);
      final Map<String, dynamic> body =
          jsonDecode(captured!.body) as Map<String, dynamic>;
      expect(body['query'], 'lagu uji');
      expect(items, isNotEmpty);
      expect(items.first.videoId, 'searchVid');
      expect(items.first.title, 'Lagu Cari');
      service.dispose();
    });

    test('tanpa sesi tetap memakai endpoint anonim lama', () async {
      http.Request? captured;
      final YouTubeMusicService service = YouTubeMusicService(
        httpClient: MockClient((http.Request request) async {
          captured = request;
          return _jsonResponse(_anonymousSearchJson);
        }),
      );
      // Tanpa sessionProvider — setara pengguna anonim.

      final List<MusicItem> items = await service.search('lagu uji');

      expect(captured, isNotNull);
      expect(captured!.url.host, 'www.youtube.com');
      expect(captured!.url.path, '/youtubei/v1/search');
      expect(captured!.headers.containsKey('cookie'), isFalse);
      expect(captured!.headers.containsKey('authorization'), isFalse);
      expect(items, hasLength(1));
      expect(items.first.videoId, 'anonVid');
      service.dispose();
    });

    test('gagal pada music.youtube.com jatuh ke hasil anonim', () async {
      final List<http.Request> requests = <http.Request>[];
      final YouTubeMusicService service = YouTubeMusicService(
        httpClient: MockClient((http.Request request) async {
          requests.add(request);
          if (request.url.host == 'music.youtube.com') {
            return _jsonResponse('{"error": "server"}', 500);
          }
          return _jsonResponse(_anonymousSearchJson);
        }),
      );
      service.sessionProvider = () async => _session();

      final List<MusicItem> items = await service.search('lagu uji');

      expect(requests, hasLength(2));
      expect(requests[0].url.host, 'music.youtube.com');
      expect(requests[1].url.host, 'www.youtube.com');
      expect(items, hasLength(1));
      expect(items.first.videoId, 'anonVid');
      service.dispose();
    });
  });
}
