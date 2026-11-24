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
import 'theme.dart';
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

  /// Memutar daftar mulai [index] sehingga antrean langsung berisi lagu-lagu
  /// berikutnya. Item koleksi (playlist/album) tetap dibuka di halaman Browse.
  void playFrom(List<MusicItem> items, int index) {
    if (index < 0 || index >= items.length) return;
    final MusicItem item = items[index];
    if (browseTargetOf(item) != null) {
      open(item);
      return;
    }
    playQueue(items, startIndex: index);
  }
  void addToQueue(MusicItem item, {bool next = false}) =>
      unawaited(_player.addItem(item, next: next));

  Future<void> addToFavorites(MusicItem item) async {
    final db = SonoraScope.of(_context).database;
    if (db == null) {
      showSonoraSnack(_context, 'Penyimpanan lokal tidak tersedia');
      return;
    }
    await db.addFavorite(item);
    if (_context.mounted) {
      showSonoraSnack(_context, 'Lagu ditambahkan ke favorit', success: true);
    }
  }

  Future<void> showPlaylistPicker(MusicItem item) async {
    final db = SonoraScope.of(_context).database;
    if (db == null) {
      showSonoraSnack(_context, 'Penyimpanan lokal tidak tersedia');
      return;
    }
    final playlists = await db.getPlaylists();
    if (!_context.mounted) return;
    final selected = await showModalBottomSheet<String>(
      context: _context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(kSpaceLg),
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
              Material(
                color: Colors.transparent,
                child: ListTile(
                  leading: const Icon(Icons.queue_music_rounded),
                  title: Text(row['name'] as String? ?? ''),
                  onTap: () => Navigator.pop(context, row['id'] as String),
                ),
              ),
            if (playlists.isEmpty)
              const Padding(
                padding: EdgeInsets.all(kSpaceXl),
                child: Text('Belum ada playlist. Tekan + untuk membuat.'),
              ),
            const SizedBox(height: kSpaceMd),
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
      await db.createPlaylist(id, name);
      await db.addToPlaylist(id, item);
    } else {
      await db.addToPlaylist(selected, item);
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
          typeLabel: _typeLabel(item.type),
          collectionItem: item,
        ),
      ),
    );
  }

  /// Label overline header Browse dari tipe item proxy.
  static String _typeLabel(String type) {
    switch (type.toLowerCase()) {
      case 'playlist':
        return 'Playlist';
      case 'artist':
        return 'Artis';
      case 'video':
        return 'Video';
      case 'album':
      default:
        return 'Album';
    }
  }
}
