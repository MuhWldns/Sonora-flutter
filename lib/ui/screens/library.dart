/// Koleksi pengguna: filter tipe, sorting bottom sheet, serta mode list/grid.
library;

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/music_models.dart';
import '../app_scope.dart';
import '../player_actions.dart';
import '../player/player_chrome.dart';
import '../theme.dart';
import '../widgets/common.dart';

enum _LibrarySort { recent, added, alphabet, creator }

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  String _filter = 'Playlist';
  _LibrarySort _sort = _LibrarySort.recent;
  bool _grid = false;

  static const List<String> _filters = <String>['Playlist', 'Album', 'Artis'];

  List<Map<String, Object?>> _playlists = <Map<String, Object?>>[];
  List<MusicItem> _savedAlbums = <MusicItem>[];
  List<MusicItem> _savedArtists = <MusicItem>[];
  bool _loading = true;
  AppTabController? _tabs;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tabs = SonoraScope.of(context).tabs;
    if (!identical(tabs, _tabs)) {
      _tabs?.removeListener(_onTabChanged);
      _tabs = tabs..addListener(_onTabChanged);
    }
    if (_playlists.isEmpty && _loading) _load();
  }

  @override
  void dispose() {
    _tabs?.removeListener(_onTabChanged);
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabs?.index == AppTabs.library) _load();
  }

  Future<void> _load() async {
    final db = SonoraScope.of(context).database;
    final values = await db.getPlaylists();
    final albums = await db.getSavedCollections('album');
    final artists = await db.getSavedCollections('artist');
    if (!mounted) return;
    setState(() {
      _playlists = values;
      _savedAlbums = albums;
      _savedArtists = artists;
      _loading = false;
    });
  }

  String get _sortLabel => switch (_sort) {
    _LibrarySort.recent => 'Terakhir',
    _LibrarySort.added => 'Baru ditambahkan',
    _LibrarySort.alphabet => 'Abjad',
    _LibrarySort.creator => 'Kreator',
  };

  List<MusicItem> get _visible => _filter == 'Playlist'
      ? <MusicItem>[
          for (final row in _playlists)
            MusicItem(
              type: 'playlist',
              title: row['name'] as String? ?? 'Playlist',
              subtitle: '${row['track_count'] ?? 0} lagu',
              thumbnail: row['artwork_url'] as String?,
              localThumbnailPath: row['artwork_path'] as String?,
              playlistId: row['id'] as String,
            ),
        ]
      : _filter == 'Album'
      ? _savedAlbums
      : _savedArtists;

  Future<void> _createPlaylist() async {
    final name = TextEditingController();
    final description = TextEditingController();
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Playlist baru'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Nama playlist'),
            ),
            TextField(
              controller: description,
              decoration: const InputDecoration(
                labelText: 'Deskripsi (opsional)',
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, (
              name.text.trim(),
              description.text.trim(),
            )),
            child: const Text('Buat'),
          ),
        ],
      ),
    );
    if (result == null || result.$1.isEmpty || !mounted) return;
    await SonoraScope.of(context).database.createPlaylist(
      DateTime.now().microsecondsSinceEpoch.toString(),
      result.$1,
      description: result.$2,
    );
    await _load();
  }

  Future<void> _chooseSort() async {
    final selected = await showModalBottomSheet<_LibrarySort>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                kSpaceLg,
                0,
                kSpaceLg,
                kSpaceSm,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Urutkan menurut', style: context.texts.titleLarge),
              ),
            ),
            for (final option in <(_LibrarySort, String)>[
              (_LibrarySort.recent, 'Terakhir'),
              (_LibrarySort.added, 'Baru ditambahkan'),
              (_LibrarySort.alphabet, 'Abjad'),
              (_LibrarySort.creator, 'Kreator'),
            ])
              ListTile(
                title: Text(option.$2),
                leading: Icon(
                  option.$1 == _sort
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                trailing: option.$1 == _sort
                    ? Icon(Icons.check_rounded, color: context.sonora.success)
                    : null,
                onTap: () => Navigator.pop(context, option.$1),
              ),
            const SizedBox(height: kSpaceSm),
          ],
        ),
      ),
    );
    if (selected != null) setState(() => _sort = selected);
  }

  @override
  Widget build(BuildContext context) {
    final items = _visible;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: <Widget>[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                kSpaceLg,
                kSpaceLg,
                kSpaceSm,
                kSpaceSm,
              ),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'Koleksi Kamu',
                        style: context.texts.displaySmall,
                      ),
                    ),
                    IconButton(
                      onPressed: () async {
                        final q = await showSearch<String?>(
                          context: context,
                          delegate: _PlaylistSearchDelegate(_playlists),
                        );
                        if (q != null) setState(() {});
                      },
                      icon: const Icon(Icons.search_rounded),
                    ),
                    IconButton(
                      onPressed: _createPlaylist,
                      icon: const Icon(Icons.add_rounded),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 52,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: kSpaceLg),
                  itemCount: _filters.length,
                  separatorBuilder: (_, _) => const SizedBox(width: kSpaceSm),
                  itemBuilder: (_, int index) => ChoiceChip(
                    label: Text(_filters[index]),
                    selected: _filter == _filters[index],
                    onSelected: (_) =>
                        setState(() => _filter = _filters[index]),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  kSpaceLg,
                  kSpaceMd,
                  kSpaceLg,
                  kSpaceSm,
                ),
                child: Row(
                  children: <Widget>[
                    TextButton.icon(
                      onPressed: _chooseSort,
                      icon: const Icon(Icons.swap_vert_rounded, size: 20),
                      label: Text(_sortLabel),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => setState(() => _grid = false),
                      icon: Icon(
                        Icons.view_list_rounded,
                        color: !_grid ? context.scheme.primary : null,
                      ),
                    ),
                    IconButton(
                      onPressed: () => setState(() => _grid = true),
                      icon: Icon(
                        Icons.grid_view_rounded,
                        color: _grid ? context.scheme.primary : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_loading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (items.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.library_music_outlined,
                  title: 'Belum ada koleksi',
                  message: 'Tambahkan playlist, album, atau artis favoritmu.',
                ),
              )
            else if (_grid)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  kSpaceLg,
                  0,
                  kSpaceLg,
                  kSpaceXxl,
                ),
                sliver: SliverGrid.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: kSpaceMd,
                  crossAxisSpacing: kSpaceMd,
                  childAspectRatio: .76,
                  children: items
                      .map((item) => _LibraryGridItem(item: item))
                      .toList(),
                ),
              )
            else
              SliverList.builder(
                itemCount: items.length,
                itemBuilder: (_, int index) =>
                    _LibraryListItem(item: items[index]),
              ),
          ],
        ),
      ),
    );
  }
}

class _LibraryGridItem extends StatelessWidget {
  const _LibraryGridItem({required this.item});
  final MusicItem item;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: item.playlistId != null
        ? () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) =>
                  PlaylistDetailScreen(id: item.playlistId!, name: item.title),
            ),
          )
        : item.browseTarget == null
        ? null
        : () => PlayerActions.of(context).open(item),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        item.type == 'playlist' && item.playlistId != null
            ? _PlaylistArtwork(
                id: item.playlistId!,
                url: item.thumbnail,
                path: item.localThumbnailPath,
                size: 160,
              )
            : CoverArt(
                url: item.thumbnail,
                localPath: item.localThumbnailPath,
                size: 160,
                circle: item.type == 'artist',
                icon: item.type == 'artist'
                    ? Icons.person_rounded
                    : Icons.queue_music_rounded,
              ),
        const SizedBox(height: kSpaceSm),
        Text(
          item.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.texts.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        Text(
          item.subtitle ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.texts.bodySmall?.copyWith(
            color: context.scheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}

class _PlaylistSearchDelegate extends SearchDelegate<String?> {
  _PlaylistSearchDelegate(this.playlists);
  final List<Map<String, Object?>> playlists;
  @override
  List<Widget>? buildActions(BuildContext context) => <Widget>[
    IconButton(
      onPressed: () => query = '',
      icon: const Icon(Icons.clear_rounded),
    ),
  ];
  @override
  Widget? buildLeading(BuildContext context) => IconButton(
    onPressed: () => close(context, null),
    icon: const Icon(Icons.arrow_back_rounded),
  );
  @override
  Widget buildResults(BuildContext context) => buildSuggestions(context);
  @override
  Widget buildSuggestions(BuildContext context) {
    final filtered = playlists.where(
      (row) => (row['name'] as String? ?? '').toLowerCase().contains(
        query.toLowerCase(),
      ),
    );
    return ListView(
      children: filtered
          .map<Widget>(
            (row) => ListTile(
              title: Text(row['name'] as String? ?? ''),
              subtitle: Text('${row['track_count'] ?? 0} lagu'),
            ),
          )
          .toList(),
    );
  }
}

class _LibraryListItem extends StatelessWidget {
  const _LibraryListItem({required this.item});
  final MusicItem item;
  @override
  Widget build(BuildContext context) => ListTile(
    leading: item.type == 'playlist' && item.playlistId != null
        ? _PlaylistArtwork(
            id: item.playlistId!,
            url: item.thumbnail,
            path: item.localThumbnailPath,
            size: 56,
          )
        : CoverArt(
            url: item.thumbnail,
            localPath: item.localThumbnailPath,
            size: 56,
            circle: item.type == 'artist',
            icon: item.type == 'artist'
                ? Icons.person_rounded
                : Icons.queue_music_rounded,
          ),
    title: Text(item.title),
    subtitle: Text(item.subtitle ?? ''),
    onTap: item.playlistId != null
        ? () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) =>
                  PlaylistDetailScreen(id: item.playlistId!, name: item.title),
            ),
          )
        : item.browseTarget == null
        ? null
        : () => PlayerActions.of(context).open(item),
    trailing: PopupMenuButton<String>(
      onSelected: (value) async {
        final db = SonoraScope.of(context).database;
        if (value == 'edit') {
          final name = TextEditingController(text: item.title);
          final bio = TextEditingController(text: item.subtitle);
          final result = await showDialog<(String, String)>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Edit playlist'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Nama'),
                  ),
                  TextField(
                    controller: bio,
                    decoration: const InputDecoration(labelText: 'Deskripsi'),
                  ),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Batal'),
                ),
                FilledButton(
                  onPressed: () =>
                      Navigator.pop(context, (name.text, bio.text)),
                  child: const Text('Simpan'),
                ),
              ],
            ),
          );
          if (result != null) {
            await db.updatePlaylist(
              item.playlistId!,
              name: result.$1,
              description: result.$2,
            );
          }
        } else if (value == 'delete') {
          await db.deletePlaylist(item.playlistId!);
        }
        if (context.mounted) SonoraScope.of(context).tabs.goTo(AppTabs.library);
      },
      itemBuilder: (_) => const <PopupMenuEntry<String>>[
        PopupMenuItem(value: 'edit', child: Text('Edit nama & deskripsi')),
        PopupMenuItem(value: 'delete', child: Text('Hapus playlist')),
      ],
    ),
  );
}

class PlaylistDetailScreen extends StatefulWidget {
  const PlaylistDetailScreen({super.key, required this.id, required this.name});
  final String id;
  final String name;
  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailState();
}

class _PlaylistDetailState extends State<PlaylistDetailScreen> {
  late Future<List<MusicItem>> _tracks;
  bool _showRecommendations = false;
  bool _loadingRecommendations = false;
  List<MusicItem> _recommendations = <MusicItem>[];
  final Set<String> _selected = <String>{};
  final TextEditingController _addSearch = TextEditingController();

  @override
  void dispose() {
    _addSearch.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tracks = SonoraScope.of(context).database.getPlaylistTracks(widget.id);
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    final tracks = SonoraScope.of(
      context,
    ).database.getPlaylistTracks(widget.id);
    setState(() => _tracks = tracks);
  }

  Future<void> _loadRecommendations() async {
    if (_loadingRecommendations) return;
    setState(() => _loadingRecommendations = true);
    final scope = SonoraScope.of(context);
    final history = await scope.database.getRecentSearches(limit: 30);
    final seen = <String>{};
    final found = <MusicItem>[];
    for (final search in history) {
      try {
        final sections = await scope.api.search(search.query);
        for (final section in sections) {
          for (final item in section.items) {
            final id = item.videoId;
            if (id != null && id.isNotEmpty && seen.add(id)) found.add(item);
          }
        }
      } catch (_) {
        // Lewati query yang gagal dan coba pencarian sebelumnya.
      }
      if (found.length >= 30) break;
    }
    if (found.isEmpty) {
      try {
        final sections = await scope.api.home();
        for (final section in sections) {
          for (final item in section.items) {
            final id = item.videoId;
            if (id != null && id.isNotEmpty && seen.add(id)) found.add(item);
          }
        }
      } catch (_) {
        // Pencarian manual tetap tersedia jika rekomendasi belum bisa dimuat.
      }
    }
    if (!mounted) return;
    setState(() {
      _recommendations = found.take(30).toList(growable: false);
      _loadingRecommendations = false;
    });
  }

  Future<void> _searchToAdd(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    setState(() => _loadingRecommendations = true);
    try {
      final sections = await SonoraScope.of(context).api.search(trimmed);
      if (!mounted) return;
      final items = <MusicItem>[];
      final seen = <String>{};
      for (final section in sections) {
        for (final item in section.items) {
          if (item.videoId != null && seen.add(item.videoId!)) items.add(item);
        }
      }
      if (items.isEmpty) {
        final home = await SonoraScope.of(context).api.home();
        for (final section in home) {
          for (final item in section.items) {
            if (item.videoId != null && seen.add(item.videoId!)) {
              items.add(item);
            }
          }
        }
      }
      setState(() {
        _recommendations = items;
        _loadingRecommendations = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingRecommendations = false);
    }
  }

  Future<void> _addItem(MusicItem item) async {
    final db = SonoraScope.of(context).database;
    if (widget.id == 'favorites') {
      await db.addFavorite(item);
    } else {
      await db.addToPlaylist(widget.id, item);
    }
    if (item.videoId != null && mounted) {
      setState(() => _selected.add(item.videoId!));
      await _refresh();
    }
  }

  Future<void> _editPlaylist() async {
    if (widget.id == 'favorites') return;
    final db = SonoraScope.of(context).database;
    final playlists = await db.getPlaylists();
    if (!mounted) return;
    final row = playlists.firstWhere((entry) => entry['id'] == widget.id);
    final name = TextEditingController(
      text: row['name'] as String? ?? widget.name,
    );
    final description = TextEditingController(
      text: row['description'] as String? ?? '',
    );
    final artworkUrl = TextEditingController(
      text: row['artwork_url'] as String? ?? '',
    );
    String? artworkPath = row['artwork_path'] as String?;
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit playlist'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Nama'),
                ),
                TextField(
                  controller: description,
                  decoration: const InputDecoration(labelText: 'Deskripsi'),
                ),
                TextField(
                  controller: artworkUrl,
                  decoration: const InputDecoration(labelText: 'URL foto'),
                ),
                TextButton.icon(
                  onPressed: () async {
                    final image = await ImagePicker().pickImage(
                      source: ImageSource.gallery,
                    );
                    if (image != null) {
                      setDialogState(() {
                        artworkPath = image.path;
                        artworkUrl.clear();
                      });
                    }
                  },
                  icon: const Icon(Icons.photo_library_outlined),
                  label: Text(
                    artworkPath == null
                        ? 'Pilih foto lokal'
                        : 'Foto lokal dipilih',
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
    if (save == true) {
      await db.updatePlaylist(
        widget.id,
        name: name.text,
        description: description.text,
        artworkUrl: artworkUrl.text.trim().isEmpty
            ? null
            : artworkUrl.text.trim(),
        artworkPath: artworkPath,
      );
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.name),
      actions: <Widget>[
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded),
          onSelected: (value) async {
            final db = SonoraScope.of(context).database;
            final navigator = Navigator.of(context);
            if (value == 'edit') await _editPlaylist();
            if (value == 'delete') {
              await db.deletePlaylist(widget.id);
              if (mounted) navigator.pop();
            }
            if (value == 'add') {
              setState(() => _showRecommendations = !_showRecommendations);
              if (_showRecommendations && _recommendations.isEmpty) {
                await _loadRecommendations();
              }
            }
          },
          itemBuilder: (_) => <PopupMenuEntry<String>>[
            if (widget.id != 'favorites')
              const PopupMenuItem(value: 'edit', child: Text('Edit playlist')),
            if (widget.id != 'favorites')
              const PopupMenuItem(
                value: 'delete',
                child: Text('Hapus playlist'),
              ),
            const PopupMenuItem(value: 'add', child: Text('Tambah lagu')),
          ],
        ),
      ],
    ),
    bottomNavigationBar: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const MiniPlayer(),
        NavigationBar(
          selectedIndex: SonoraScope.of(context).tabs.index,
          onDestinationSelected: (index) {
            Navigator.of(context).popUntil((route) => route.isFirst);
            SonoraScope.of(context).tabs.goTo(index);
          },
          destinations: const <Widget>[
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Beranda',
            ),
            NavigationDestination(
              icon: Icon(Icons.search_outlined),
              selectedIcon: Icon(Icons.search_rounded),
              label: 'Cari',
            ),
            NavigationDestination(
              icon: Icon(Icons.library_music_outlined),
              selectedIcon: Icon(Icons.library_music_rounded),
              label: 'Koleksi',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings_rounded),
              label: 'Pengaturan',
            ),
          ],
        ),
      ],
    ),
    body: FutureBuilder<List<MusicItem>>(
      future: _tracks,
      builder: (context, snapshot) {
        final tracks = snapshot.data ?? const <MusicItem>[];
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView(
          children: <Widget>[
            FutureBuilder<List<Map<String, Object?>>>(
              future: SonoraScope.of(context).database.getPlaylists(),
              builder: (context, playlists) {
                final row = playlists.data
                    ?.where((value) => value['id'] == widget.id)
                    .firstOrNull;
                if (row == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: _PlaylistArtwork(
                    id: widget.id,
                    url: row['artwork_url'] as String?,
                    path: row['artwork_path'] as String?,
                    size: (MediaQuery.sizeOf(context).width - 32).clamp(0, 360),
                  ),
                );
              },
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '${tracks.length} lagu',
                style: context.texts.bodyMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: tracks.isEmpty
                          ? null
                          : () => PlayerActions.of(context).playQueue(tracks),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Putar semua'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: tracks.isEmpty
                          ? null
                          : () => PlayerActions.of(context).playQueue(
                              tracks,
                              startIndex: Random().nextInt(tracks.length),
                            ),
                      icon: const Icon(Icons.shuffle_rounded),
                      label: const Text('Acak'),
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFF808080),
                child: Icon(Icons.add_rounded, color: Colors.white),
              ),
              title: const Text('Tambahkan lagu'),
              onTap: () async {
                setState(() => _showRecommendations = true);
                await _loadRecommendations();
              },
            ),
            if (_showRecommendations)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _addSearch,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Cari lagu',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.arrow_forward_rounded),
                      onPressed: () => _searchToAdd(_addSearch.text),
                    ),
                  ),
                  onSubmitted: _searchToAdd,
                ),
              ),
            if (_loadingRecommendations)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              ),
            if (_showRecommendations && !_loadingRecommendations) ...<Widget>[
              for (final item in _recommendations)
                CheckboxListTile(
                  value:
                      _selected.contains(item.videoId) ||
                      tracks.any((track) => track.videoId == item.videoId),
                  secondary: CoverArt(url: item.thumbnail, size: 48),
                  title: Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    item.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onChanged: (checked) async {
                    final id = item.videoId;
                    if (id == null) return;
                    if (checked == true) {
                      await _addItem(item);
                    } else {
                      if (widget.id == 'favorites') {
                        await SonoraScope.of(
                          context,
                        ).database.removeFavorite(id);
                      } else {
                        await SonoraScope.of(
                          context,
                        ).database.removeFromPlaylist(widget.id, id);
                      }
                      if (mounted) {
                        setState(() => _selected.remove(id));
                        await _refresh();
                      }
                    }
                  },
                ),
            ],
            for (final item in tracks)
              SongRow(
                item: item,
                onPlay: () => PlayerActions.of(context).play(item),
                onAddToQueue: (next) =>
                    PlayerActions.of(context).addToQueue(item, next: next),
                trailing: widget.id == 'favorites'
                    ? IconButton(
                        icon: const Icon(
                          Icons.favorite_rounded,
                          color: Colors.redAccent,
                        ),
                        onPressed: () async {
                          await SonoraScope.of(
                            context,
                          ).database.removeFavorite(item.videoId ?? '');
                          await _refresh();
                        },
                      )
                    : IconButton(
                        icon: const Icon(Icons.remove_circle_outline_rounded),
                        onPressed: () async {
                          await SonoraScope.of(
                            context,
                          ).database.removeFromPlaylist(
                            widget.id,
                            item.videoId ?? '',
                          );
                          await _refresh();
                        },
                      ),
              ),
          ],
        );
      },
    ),
  );
}

class _PlaylistArtwork extends StatelessWidget {
  const _PlaylistArtwork({
    required this.id,
    this.url,
    this.path,
    this.size = 180,
  });
  final String id;
  final String? url;
  final String? path;
  final double size;

  @override
  Widget build(BuildContext context) => FutureBuilder<List<MusicItem>>(
    future: SonoraScope.of(context).database.getPlaylistTracks(id),
    builder: (context, snapshot) {
      final tracks = snapshot.data ?? const <MusicItem>[];
      if (tracks.isEmpty && (url == null || url!.isEmpty) && path == null) {
        return CoverArt(
          url: url,
          localPath: path,
          size: size,
          icon: id == 'favorites'
              ? Icons.favorite_rounded
              : Icons.queue_music_rounded,
        );
      }
      if (tracks.isEmpty) {
        return CoverArt(url: url, localPath: path, size: size);
      }
      return ClipRRect(
        borderRadius: BorderRadius.circular(kRadiusMd),
        child: SizedBox(
          height: size,
          width: size,
          child: Column(
            children: <Widget>[
              Expanded(
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: CoverArt(
                        url: tracks[0 % tracks.length].thumbnail,
                        size: size / 2,
                        radius: 0,
                      ),
                    ),
                    Expanded(
                      child: CoverArt(
                        url: tracks[1 % tracks.length].thumbnail,
                        size: size / 2,
                        radius: 0,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: CoverArt(
                        url: tracks[2 % tracks.length].thumbnail,
                        size: size / 2,
                        radius: 0,
                      ),
                    ),
                    Expanded(
                      child: CoverArt(
                        url: tracks[3 % tracks.length].thumbnail,
                        size: size / 2,
                        radius: 0,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
