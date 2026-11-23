import 'dart:async';

import 'package:flutter/material.dart';

import 'data/audio_cache_service.dart';
import 'data/local_database.dart';
import 'data/settings_store.dart';
import 'data/sonora_api.dart';
import 'data/youtube_music_service.dart';
import 'playback/sonora_audio_handler.dart';
import 'ui/sonora_app.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _Startup());
}

class _Startup extends StatefulWidget {
  const _Startup();

  @override
  State<_Startup> createState() => _StartupState();
}

class _StartupState extends State<_Startup> {
  SettingsStore? _settings;
  SonoraApi? _api;
  YouTubeMusicService? _ytService;
  SonoraAudioHandler? _audio;
  LocalDatabase? _database;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    setState(() => _failed = false);
    SettingsStore? settings;
    SonoraApi? api;
    YouTubeMusicService? ytService;
    LocalDatabase? database;
    try {
      settings = await SettingsStore.load();
      api = SonoraApi(settings);
      ytService = YouTubeMusicService();
      final audio = await SonoraAudioHandler.initialize(api, ytService: ytService);
      // Basis data lokal opsional: riwayat pencarian + favorit. Kegagalan
      // membuka SQLite tidak boleh menggagalkan aplikasi.
      try {
        database = await LocalDatabase.open();
      } catch (_) {
        database = null;
      }
      // Pemangkasan cache audio di latar belakang (LRU max 500 MB) pada startup.
      unawaited(AudioCacheService.pruneCache());
      if (!mounted) {
        await database?.close();
        await audio.dispose();
        ytService.dispose();
        api.close();
        settings.dispose();
        return;
      }
      setState(() {
        _settings = settings;
        _api = api;
        _ytService = ytService;
        _audio = audio;
        _database = database;
      });
    } catch (_) {
      await database?.close();
      ytService?.dispose();
      api?.close();
      settings?.dispose();
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_audio != null) {
      return SonoraApp(
        settings: _settings!,
        api: _api!,
        audio: _audio!,
        ytService: _ytService!,
        database: _database,
      );
    }
    return MaterialApp(
      title: 'Sonora',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: kAccent)),
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _failed
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.music_off_outlined, size: 48),
                      const SizedBox(height: 16),
                      const Text('Pemutar audio tidak dapat disiapkan.'),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _initialize,
                        child: const Text('Coba lagi'),
                      ),
                    ],
                  )
                : const CircularProgressIndicator(),
          ),
        ),
      ),
    );
  }
}
