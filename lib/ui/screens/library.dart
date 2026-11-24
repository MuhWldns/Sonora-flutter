/// Layar Koleksi pengguna: manajemen playlist, album & artis tersimpan,
/// serta statistik wawasan mendengarkan (Nocturne Audio).
library;

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/local_database.dart';
import '../../data/music_models.dart';
import '../app_scope.dart';
import '../player_actions.dart';
import '../theme.dart';
import '../widgets/common.dart';

enum _LibrarySort { recent, added, alphabet, creator }

enum _StatsPeriod {
  week(Duration(days: 7), '1 Minggu'),
  month(Duration(days: 30), '1 Bulan'),
  threeMonths(Duration(days: 90), '3 Bulan'),
  sixMonths(Duration(days: 180), '6 Bulan'),
  year(Duration(days: 365), '1 Tahun'),
  all(null, 'Semua');

  const _StatsPeriod(this.duration, this.label);
  final Duration? duration;
  final String label;

  int get startTimestamp {
    if (duration == null) return 0;
    return DateTime.now().subtract(duration!).millisecondsSinceEpoch;
  }
}

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  String _filter = 'Playlist';
  _LibrarySort _sort = _LibrarySort.recent;
  _StatsPeriod _statsPeriod = _StatsPeriod.month;
  bool _grid = false;

  static const List<String> _filters = <String>[
    'Playlist',
    'Album',
    'Artis',
    'Statistik',
  ];

  List<Map<String, Object?>> _playlists = <Map<String, Object?>>[];
  List<MusicItem> _savedAlbums = <MusicItem>[];
  List<MusicItem> _savedArtists = <MusicItem>[];
  ListeningStats? _stats;
  bool _loading = true;
  bool _loadingStats = false;
  AppTabController? _tabs;
  ChangeNotifier? _auth;
  bool _loadingPersonal = false;
  List<MusicItem> _liked = const <MusicItem>[];
  List<MusicItem> _history = const <MusicItem>[];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tabs = SonoraScope.of(context).tabs;
    if (!identical(tabs, _tabs)) {
      _tabs?.removeListener(_onTabChanged);
      _tabs = tabs..addListener(_onTabChanged);
    }
    final ChangeNotifier auth = SonoraScope.of(context).auth;
    if (!identical(auth, _auth)) {
      _auth?.removeListener(_onAuthChanged);
      _auth = auth..addListener(_onAuthChanged);
    }
    if (_playlists.isEmpty && _loading) _load();
    if (SonoraScope.of(context).auth.signedIn) _loadPersonal();
  }

  @override
  void dispose() {
    _tabs?.removeListener(_onTabChanged);
    _auth?.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabs?.index == AppTabs.library) {
      _load();
      if (_filter == 'Statistik') _loadStats();
      // Segarkan seksi personal juga (berfungsi sebagai coba lagi).
      if (SonoraScope.of(context).auth.signedIn) _loadPersonal();
    }
  }

  Future<void> _load() async {
    final db = SonoraScope.of(context).database;
    if (db == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
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

  Future<void> _loadStats() async {
    final db = SonoraScope.of(context).database;
    if (db == null) return;
    setState(() => _loadingStats = true);
    final stats = await db.getListeningStats(_statsPeriod.startTimestamp);
    if (!mounted) return;
    setState(() {
      _stats = stats;
      _loadingStats = false;
    });
  }

  /// Dipanggil saat status sesi YouTube Music berubah: muat seksi personal
  /// saat masuk, kosongkan saat keluar.
  void _onAuthChanged() {
    if (!mounted) return;
    if (SonoraScope.of(context).auth.signedIn) {
      _loadPersonal();
    } else {
      setState(() {
        _liked = const <MusicItem>[];
        _history = const <MusicItem>[];
        _loadingPersonal = false;
      });
    }
  }

  /// Memuat lagu disukai + riwayat dari YouTube Music secara lazy.
  /// Daftar kosong berarti gagal/kosong — seksi disembunyikan, tanpa crash.
  Future<void> _loadPersonal() async {
    if (_loadingPersonal) return;
    if (!SonoraScope.of(context).auth.signedIn) return;
    setState(() => _loadingPersonal = true);
    try {
      final scope = SonoraScope.of(context);
      final results =
          await Future.wait<List<MusicItem>>(<Future<List<MusicItem>>>[
        scope.ytService.fetchLiked(),
        scope.ytService.fetchHistory(),
      ]);
      if (!mounted) return;
      if (!SonoraScope.of(context).auth.signedIn) return;
      setState(() {
        _liked = results[0];
        _history = results[1];
        _loadingPersonal = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _liked = const <MusicItem>[];
        _history = const <MusicItem>[];
        _loadingPersonal = false;
      });
    }
  }

  /// Sliver seksi personal (Disukai/Riwayat) memakai pola rak yang ada.
  /// Kosong/gagal → seksi disembunyikan seluruhnya.
  List<Widget> _personalSectionSlivers({
    required String title,
    required bool loading,
    required List<MusicItem> items,
  }) {
    if (!loading && items.isEmpty) return const <Widget>[];
    return <Widget>[
      SliverToBoxAdapter(child: SectionHeader(title: title)),
      if (loading)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: kSpaceLg,
              vertical: kSpaceLg,
            ),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        )
      else
        SliverToBoxAdapter(
          child: MusicShelf(
            items: items,
            onOpen: (MusicItem item) => PlayerActions.of(context).play(item),
          ),
        ),
    ];
  }

  String get _sortLabel => switch (_sort) {
    _LibrarySort.recent => 'Terakhir',
    _LibrarySort.added => 'Baru ditambahkan',
    _LibrarySort.alphabet => 'Abjad',
    _LibrarySort.creator => 'Kreator',
  };

  List<MusicItem> get _visible {
    switch (_filter) {
      case 'Album':
        return _savedAlbums;
      case 'Artis':
        return _savedArtists;
      case 'Playlist':
      default:
        return <MusicItem>[
          for (final row in _playlists)
            MusicItem(
              type: 'playlist',
              title: row['name'] as String? ?? 'Playlist',
              subtitle: '${row['track_count'] ?? 0} lagu',
              thumbnail: row['artwork_url'] as String?,
              localThumbnailPath: row['artwork_path'] as String?,
              playlistId: row['id'] as String,
            ),
        ];
    }
  }

  Future<void> _createPlaylist() async {
    final db = SonoraScope.of(context).database;
    if (db == null) {
      showSonoraSnack(context, 'Penyimpanan lokal tidak tersedia');
      return;
    }
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
    await db.createPlaylist(
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
    final db = SonoraScope.of(context).database;
    if (db == null) {
      return const Scaffold(
        body: Center(
          child: EmptyState(
            icon: Icons.error_outline_rounded,
            title: 'Basis Data Tidak Tersedia',
            message:
                'Penyimpanan lokal tidak dapat diakses pada perangkat ini.',
          ),
        ),
      );
    }

    final isStats = _filter == 'Statistik';
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
                    if (!isStats) ...<Widget>[
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
                  itemBuilder: (_, int index) {
                    final label = _filters[index];
                    final active = _filter == label;
                    return ChoiceChip(
                      label: Text(label),
                      selected: active,
                      onSelected: (_) {
                        setState(() => _filter = label);
                        if (label == 'Statistik') _loadStats();
                      },
                    );
                  },
                ),
              ),
            ),
            if (SonoraScope.of(context).auth.signedIn) ...<Widget>[
              ..._personalSectionSlivers(
                title: 'Disukai',
                loading: _loadingPersonal && _liked.isEmpty,
                items: _liked,
              ),
              ..._personalSectionSlivers(
                title: 'Riwayat',
                loading: _loadingPersonal && _history.isEmpty,
                items: _history,
              ),
            ],
            if (isStats) ...<Widget>[
              SliverToBoxAdapter(
                child: _StatsView(
                  period: _statsPeriod,
                  stats: _stats,
                  loading: _loadingStats,
                  onPeriodChanged: (period) {
                    setState(() => _statsPeriod = period);
                    _loadStats();
                  },
                ),
              ),
            ] else ...<Widget>[
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
                      _LibraryListItem(item: items[index], onRefresh: _load),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Tampilan statistik mendengarkan pengguna dengan desain kartu estetik (Nocturne Audio).
class _StatsView extends StatelessWidget {
  const _StatsView({
    required this.period,
    required this.stats,
    required this.loading,
    required this.onPeriodChanged,
  });

  final _StatsPeriod period;
  final ListeningStats? stats;
  final bool loading;
  final ValueChanged<_StatsPeriod> onPeriodChanged;

  String _formatMinutes(int minutes) {
    if (minutes >= 60) {
      final hours = minutes ~/ 60;
      final remaining = minutes % 60;
      if (remaining == 0) return '$hours Jam';
      return '$hours Jam $remaining Mnt';
    }
    return '$minutes Menit';
  }

  void _playTrack(BuildContext context, TopTrackStat track) {
    final item = MusicItem(
      type: 'song',
      title: track.title,
      artist: track.artist,
      thumbnail: track.thumbnail,
      videoId: track.videoId,
    );
    PlayerActions.of(context).play(item);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final sonora = context.sonora;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kSpaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: kSpaceMd),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _StatsPeriod.values.map((p) {
                final selected = p == period;
                return Padding(
                  padding: const EdgeInsets.only(right: kSpaceSm),
                  child: FilterChip(
                    label: Text(p.label),
                    selected: selected,
                    onSelected: (_) => onPeriodChanged(p),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: kSpaceLg),
          if (loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(kSpaceXl),
                child: CircularProgressIndicator(),
              ),
            )
          else if (stats == null ||
              (stats!.totalMinutes == 0 && stats!.totalPlays == 0))
            const EmptyState(
              icon: Icons.insights_rounded,
              title: 'Belum Ada Statistik',
              message:
                  'Dengarkan lagu favoritmu minimal 15 detik untuk mulai mencatat wawasan musik riil.',
            )
          else ...<Widget>[
            // Hero Card: Waktu Mendengarkan
            GlassContainer(
              padding: const EdgeInsets.all(kSpaceLg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Container(
                        padding: const EdgeInsets.all(kSpaceSm),
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.headphones_rounded,
                          size: 20,
                          color: scheme.primary,
                        ),
                      ),
                      const SizedBox(width: kSpaceSm),
                      Text(
                        'Total Waktu Mendengarkan',
                        style: context.texts.labelLarge?.copyWith(
                          color: sonora.accentText,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: kSpaceSm,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(kRadiusXl),
                        ),
                        child: Text(
                          period.label,
                          style: context.texts.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: kSpaceLg),
                  Text(
                    _formatMinutes(stats!.totalMinutes),
                    style: context.texts.headlineLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: scheme.primary,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Akumulasi durasi pemutaran riil (min. 15 detik)',
                    style: context.texts.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: kSpaceMd),

            // Bento Metric Row: Total Plays & Lagu Unik
            Row(
              children: <Widget>[
                Expanded(
                  child: GlassContainer(
                    padding: const EdgeInsets.all(kSpaceMd),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Icon(
                          Icons.play_circle_fill_rounded,
                          size: 24,
                          color: scheme.onSurface,
                        ),
                        const SizedBox(height: kSpaceSm),
                        Text(
                          '${stats!.totalPlays}',
                          style: context.texts.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: scheme.onSurface,
                          ),
                        ),
                        Text(
                          'Lagu Diputar',
                          style: context.texts.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: kSpaceMd),
                Expanded(
                  child: GlassContainer(
                    padding: const EdgeInsets.all(kSpaceMd),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Icon(
                          Icons.audiotrack_rounded,
                          size: 24,
                          color: sonora.accentText,
                        ),
                        const SizedBox(height: kSpaceSm),
                        Text(
                          '${stats!.topTracks.length}',
                          style: context.texts.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: scheme.onSurface,
                          ),
                        ),
                        Text(
                          'Lagu Favorit Teratas',
                          style: context.texts.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // Top Lagu: Spotlight #1 + Grouped Card #2-#5
            if (stats!.topTracks.isNotEmpty) ...<Widget>[
              const SizedBox(height: kSpaceXl),
              const SectionHeader(title: 'Lagu Paling Sering Diputar'),
              const SizedBox(height: kSpaceSm),
              // Spotlight Card untuk Lagu #1
              () {
                final top1 = stats!.topTracks.first;
                return GlassContainer(
                  padding: const EdgeInsets.all(kSpaceMd),
                  child: Column(
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: kSpaceSm,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.primary.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(kRadiusXl),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                const Text('👑 ', style: TextStyle(fontSize: 12)),
                                Text(
                                  '#1 Teratas',
                                  style: context.texts.labelSmall?.copyWith(
                                    color: scheme.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${top1.playCount}x putar • ${top1.totalMinutes} mnt',
                            style: context.texts.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: kSpaceMd),
                      InkWell(
                        onTap: () => _playTrack(context, top1),
                        borderRadius: BorderRadius.circular(kRadiusSm),
                        child: Row(
                          children: <Widget>[
                            CoverArt(
                              url: top1.thumbnail,
                              size: 56,
                              radius: kRadiusSm,
                            ),
                            const SizedBox(width: kSpaceMd),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    top1.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: context.texts.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    top1.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: context.texts.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton.filled(
                              onPressed: () => _playTrack(context, top1),
                              icon: const Icon(Icons.play_arrow_rounded, size: 24),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }(),

              // Grouped Card untuk Lagu #2 dst.
              if (stats!.topTracks.length > 1) ...<Widget>[
                const SizedBox(height: kSpaceMd),
                GlassContainer(
                  padding: const EdgeInsets.symmetric(vertical: kSpaceSm),
                  child: Column(
                    children: <Widget>[
                      for (final (index, track) in stats!.topTracks.skip(1).indexed) ...<Widget>[
                        if (index > 0)
                          Divider(
                            height: 1,
                            indent: 56,
                            color: scheme.outlineVariant.withValues(alpha: 0.5),
                          ),
                        InkWell(
                          onTap: () => _playTrack(context, track),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: kSpaceSm,
                              horizontal: kSpaceMd,
                            ),
                            child: Row(
                              children: <Widget>[
                                SizedBox(
                                  width: 24,
                                  child: Text(
                                    '#${index + 2}',
                                    style: context.texts.titleSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                CoverArt(url: track.thumbnail, size: 44),
                                const SizedBox(width: kSpaceMd),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text(
                                        track.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: context.texts.bodyMedium?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        track.artist,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: context.texts.bodySmall?.copyWith(
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: <Widget>[
                                    Text(
                                      '${track.playCount}x',
                                      style: context.texts.labelLarge?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: sonora.accentText,
                                      ),
                                    ),
                                    Text(
                                      '${track.totalMinutes} mnt',
                                      style: context.texts.labelSmall?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],

            // Top Artis: Carousel Horizontal Cards
            if (stats!.topArtists.isNotEmpty) ...<Widget>[
              const SizedBox(height: kSpaceXl),
              const SectionHeader(title: 'Artis Teratas'),
              const SizedBox(height: kSpaceSm),
              SizedBox(
                height: 144,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: stats!.topArtists.length,
                  separatorBuilder: (_, _) => const SizedBox(width: kSpaceMd),
                  itemBuilder: (context, index) {
                    final artist = stats!.topArtists[index];
                    final isTop = index == 0;
                    return SizedBox(
                      width: 140,
                      child: GlassContainer(
                        padding: const EdgeInsets.all(kSpaceMd),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Stack(
                              alignment: Alignment.bottomRight,
                              children: <Widget>[
                                CircleAvatar(
                                  radius: 26,
                                  backgroundColor: isTop
                                      ? scheme.primary.withValues(alpha: 0.2)
                                      : scheme.surfaceContainerHighest,
                                  child: Icon(
                                    Icons.person_rounded,
                                    size: 30,
                                    color: isTop ? scheme.primary : scheme.onSurface,
                                  ),
                                ),
                                if (isTop)
                                  Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: BoxDecoration(
                                      color: scheme.primary,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Text('👑', style: TextStyle(fontSize: 10)),
                                  ),
                              ],
                            ),
                            const SizedBox(height: kSpaceSm),
                            Text(
                              artist.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: context.texts.labelLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${artist.playCount}x • ${artist.totalMinutes} mnt',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: context.texts.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: kSpaceXxl),
          ],
        ],
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
    borderRadius: BorderRadius.circular(kRadiusMd),
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
  const _LibraryListItem({required this.item, required this.onRefresh});
  final MusicItem item;
  final VoidCallback onRefresh;

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
        if (db == null) return;
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
            onRefresh();
          }
        } else if (value == 'delete') {
          await db.deletePlaylist(item.playlistId!);
          onRefresh();
        }
      },
      itemBuilder: (_) => <PopupMenuEntry<String>>[
        if (item.playlistId != 'favorites') ...<PopupMenuEntry<String>>[
          const PopupMenuItem(value: 'edit', child: Text('Edit nama & deskripsi')),
          const PopupMenuItem(value: 'delete', child: Text('Hapus playlist')),
        ],
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
    final db = SonoraScope.of(context).database;
    _tracks = db?.getPlaylistTracks(widget.id) ?? Future.value(<MusicItem>[]);
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    final db = SonoraScope.of(context).database;
    final tracks =
        db?.getPlaylistTracks(widget.id) ?? Future.value(<MusicItem>[]);
    setState(() => _tracks = tracks);
  }

  Future<void> _loadRecommendations() async {
    if (_loadingRecommendations) return;
    setState(() => _loadingRecommendations = true);
    final scope = SonoraScope.of(context);
    final history =
        await scope.database?.getRecentSearches(limit: 30) ??
        <SearchHistoryItem>[];
    final seen = <String>{};
    final found = <MusicItem>[];
    for (final search in history) {
      try {
        List<MusicItem> results;
        if (scope.settings.isConfigured) {
          try {
            final sections = await scope.api.search(search.query);
            results = sections.expand((s) => s.items).toList();
          } catch (_) {
            results = await scope.ytService.search(search.query);
          }
        } else {
          results = await scope.ytService.search(search.query);
        }
        for (final item in results) {
          final id = item.videoId;
          if (id != null && id.isNotEmpty && seen.add(id)) found.add(item);
        }
      } catch (_) {}
      if (found.length >= 30) break;
    }
    if (found.isEmpty) {
      try {
        List<MusicItem> results;
        if (scope.settings.isConfigured) {
          try {
            final sections = await scope.api.home();
            results = sections.expand((s) => s.items).toList();
          } catch (_) {
            results = await scope.ytService.getTrending();
          }
        } else {
          results = await scope.ytService.getTrending();
        }
        for (final item in results) {
          final id = item.videoId;
          if (id != null && id.isNotEmpty && seen.add(id)) found.add(item);
        }
      } catch (_) {}
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
    final scope = SonoraScope.of(context);
    try {
      List<MusicItem> results;
      if (scope.settings.isConfigured) {
        try {
          final sections = await scope.api.search(trimmed);
          results = sections.expand((s) => s.items).toList();
        } catch (_) {
          results = await scope.ytService.search(trimmed);
        }
      } else {
        results = await scope.ytService.search(trimmed);
      }
      if (!mounted) return;
      final items = <MusicItem>[];
      final seen = <String>{};
      for (final item in results) {
        if (item.videoId != null && seen.add(item.videoId!)) items.add(item);
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
    if (db == null) return;
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
    if (db == null) return;
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
            if (db == null) return;
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
            if (widget.id != 'favorites') ...<PopupMenuEntry<String>>[
              const PopupMenuItem(value: 'edit', child: Text('Edit playlist')),
              const PopupMenuItem(value: 'delete', child: Text('Hapus playlist')),
            ],
            const PopupMenuItem(value: 'add', child: Text('Tambah lagu')),
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
              future: SonoraScope.of(context).database?.getPlaylists() ??
                  Future.value(<Map<String, Object?>>[]),
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
              leading: CircleAvatar(
                backgroundColor: context.scheme.surfaceContainerHighest,
                child: Icon(Icons.add_rounded, color: context.scheme.primary),
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
                    hintText: 'Cari lagu untuk ditambahkan',
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
                      final db = SonoraScope.of(context).database;
                      if (widget.id == 'favorites') {
                        await db?.removeFavorite(id);
                      } else {
                        await db?.removeFromPlaylist(widget.id, id);
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
                        icon: Icon(
                          Icons.favorite_rounded,
                          color: context.sonora.accentText,
                        ),
                        onPressed: () async {
                          await SonoraScope.of(
                            context,
                          ).database?.removeFavorite(item.videoId ?? '');
                          await _refresh();
                        },
                      )
                    : IconButton(
                        icon: const Icon(Icons.remove_circle_outline_rounded),
                        onPressed: () async {
                          await SonoraScope.of(
                            context,
                          ).database?.removeFromPlaylist(
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
    future: SonoraScope.of(context).database?.getPlaylistTracks(id) ??
        Future.value(<MusicItem>[]),
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
