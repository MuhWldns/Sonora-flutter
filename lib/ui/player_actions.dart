/// Aksi pemutar bersama: memutar item, memutar seluruh daftar, menambahkan ke
/// antrean, dan membuka layar Browse. Dipakai oleh Home, Search, Browse, dan
/// Library agar perilaku konsisten dan hanya ada satu jalur ke pemutar.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../data/music_models.dart';
import 'app_scope.dart';
import 'player/player_controller.dart';
import 'screens/browse.dart';
import 'widgets/common.dart';

class PlayerActions {
  PlayerActions._(BuildContext context)
      : _context = context,
        _player = SonoraScope.of(context).player;

  final BuildContext _context;
  final PlayerController _player;

  static PlayerActions of(BuildContext context) => PlayerActions._(context);

  /// Video id lagu yang sedang diputar (untuk menyorot baris aktif).
  String? get activeVideoId => _player.snapshot.current?.videoId;

  void play(MusicItem item) => unawaited(_player.playItem(item));

  void playQueue(List<MusicItem> items, {int startIndex = 0}) =>
      unawaited(_player.playQueue(items, startIndex: startIndex));

  void addToQueue(MusicItem item, {bool next = false}) =>
      unawaited(_player.addItem(item, next: next));

  void open(MusicItem item) {
    final String? target = browseTargetOf(item);
    if (target == null) {
      if (item.isPlayable) play(item);
      return;
    }
    Navigator.of(_context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => BrowseScreen(browseId: target, title: item.title),
      ),
    );
  }
}
