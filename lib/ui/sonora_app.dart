/// Titik masuk UI Sonora.
///
/// Konstruktor persis seperti yang dipanggil `lib/main.dart`:
/// `SonoraApp(settings:, api:, audio:, database:)`. Widget ini memasang tema
/// Nocturne (dark atmosferik + derivasi terang, aksen crimson), menyediakan
/// dependensi ke subtree, dan merakit pemutar + navigasi.
library;

import 'package:flutter/material.dart';

import '../data/local_database.dart';
import '../data/settings_store.dart';
import '../data/sonora_api.dart';
import '../playback/sonora_audio_handler.dart';
import 'app_scope.dart';
import 'player/player_controller.dart';
import 'root_shell.dart';
import 'theme.dart';

class SonoraApp extends StatefulWidget {
  const SonoraApp({
    super.key,
    required this.settings,
    required this.api,
    required this.audio,
    this.database,
  });

  final SettingsStore settings;
  final SonoraApi api;
  final SonoraAudioHandler audio;
  final LocalDatabase? database;

  @override
  State<SonoraApp> createState() => _SonoraAppState();
}

class _SonoraAppState extends State<SonoraApp> {
  late final PlayerController _player = PlayerController(widget.audio);
  late final AppTabController _tabs = AppTabController();

  @override
  void dispose() {
    _player.dispose();
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SonoraScope(
      settings: widget.settings,
      api: widget.api,
      player: _player,
      tabs: _tabs,
      database: widget.database,
      child: MaterialApp(
        title: 'Sonora',
        debugShowCheckedModeBanner: false,
        theme: buildSonoraTheme(Brightness.light),
        darkTheme: buildSonoraTheme(Brightness.dark),
        themeMode: ThemeMode.system,
        home: const RootShell(),
      ),
    );
  }
}
