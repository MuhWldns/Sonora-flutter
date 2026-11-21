/// Layar Cari: riwayat pencarian lokal dan hasil dari proxy Sonora.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/local_database.dart';
import '../../data/music_models.dart';
import '../../data/settings_store.dart';
import '../../data/sonora_api.dart';
import '../app_scope.dart';
import '../player/player_controller.dart';
import '../player_actions.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Filter tipe hasil pencarian; `null` berarti semua jenis.
const List<({String? id, String label})> kSearchFilters =
    <({String? id, String label})>[
  (id: null, label: 'Semua'),
  (id: 'song', label: 'Lagu'),
  (id: 'video', label: 'Video'),
  (id: 'artist', label: 'Artis'),
  (id: 'album', label: 'Album'),
  (id: 'playlist', label: 'Playlist'),
];

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  Timer? _debounce;
  int _generation = 0;
  String? _filter;
  List<MusicSection>? _sections;
  bool _loading = false;
  String? _error;
  String _submitted = '';
  List<SearchHistoryItem> _history = const <SearchHistoryItem>[];
  LocalDatabase? _database;
  SettingsStore? _settings;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final SettingsStore settings = SonoraScope.of(context).settings;
    if (!identical(settings, _settings)) {
      _settings?.removeListener(_onSettingsChanged);
      _settings = settings..addListener(_onSettingsChanged);
    }
    final database = SonoraScope.of(context).database;
    if (!identical(database, _database)) {
      _database = database;
      _refreshHistory();
    }
  }

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _settings?.removeListener(_onSettingsChanged);
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    // Endpoint berubah: buang hasil dari host lama.
    _generation++;
    setState(() {
      _sections = null;
      _error = null;
      _loading = false;
      _submitted = '';
    });
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _generation++;
    setState(() {
      _sections = null;
      _error = null;
      _loading = false;
      _submitted = '';
    });
  }

  Future<void> _run(String query) async {
    final String trimmed = query.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (trimmed.isEmpty) return;
    final SonoraScope scope = SonoraScope.of(context);
    if (!scope.settings.isConfigured) return;
    unawaited(
      _database?.recordSearch(trimmed).then((_) => _refreshHistory()),
    );
    final int generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _submitted = trimmed;
    });
    try {
      final List<MusicSection> sections =
          await scope.api.search(trimmed, filter: _filter);
      if (!mounted || generation != _generation) return;
      setState(() {
        _sections = sections;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = _message(error);
        _loading = false;
      });
    }
  }

  void _selectFilter(String? id) {
    if (_filter == id) return;
    setState(() => _filter = id);
    if (_submitted.isNotEmpty) _run(_submitted);
  }

  void _clear() {
    _debounce?.cancel();
    _generation++;
    _controller.clear();
    setState(() {
      _sections = null;
      _error = null;
      _loading = false;
      _submitted = '';
    });
    _refreshHistory();
    _focus.requestFocus();
  }

  Future<void> _refreshHistory() async {
    final items = await _database?.getRecentSearches(limit: 30) ??
        const <SearchHistoryItem>[];
    if (mounted) setState(() => _history = items);
  }

  Future<void> _deleteHistory(String query) async {
    await _database?.deleteSearch(query);
    await _refreshHistory();
  }

  Future<void> _clearHistory() async {
    await _database?.clearSearchHistory();
    await _refreshHistory();
  }

  String _message(Object error) =>
      error is SonoraApiException ? error.message : error.toString();

  @override
  Widget build(BuildContext context) {
    final SonoraScope scope = SonoraScope.of(context);
    return ListenableBuilder(
      listenable: scope.settings,
      builder: (BuildContext context, Widget? _) {
        final ColorScheme scheme = context.scheme;
        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(kSpaceLg, kSpaceLg, kSpaceLg, kSpaceSm),
                  child: TextField(
                    controller: _controller,
                    focusNode: _focus,
                    enabled: scope.settings.isConfigured,
                    textInputAction: TextInputAction.search,
                    onChanged: _onChanged,
                    onSubmitted: _run,
                    decoration: InputDecoration(
                       hintText: 'Apa yang ingin kamu dengarkan?',
                       prefixIcon: _focus.hasFocus
                           ? IconButton(
                               icon: const Icon(Icons.arrow_back_rounded),
                               onPressed: () => _focus.unfocus(),
                             )
                           : const Icon(Icons.search_rounded),
                      suffixIcon: _controller.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Hapus pencarian',
                              icon: const Icon(Icons.close_rounded),
                              onPressed: _clear,
                            ),
                      border: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(kRadiusXl)),
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: kSpaceSm),
                    ),
                  ),
                ),
                SizedBox(
                  height: 52,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: kSpaceLg),
                    itemCount: kSearchFilters.length,
                    separatorBuilder: (_, _) => const SizedBox(width: kSpaceSm),
                    itemBuilder: (BuildContext context, int index) {
                      final option = kSearchFilters[index];
                      return Center(
                        child: ChoiceChip(
                          label: Text(option.label),
                          selected: _filter == option.id,
                          onSelected: (_) => _selectFilter(option.id),
                        ),
                      );
                    },
                  ),
                ),
                const Divider(height: 1),
                Expanded(child: _body(scope)),
              ],
            ),
          ),
          backgroundColor: scheme.surface,
        );
      },
    );
  }

  Widget _body(SonoraScope scope) {
    if (!scope.settings.isConfigured) {
      return EmptyState(
        icon: Icons.settings_ethernet_rounded,
        title: 'Proxy belum diatur',
        message: 'Atur alamat proxy di Pengaturan sebelum mencari musik.',
        action: FilledButton.icon(
          onPressed: () => scope.tabs.goTo(AppTabs.settings),
          icon: const Icon(Icons.settings_rounded),
          label: const Text('Buka Pengaturan'),
        ),
      );
    }
    if (_loading) return const LoadingState(label: 'Mencari\u2026');
    if (_error != null) return ErrorState(message: _error!, onRetry: () => _run(_submitted));
    if (_sections == null) {
      return ListView(
        padding: const EdgeInsets.only(bottom: kSpaceXxl),
        children: <Widget>[
          _SearchHistory(
            items: _history,
            onSelect: (String value) {
              _controller.text = value;
              _run(value);
            },
            onDelete: _deleteHistory,
            onClear: _clearHistory,
          ),
        ],
      );
    }
    final List<MusicSection> visible = _sections!
        .where((MusicSection section) => section.items.isNotEmpty)
        .toList(growable: false);
    if (visible.isEmpty) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        title: 'Tidak ada hasil',
        message: 'Tidak ditemukan hasil untuk \u201c$_submitted\u201d.',
      );
    }
    return _SearchResults(sections: visible);
  }
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({required this.sections});

  final List<MusicSection> sections;

  @override
  Widget build(BuildContext context) {
    final PlayerActions actions = PlayerActions.of(context);
    final PlayerController player = SonoraScope.of(context).player;
    final List<MusicItem> songs = <MusicItem>[
      for (final MusicSection section in sections)
        for (final MusicItem item in section.items)
          if (item.isPlayable) item,
    ];
    final List<MusicSection> shelves = sections
        .where((MusicSection section) =>
            section.items.isNotEmpty && section.items.every((MusicItem i) => !i.isPlayable))
        .toList(growable: false);
    return ListenableBuilder(
      listenable: player,
      builder: (BuildContext context, Widget? _) => ListView(
        padding: const EdgeInsets.only(bottom: kSpaceXxl),
        children: <Widget>[
          if (songs.isNotEmpty) SectionHeader(title: 'Lagu & video'),
          for (final MusicItem item in songs)
            SongRow(
              item: item,
              active: actions.activeVideoId == item.videoId,
              onPlay: () => actions.play(item),
              onAddToQueue: (bool next) => actions.addToQueue(item, next: next),
            ),
          for (final MusicSection section in shelves) ...<Widget>[
            SectionHeader(title: section.title.isEmpty ? 'Lainnya' : section.title),
            for (final MusicItem item in section.items)
              _SearchBrowseRow(
                item: item,
                onOpen: () => actions.open(item),
              ),
          ],
        ],
      ),
    );
  }
}

/// Baris vertikal untuk hasil album, artis, dan playlist yang dapat dibuka.
class _SearchBrowseRow extends StatelessWidget {
  const _SearchBrowseRow({required this.item, required this.onOpen});

  final MusicItem item;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final String subtitle = artistOf(item).isNotEmpty
        ? artistOf(item)
        : (item.subtitle ?? item.type);
    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: kSpaceLg,
          vertical: kSpaceSm,
        ),
        child: Row(
          children: <Widget>[
            CoverArt(
              url: item.thumbnail,
              size: 56,
              circle: item.type.toLowerCase() == 'artist',
              radius: kRadiusSm,
              icon: item.type.toLowerCase() == 'artist'
                  ? Icons.person_rounded
                  : Icons.album_rounded,
            ),
            const SizedBox(width: kSpaceMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.bodySmall?.copyWith(
                      color: context.scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}

class _SearchHistory extends StatelessWidget {
  const _SearchHistory({required this.items, required this.onSelect, required this.onDelete, required this.onClear});
  final List<SearchHistoryItem> items;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onDelete;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: kSpaceXxl),
        child: Column(
          children: <Widget>[
          SectionHeader(
            title: 'Riwayat pencarian',
            trailing: items.isEmpty
                ? null
                : TextButton(onPressed: onClear, child: const Text('Hapus semua')),
          ),
          if (items.isEmpty)
            const EmptyState(
              icon: Icons.search_rounded,
              title: 'Belum ada pencarian',
              message: 'Pencarian lagu, album, artis, atau playlist akan muncul di sini.',
            ),
          for (final item in items)
            ListTile(
              leading: const Icon(Icons.history_rounded),
              title: Text(item.query, style: context.texts.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
              trailing: IconButton(
                tooltip: 'Hapus',
                icon: const Icon(Icons.close_rounded),
                onPressed: () => onDelete(item.query),
              ),
              onTap: () => onSelect(item.query),
            ),
          ],
        ),
      );
}
