/// Pengujian Kotak Hitam Otomatis (Automated Black-Box UI & Widget Tests)
/// untuk memvalidasi kasus uji yang didefinisikan pada docs/testing/01-blackbox-testing.md.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:just_audio/just_audio.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sonora_flutter/data/local_database.dart';
import 'package:sonora_flutter/data/lyrics_store.dart';
import 'package:sonora_flutter/data/music_models.dart';
import 'package:sonora_flutter/data/settings_store.dart';
import 'package:sonora_flutter/data/sonora_api.dart';
import 'package:sonora_flutter/data/youtube_music_service.dart';
import 'package:sonora_flutter/playback/sonora_audio_handler.dart';
import 'package:sonora_flutter/ui/app_scope.dart';
import 'package:sonora_flutter/ui/player/player_controller.dart';
import 'package:sonora_flutter/ui/screens/browse.dart';
import 'package:sonora_flutter/ui/screens/home.dart';
import 'package:sonora_flutter/ui/screens/search.dart';
import 'package:sonora_flutter/ui/screens/settings.dart';
import 'package:sonora_flutter/ui/theme.dart';

/// Implementasi tiruan pemutar audio murni in-memory tanpa platform channels.
class FakeSonoraAudioHandler extends BaseAudioHandler
    with SeekHandler
    implements SonoraPlaybackHandler {
  FakeSonoraAudioHandler();

  @override
  final ValueNotifier<String?> error = ValueNotifier<String?>(null);

  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Duration get position => Duration.zero;

  @override
  AndroidEqualizer? get equalizer => null;

  @override
  Future<void> appendSuggestions(List<MusicItem> items) async {}

  @override
  Future<void> playItems(List<MusicItem> items, {int startIndex = 0}) async {
    final List<MusicItem> playable = items.where((e) => e.isPlayable).toList();
    final List<MediaItem> media = playable
        .map((e) => MediaItem(
              id: e.videoId!,
              title: e.title,
              artist: e.artist,
              duration: parseDurationToMs(e.duration) != null
                  ? Duration(milliseconds: parseDurationToMs(e.duration)!)
                  : null,
            ))
        .toList();
    queue.add(List<MediaItem>.unmodifiable(media));
    final int idx = startIndex.clamp(0, media.isEmpty ? 0 : media.length - 1);
    if (media.isNotEmpty) {
      mediaItem.add(media[idx]);
    }
    playbackState.add(playbackState.value.copyWith(
      playing: true,
      processingState: AudioProcessingState.ready,
      queueIndex: idx,
    ));
  }

  @override
  Future<void> play() async {
    playbackState.add(playbackState.value.copyWith(playing: true));
  }

  @override
  Future<void> pause() async {
    playbackState.add(playbackState.value.copyWith(playing: false));
  }

  @override
  Future<void> stop() async {
    queue.add(const <MediaItem>[]);
    mediaItem.add(null);
    playbackState.add(playbackState.value.copyWith(
      playing: false,
      processingState: AudioProcessingState.idle,
    ));
  }

  @override
  Future<void> skipToNext() async {
    final List<MediaItem> q = queue.value;
    final int cur = playbackState.value.queueIndex ?? 0;
    if (cur + 1 < q.length) {
      mediaItem.add(q[cur + 1]);
      playbackState.add(playbackState.value.copyWith(queueIndex: cur + 1));
    }
  }

  @override
  Future<void> skipToPrevious() async {
    final List<MediaItem> q = queue.value;
    final int cur = playbackState.value.queueIndex ?? 0;
    if (cur - 1 >= 0 && q.isNotEmpty) {
      mediaItem.add(q[cur - 1]);
      playbackState.add(playbackState.value.copyWith(queueIndex: cur - 1));
    }
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    final List<MediaItem> q = queue.value;
    if (index >= 0 && index < q.length) {
      mediaItem.add(q[index]);
      playbackState.add(playbackState.value.copyWith(queueIndex: index));
    }
  }

  @override
  Future<void> seek(Duration position) async {
    _positionController.add(position);
  }

  Future<void> dispose() async {
    await _positionController.close();
    error.dispose();
  }
}

/// Implementasi tiruan [YouTubeMusicService] untuk pengujian kotak hitam terisolasi.
class FakeYouTubeMusicService extends YouTubeMusicService {
  FakeYouTubeMusicService({
    this.searchResult = const <MusicItem>[],
    this.browseResult = const <MusicSection>[],
    this.trendingResult = const <MusicItem>[],
  });

  List<MusicItem> searchResult;
  List<MusicSection> browseResult;
  List<MusicItem> trendingResult;

  int searchCalls = 0;
  int browseCalls = 0;
  int trendingCalls = 0;

  @override
  Future<List<MusicItem>> search(String query) async {
    searchCalls++;
    return searchResult;
  }

  @override
  Future<List<MusicSection>> browse(
    String browseId, {
    String? title,
    String? type,
    int limit = 50,
  }) async {
    browseCalls++;
    return browseResult;
  }

  @override
  Future<List<MusicItem>> getTrending() async {
    trendingCalls++;
    return trendingResult;
  }
}

/// Implementasi tiruan basis data lokal in-memory tanpa SQLite/FFI.
class FakeLocalDatabase extends Fake implements LocalDatabase {
  final List<SearchHistoryItem> searchHistory = <SearchHistoryItem>[];
  final Set<String> favoriteIds = <String>{};
  final List<MusicItem> favoriteList = <MusicItem>[];
  final List<MusicItem> recentPlaybacks = <MusicItem>[];
  final List<Map<String, Object?>> playlists = <Map<String, Object?>>[];
  final Map<String, List<MusicItem>> playlistTracks = <String, List<MusicItem>>{};
  final List<Map<String, Object?>> listeningLogs = <Map<String, Object?>>[];

  @override
  Future<void> recordPlayback(MusicItem item, {DateTime? playedAt}) async {
    if (item.videoId != null) {
      recentPlaybacks.removeWhere((MusicItem e) => e.videoId == item.videoId);
      recentPlaybacks.insert(0, item);
    }
  }

  @override
  Future<List<MusicItem>> getRecentPlaybacks({int limit = 100}) async {
    return List<MusicItem>.unmodifiable(recentPlaybacks.take(limit));
  }

  @override
  Future<List<MusicItem>> getPlaybacksSince(int timestamp, {int limit = 100}) async {
    return List<MusicItem>.unmodifiable(recentPlaybacks.take(limit));
  }

  @override
  Future<void> recordSearch(String query, {String? filter}) async {
    searchHistory.removeWhere((SearchHistoryItem e) => e.query == query);
    searchHistory.insert(
      0,
      SearchHistoryItem(
        query: query,
        filter: filter,
        searchedAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<List<SearchHistoryItem>> getRecentSearches({int limit = 10}) async {
    return searchHistory.take(limit).toList();
  }

  @override
  Future<void> clearSearchHistory() async {
    searchHistory.clear();
  }

  @override
  Future<void> createPlaylist(
    String id,
    String name, {
    String description = '',
  }) async {
    playlists.add(<String, Object?>{
      'id': id,
      'name': name,
      'description': description,
      'track_count': 0,
    });
  }

  @override
  Future<List<Map<String, Object?>>> getPlaylists() async {
    return playlists.map((Map<String, Object?> p) {
      final List<MusicItem> tracks = playlistTracks[p['id']] ?? <MusicItem>[];
      return <String, Object?>{
        ...p,
        'track_count': tracks.length,
      };
    }).toList();
  }

  @override
  Future<void> addToPlaylist(String playlistId, MusicItem item) async {
    playlistTracks.putIfAbsent(playlistId, () => <MusicItem>[]).add(item);
  }

  @override
  Future<List<MusicItem>> getPlaylistTracks(String playlistId) async {
    return playlistTracks[playlistId] ?? <MusicItem>[];
  }

  @override
  Future<bool> isFavorite(String videoId) async {
    return favoriteIds.contains(videoId);
  }

  @override
  Future<void> addFavorite(MusicItem item, {DateTime? addedAt}) async {
    if (item.videoId != null) {
      favoriteIds.add(item.videoId!);
      favoriteList.removeWhere((MusicItem e) => e.videoId == item.videoId);
      favoriteList.insert(0, item);
    }
  }

  @override
  Future<void> removeFavorite(String videoId) async {
    favoriteIds.remove(videoId);
    favoriteList.removeWhere((MusicItem e) => e.videoId == videoId);
  }

  @override
  Future<List<MusicItem>> getFavorites({int limit = 100}) async {
    return List<MusicItem>.unmodifiable(favoriteList.take(limit));
  }

  @override
  Future<void> recordListeningLog({
    required MusicItem item,
    required int listenedSeconds,
    int durationSeconds = 0,
    DateTime? playedAt,
  }) async {
    if (listenedSeconds < 15) return;
    listeningLogs.add(<String, Object?>{
      'video_id': item.videoId,
      'title': item.title,
      'artist': item.artist,
      'duration_seconds': durationSeconds,
      'listened_seconds': listenedSeconds,
      'played_at': playedAt ?? DateTime.now(),
    });
  }

  @override
  Future<ListeningStats> getListeningStats(
    int startTimestamp, {
    int limit = 10,
  }) async {
    final int totalSec = listeningLogs.fold<int>(
      0,
      (int sum, Map<String, Object?> el) =>
          sum + (el['listened_seconds'] as int? ?? 0),
    );
    final List<TopTrackStat> topTracks = listeningLogs
        .map((Map<String, Object?> el) => TopTrackStat(
              videoId: el['video_id'] as String? ?? '',
              title: el['title'] as String? ?? '',
              artist: el['artist'] as String? ?? '',
              playCount: 1,
              totalMinutes: ((el['listened_seconds'] as int? ?? 0) / 60).round(),
            ))
        .toList();
    return ListeningStats(
      totalMinutes: totalSec ~/ 60,
      totalPlays: listeningLogs.length,
      topTracks: topTracks,
      topArtists: const <TopArtistStat>[],
    );
  }

  @override
  Future<void> close() async {}
}

/// Wadah pengujian UI mandiri yang memuat seluruh dependensi aplikasi.
class TestHarness {
  TestHarness({
    required this.settings,
    required this.api,
    required this.ytService,
    required this.handler,
    required this.player,
    required this.tabs,
    required this.database,
  });

  final SettingsStore settings;
  final SonoraApi api;
  final FakeYouTubeMusicService ytService;
  final FakeSonoraAudioHandler handler;
  final PlayerController player;
  final AppTabController tabs;
  final LocalDatabase database;

  static Future<TestHarness> create({
    String initialProxy = '',
    String initialDraft = '',
    http.Client? httpClient,
    FakeYouTubeMusicService? customYt,
    LocalDatabase? customDb,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'sonora.proxyBase': initialProxy,
      'sonora.proxyDraft': initialDraft,
    });

    final SettingsStore settings = await SettingsStore.load();
    final FakeYouTubeMusicService ytService = customYt ?? FakeYouTubeMusicService();

    final http.Client client = httpClient ??
        MockClient((http.Request request) async {
          if (request.url.path.endsWith('/healthz')) {
            return http.Response(
              jsonEncode(<String, Object?>{'ok': true, 'version': '1.0.0'}),
              200,
              headers: <String, String>{
                'content-type': 'application/json; charset=utf-8',
              },
            );
          }
          return http.Response('Not Found', 404);
        });

    final SonoraApi api = SonoraApi(settings, client: client);
    final LocalDatabase db = customDb ?? FakeLocalDatabase();

    final FakeSonoraAudioHandler handler = FakeSonoraAudioHandler();
    final PlayerController player = PlayerController(handler, database: db);
    final AppTabController tabs = AppTabController();

    return TestHarness(
      settings: settings,
      api: api,
      ytService: ytService,
      handler: handler,
      player: player,
      tabs: tabs,
      database: db,
    );
  }

  Widget buildApp(Widget child) {
    return MaterialApp(
      theme: buildSonoraTheme(Brightness.dark, useGoogleFonts: false),
      home: SonoraScope(
        settings: settings,
        api: api,
        ytService: ytService,
        player: player,
        tabs: tabs,
        database: database,
        child: Scaffold(body: child),
      ),
    );
  }

  Future<void> dispose() async {
    player.dispose();
    await handler.dispose();
    await database.close();
  }
}

const MusicItem kTestSong1 = MusicItem(
  type: 'song',
  title: 'Song One',
  artist: 'Artist A',
  videoId: 'vid_001',
  duration: '3:45',
);

const MusicItem kTestSong2 = MusicItem(
  type: 'song',
  title: 'Song Two',
  artist: 'Artist B',
  videoId: 'vid_002',
  duration: '4:20',
);

class FakePathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  @override
  Future<String?> getTemporaryPath() async => Directory.systemTemp.path;

  @override
  Future<String?> getApplicationSupportPath() async => Directory.systemTemp.path;

  @override
  Future<String?> getApplicationDocumentsPath() async => Directory.systemTemp.path;
}

void main() {
  setUpAll(() {
    PathProviderPlatform.instance = FakePathProviderPlatform();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => Directory.systemTemp.path,
    );
  });

  group('Modul 1: TC-SET (Pengaturan, Add-on, & Manajemen Cache)', () {
    testWidgets('TC-SET-01: Validasi input URL proxy yang sah dan penyimpanan', (
      WidgetTester tester,
    ) async {
      final TestHarness harness = await TestHarness.create();
      addTearDown(harness.dispose);

      await tester.pumpWidget(harness.buildApp(const SettingsScreen()));
      await tester.pumpAndSettle();

      // Aktifkan sakelar Add-on
      await tester.tap(find.widgetWithText(SwitchListTile, 'Sonora Node Proxy'));
      await tester.pumpAndSettle();

      // Masukkan URL sah
      await tester.enterText(
        find.byType(TextField),
        'https://proxy.example.com:8787',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Simpan'));
      await tester.pumpAndSettle();

      expect(harness.settings.proxyBase, 'https://proxy.example.com:8787');
      expect(find.textContaining('Endpoint tersimpan'), findsOneWidget);
    });

    testWidgets('TC-SET-02: Penolakan input URL dengan skema tidak valid (ftp://)', (
      WidgetTester tester,
    ) async {
      final TestHarness harness = await TestHarness.create();
      addTearDown(harness.dispose);

      await tester.pumpWidget(harness.buildApp(const SettingsScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(SwitchListTile, 'Sonora Node Proxy'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'ftp://myhost:8787');
      await tester.tap(find.widgetWithText(FilledButton, 'Simpan'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Skema URL proxy harus http atau https'),
        findsOneWidget,
      );
      expect(harness.settings.proxyBase, isEmpty);
    });

    testWidgets('TC-SET-03: Penolakan input URL memuat query atau fragment', (
      WidgetTester tester,
    ) async {
      final TestHarness harness = await TestHarness.create();
      addTearDown(harness.dispose);

      await tester.pumpWidget(harness.buildApp(const SettingsScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(SwitchListTile, 'Sonora Node Proxy'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextField),
        'https://host:8787/api?key=secret#part',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Simpan'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('tidak boleh memuat query atau fragment'),
        findsOneWidget,
      );
      expect(harness.settings.proxyBase, isEmpty);
    });

    testWidgets('TC-SET-04: Tombol Tes koneksi memanggil /healthz dan menampilkan status', (
      WidgetTester tester,
    ) async {
      final TestHarness harness = await TestHarness.create(
        initialProxy: 'https://proxy.example.com:8787',
      );
      addTearDown(harness.dispose);

      await tester.pumpWidget(harness.buildApp(const SettingsScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Tes koneksi'));
      await tester.pumpAndSettle();

      expect(find.text('https://proxy.example.com:8787'), findsAtLeastNWidgets(1));
    });

    testWidgets('TC-SET-05: Toggle switch Add-on dimatikan dan draf tersimpan', (
      WidgetTester tester,
    ) async {
      final TestHarness harness = await TestHarness.create(
        initialProxy: 'https://proxy.example.com:8787',
      );
      addTearDown(harness.dispose);

      await tester.pumpWidget(harness.buildApp(const SettingsScreen()));
      await tester.pumpAndSettle();

      // Matikan sakelar Add-on
      await tester.tap(find.widgetWithText(SwitchListTile, 'Sonora Node Proxy'));
      await tester.pumpAndSettle();

      expect(harness.settings.proxyBase, isEmpty);
      expect(harness.settings.proxyDraft, 'https://proxy.example.com:8787');
      expect(find.byType(TextField), findsNothing);

      // Aktifkan kembali sakelar Add-on
      await tester.tap(find.widgetWithText(SwitchListTile, 'Sonora Node Proxy'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
      expect(
        find.widgetWithText(TextField, 'https://proxy.example.com:8787'),
        findsOneWidget,
      );
    });

    testWidgets('TC-SET-06: Pembersihan cache audio manual via tombol Bersihkan', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final TestHarness harness = await TestHarness.create();
      addTearDown(harness.dispose);

      await tester.pumpWidget(harness.buildApp(const SettingsScreen()));
      await tester.pumpAndSettle();

      final Finder btn = find.widgetWithText(OutlinedButton, 'Bersihkan');
      await tester.tap(btn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        find.text('Cache audio berhasil dibersihkan.'),
        findsOneWidget,
      );
    });
  });

  group('Modul 2: TC-PLY (Pemutar Audio & Kontrol Transport UI)', () {
    testWidgets('TC-PLY-02: Kontrol transport pemutar (Play/Pause/Next/Previous)', (
      WidgetTester tester,
    ) async {
      final TestHarness harness = await TestHarness.create();
      addTearDown(harness.dispose);

      await harness.player.playQueue(<MusicItem>[kTestSong1, kTestSong2]);

      expect(harness.player.snapshot.queue, hasLength(2));
      expect(harness.player.snapshot.index, 0);
      expect(harness.player.snapshot.current?.videoId, kTestSong1.videoId);

      await harness.player.togglePlay();
      expect(harness.player.snapshot.playing, isFalse);

      await harness.player.next();
      expect(harness.player.snapshot.index, 1);
      expect(harness.player.snapshot.current?.videoId, kTestSong2.videoId);

      await harness.player.previous();
      expect(harness.player.snapshot.index, 0);
      expect(harness.player.snapshot.current?.videoId, kTestSong1.videoId);
    });

    testWidgets('TC-PLY-04: Siklus mode pengulangan (Repeat Mode: Off -> All -> One -> Off)', (
      WidgetTester tester,
    ) async {
      final TestHarness harness = await TestHarness.create();
      addTearDown(harness.dispose);

      expect(harness.player.snapshot.repeat, PlayerRepeatMode.off);

      await harness.player.cycleRepeat();
      expect(harness.player.snapshot.repeat, PlayerRepeatMode.all);

      await harness.player.cycleRepeat();
      expect(harness.player.snapshot.repeat, PlayerRepeatMode.one);

      await harness.player.cycleRepeat();
      expect(harness.player.snapshot.repeat, PlayerRepeatMode.off);
    });

    testWidgets('TC-PLY-05: Toggle mode acak antrean (Shuffle Mode)', (
      WidgetTester tester,
    ) async {
      final TestHarness harness = await TestHarness.create();
      addTearDown(harness.dispose);

      expect(harness.player.snapshot.shuffle, isFalse);

      await harness.player.toggleShuffle();
      expect(harness.player.snapshot.shuffle, isTrue);

      await harness.player.toggleShuffle();
      expect(harness.player.snapshot.shuffle, isFalse);
    });
  });

  group('Modul 3: TC-SRC (Pencarian & Riwayat SQLite)', () {
    testWidgets('TC-SRC-01 & TC-SRC-03: Pencarian lagu dengan debounce dan rendering hasil', (
      WidgetTester tester,
    ) async {
      final FakeYouTubeMusicService ytService = FakeYouTubeMusicService(
        searchResult: <MusicItem>[kTestSong1],
      );
      final TestHarness harness = await TestHarness.create(customYt: ytService);
      addTearDown(harness.dispose);

      await tester.pumpWidget(harness.buildApp(const SearchScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Song One');
      // Tunggu debounce 350ms
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(ytService.searchCalls, greaterThanOrEqualTo(1));
      expect(find.text('Song One'), findsAtLeastNWidgets(1));
      expect(find.textContaining('Artist A'), findsAtLeastNWidgets(1));
    });

    testWidgets('TC-SRC-02: Pemilihan filter kategori pencarian (ChoiceChip)', (
      WidgetTester tester,
    ) async {
      final TestHarness harness = await TestHarness.create();
      addTearDown(harness.dispose);

      await tester.pumpWidget(harness.buildApp(const SearchScreen()));
      await tester.pumpAndSettle();

      final Finder laguChip = find.widgetWithText(ChoiceChip, 'Lagu');
      expect(laguChip, findsOneWidget);

      await tester.tap(laguChip);
      await tester.pumpAndSettle();

      final ChoiceChip chipWidget = tester.widget<ChoiceChip>(laguChip);
      expect(chipWidget.selected, isTrue);
    });

    testWidgets('TC-SRC-04: Riwayat pencarian tersimpan di database dan tampil sebagai chip', (
      WidgetTester tester,
    ) async {
      final TestHarness harness = await TestHarness.create();
      addTearDown(harness.dispose);

      await harness.database.recordSearch('lofi beats', filter: 'song');

      await tester.pumpWidget(harness.buildApp(const SearchScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Riwayat pencarian'), findsOneWidget);
      expect(find.text('lofi beats'), findsOneWidget);
    });

    testWidgets('TC-SRC-05: Tombol Hapus riwayat pencarian membersihkan database dan layar', (
      WidgetTester tester,
    ) async {
      final TestHarness harness = await TestHarness.create();
      addTearDown(harness.dispose);

      await harness.database.recordSearch('jazz piano');

      await tester.pumpWidget(harness.buildApp(const SearchScreen()));
      await tester.pumpAndSettle();

      expect(find.text('jazz piano'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Hapus'));
      await tester.pumpAndSettle();

      expect(find.text('Riwayat pencarian'), findsNothing);
      expect(await harness.database.getRecentSearches(), isEmpty);
    });
  });

  group('Modul 4: TC-LIB (Koleksi, Playlist Lokal, & Statistik)', () {
    testWidgets('TC-LIB-01: Pembuatan playlist kustom lokal baru di SQLite', (
      WidgetTester tester,
    ) async {
      final TestHarness harness = await TestHarness.create();
      addTearDown(harness.dispose);

      await harness.database.createPlaylist('p1', 'Lagu Belajar');

      final List<Map<String, Object?>> playlists = await harness.database.getPlaylists();
      expect(playlists, hasLength(1));
      expect(playlists.first['name'], 'Lagu Belajar');
    });

    testWidgets('TC-LIB-02: Penambahan trek lagu ke playlist kustom', (
      WidgetTester tester,
    ) async {
      final TestHarness harness = await TestHarness.create();
      addTearDown(harness.dispose);

      await harness.database.createPlaylist('p2', 'Favorit Santai');
      await harness.database.addToPlaylist('p2', kTestSong1);

      final List<MusicItem> tracks = await harness.database.getPlaylistTracks('p2');
      expect(tracks, hasLength(1));
      expect(tracks.first.videoId, kTestSong1.videoId);
    });

    testWidgets('TC-LIB-03: Penandaan lagu favorit (addFavorite/removeFavorite)', (
      WidgetTester tester,
    ) async {
      final TestHarness harness = await TestHarness.create();
      addTearDown(harness.dispose);

      expect(await harness.database.isFavorite(kTestSong1.videoId!), isFalse);

      await harness.database.addFavorite(kTestSong1);
      expect(await harness.database.isFavorite(kTestSong1.videoId!), isTrue);

      await harness.database.removeFavorite(kTestSong1.videoId!);
      expect(await harness.database.isFavorite(kTestSong1.videoId!), isFalse);
    });

    testWidgets('TC-LIB-04 & TC-LIB-05: Rekam durasi mendengarkan >= 15s dan abaikan skip < 15s', (
      WidgetTester tester,
    ) async {
      final TestHarness harness = await TestHarness.create();
      addTearDown(harness.dispose);

      // TC-LIB-05: Skip di detik ke-5 (< 15s) tidak dicatat
      await harness.database.recordListeningLog(
        item: kTestSong1,
        listenedSeconds: 5,
        durationSeconds: 180,
      );
      var stats = await harness.database.getListeningStats(0);
      expect(stats.totalPlays, 0);

      // TC-LIB-04: Mendengarkan 25 detik (>= 15s) dicatat ke statistik
      await harness.database.recordListeningLog(
        item: kTestSong1,
        listenedSeconds: 25,
        durationSeconds: 180,
      );
      stats = await harness.database.getListeningStats(0);
      expect(stats.totalPlays, 1);
      expect(stats.topTracks.first.videoId, kTestSong1.videoId);
    });
  });

  group('Modul 5: TC-LYR (Lirik Tersinkronisasi Waktu Nyata)', () {
    test('TC-LYR-01 & TC-LYR-02: Parsing LRC dan penentuan baris aktif (activeIndexAt)', () {
      const String lrc = '''
[00:10.00]Baris pertama lirik
[00:25.50]Baris kedua sedang dinyanyikan
[01:10.00]Baris ketiga reff
''';
      final List<LrcLine> parsed = LyricsRepository.parseSynced(lrc);
      expect(parsed, hasLength(3));
      expect(parsed[0].text, 'Baris pertama lirik');
      expect(parsed[1].timestamp.inMilliseconds, 25500);

      final LrcLyrics lyrics = LrcLyrics(synced: parsed);

      // Pada detik ke-15, baris aktif adalah baris ke-0
      expect(lyrics.activeIndexAt(const Duration(seconds: 15)), 0);

      // Pada detik ke-30, baris aktif adalah baris ke-1
      expect(lyrics.activeIndexAt(const Duration(seconds: 30)), 1);

      // Pada detik ke-75, baris aktif adalah baris ke-2
      expect(lyrics.activeIndexAt(const Duration(seconds: 75)), 2);
    });

    test('TC-LYR-04: Penanganan lirik tidak tersedia secara anggun (null safety)', () async {
      final http.Client client = MockClient((http.Request request) async {
        return http.Response('{"message": "Not Found"}', 404);
      });
      final LyricsRepository repo = LyricsRepository(client: client);

      final LrcLyrics? result = await repo.find(
        track: 'Instrumental Song',
        artist: 'Unknown Artist',
      );
      expect(result, isNull);
      repo.dispose();
    });
  });

  group('Modul 6: TC-BRW (Halaman Browse & Ketahanan Jaringan)', () {
    testWidgets('TC-BRW-01: Pemuatan halaman album/playlist mode mandiri (tanpa proxy)', (
      WidgetTester tester,
    ) async {
      final FakeYouTubeMusicService ytService = FakeYouTubeMusicService(
        browseResult: <MusicSection>[
          const MusicSection(
            title: 'Top Hits Indonesia',
            items: <MusicItem>[kTestSong1, kTestSong2],
          ),
        ],
      );
      final TestHarness harness = await TestHarness.create(customYt: ytService);
      addTearDown(harness.dispose);

      await tester.pumpWidget(
        harness.buildApp(
          const BrowseScreen(
            browseId: 'VLPL_TEST_01',
            title: 'Top Hits Indonesia',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(ytService.browseCalls, 1);
      expect(find.text('Top Hits Indonesia'), findsAtLeastNWidgets(1));
      expect(find.text('Song One'), findsAtLeastNWidgets(1));
      expect(find.text('Song Two'), findsAtLeastNWidgets(1));
    });

    testWidgets('TC-BRW-02: Aksi tombol Putar semua pada halaman Browse', (
      WidgetTester tester,
    ) async {
      final FakeYouTubeMusicService ytService = FakeYouTubeMusicService(
        browseResult: <MusicSection>[
          const MusicSection(
            title: 'Koleksi Akustik',
            items: <MusicItem>[kTestSong1, kTestSong2],
          ),
        ],
      );
      final TestHarness harness = await TestHarness.create(customYt: ytService);
      addTearDown(harness.dispose);

      await tester.pumpWidget(
        harness.buildApp(
          const BrowseScreen(
            browseId: 'VLPL_TEST_02',
            title: 'Koleksi Akustik',
          ),
        ),
      );
      await tester.pumpAndSettle();

      final Finder playAllBtn = find.widgetWithText(FilledButton, 'Putar semua (2)');
      expect(playAllBtn, findsOneWidget);

      await tester.tap(playAllBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(harness.player.snapshot.queue, hasLength(2));
      expect(harness.player.snapshot.queue.first.videoId, kTestSong1.videoId);
    });

    testWidgets('TC-BRW-03: Auto-fallback saat server proxy mengalami kegagalan/offline', (
      WidgetTester tester,
    ) async {
      final http.Client failingClient = MockClient((http.Request request) async {
        return http.Response('Server Error', 500);
      });

      final FakeYouTubeMusicService ytService = FakeYouTubeMusicService(
        browseResult: <MusicSection>[
          const MusicSection(
            title: 'Fallback Playlist',
            items: <MusicItem>[kTestSong1],
          ),
        ],
      );

      final TestHarness harness = await TestHarness.create(
        initialProxy: 'https://broken-proxy.internal:8787',
        httpClient: failingClient,
        customYt: ytService,
      );
      addTearDown(harness.dispose);

      await tester.pumpWidget(
        harness.buildApp(
          const BrowseScreen(
            browseId: 'VLPL_FAILOVER',
            title: 'Fallback Playlist',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Memastikan fallback mandiri ke YouTubeMusicService berjalan mulus
      expect(ytService.browseCalls, 1);
      expect(find.text('Fallback Playlist'), findsAtLeastNWidgets(1));
      expect(find.text('Song One'), findsAtLeastNWidgets(1));
    });

    testWidgets('Modul Beranda: Tombol Muat ulang selalu aktif pada mode mandiri', (
      WidgetTester tester,
    ) async {
      final FakeYouTubeMusicService ytService = FakeYouTubeMusicService(
        trendingResult: <MusicItem>[kTestSong1],
      );
      final TestHarness harness = await TestHarness.create(customYt: ytService);
      addTearDown(harness.dispose);

      await tester.pumpWidget(harness.buildApp(const HomeScreen()));
      await tester.pumpAndSettle();

      expect(ytService.trendingCalls, 1);

      final Finder refreshBtn = find.byTooltip('Muat ulang');
      expect(refreshBtn, findsOneWidget);

      await tester.tap(refreshBtn);
      await tester.pumpAndSettle();

      expect(ytService.trendingCalls, 2);
    });
  });
}
