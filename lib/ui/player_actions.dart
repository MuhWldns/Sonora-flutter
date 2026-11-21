/// Aksi pemutar bersama: memutar item, memutar seluruh daftar, menambahkan ke
/// antrean, dan membuka layar Browse. Dipakai oleh Home, Search, Browse, dan
/// Library agar perilaku konsisten dan hanya ada satu jalur ke pemutar.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../data/music_models.dart';
import '../data/local_database.dart';
import 'app_scope.dart';
import 'player/player_controller.dart';
import 'screens/browse.dart';
import 'widgets/common.dart';

class PlayerActions {
  PlayerActions._(BuildContext context)
    : _context = context,
      _player = SonoraScope.of(context).player,
      _database = SonoraScope.of(context).database;

  final BuildContext _context;
  final PlayerController _player;
  final LocalDatabase _database;

  static PlayerActions of(BuildContext context) => PlayerActions._(context);

  /// Video id lagu yang sedang diputar (untuk menyorot baris aktif).
  String? get activeVideoId => _player.snapshot.current?.videoId;

  void play(MusicItem item) => unawaited(_player.playItem(item));

  void playQueue(List<MusicItem> items, {int startIndex = 0}) =>
      unawaited(_player.playQueue(items, startIndex: startIndex));

  void addToQueue(MusicItem item, {bool next = false}) =>
      unawaited(_player.addItem(item, next: next));

  Future<void> addToFavorites(MusicItem item) async {
    await _database.addFavorite(item);
    final playlists = await _database.getPlaylists();
    final favorite = playlists.where((row) => row['id'] == 'favorites');
    if (favorite.isNotEmpty) await _database.addToPlaylist('favorites', item);
  }

  Future<void> showPlaylistPicker(MusicItem item) async {
    var playlists = await _database.getPlaylists();
    if (!_context.mounted) return;
    final selected = await showModalBottomSheet<String>(
      context: _context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Tambahkan ke playlist',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context, '__create__'),
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
            ),
            for (final row in playlists)
              ListTile(
                leading: const Icon(Icons.queue_music_rounded),
                title: Text(row['name'] as String? ?? ''),
                onTap: () => Navigator.pop(context, row['id'] as String),
              ),
            if (playlists.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text('Belum ada playlist. Tekan + untuk membuat.'),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (selected == null || !_context.mounted) return;
    if (selected == '__create__') {
      final controller = TextEditingController();
      final name = await showDialog<String>(
        context: _context,
        builder: (context) => AlertDialog(
          title: const Text('Playlist baru'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Nama playlist'),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Buat'),
            ),
          ],
        ),
      );
      if (name == null || name.isEmpty) return;
      final id = DateTime.now().microsecondsSinceEpoch.toString();
      await _database.createPlaylist(id, name);
      await _database.addToPlaylist(id, item);
    } else {
      await _database.addToPlaylist(selected, item);
    }
    if (_context.mounted) {
      showSonoraSnack(_context, 'Lagu ditambahkan ke playlist', success: true);
    }
  }

  void open(MusicItem item) {
    final String? target = browseTargetOf(item);
    if (target == null) {
      if (item.isPlayable) play(item);
      return;
    }
    Navigator.of(_context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => BrowseScreen(
          browseId: target,
          title: item.title,
          thumbnail: item.thumbnail,
          typeLabel: item.type == 'artist'
              ? 'Artis'
              : item.type == 'playlist'
              ? 'Playlist'
              : 'Album',
          collectionItem: item,
        ),
      ),
    );
  }
}
