/// Layar Home: feed personal dari proxy dan akses cepat lokal pengguna (Nocturne).
library;

import 'package:flutter/material.dart';

import '../../data/music_models.dart';
import '../../data/settings_store.dart';
import '../../data/sonora_api.dart';
import '../app_scope.dart';
import '../player_actions.dart';
import 'library.dart';
import '../theme.dart';
import '../widgets/common.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<MusicSection>? _sections;
  String? _error;
  int _generation = 0;
  SettingsStore? _settings;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final SettingsStore settings = SonoraScope.of(context).settings;
    if (!identical(settings, _settings)) {
      _settings?.removeListener(_onSettingsChanged);
      _settings = settings..addListener(_onSettingsChanged);
      if (_sections == null && _error == null) _load();
    }
  }

  @override
  void dispose() {
    _settings?.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    _load();
  }

  Future<void> _load() async {
    final SonoraScope scope = SonoraScope.of(context);
    final int generation = ++_generation;
    setState(() => _error = null);
    try {
      List<MusicSection> sections;
      if (scope.settings.isConfigured) {
        try {
          sections = await scope.api.home();
        } catch (_) {
          final List<MusicItem> trending = await scope.ytService.getTrending();
          sections = <MusicSection>[
            MusicSection(title: 'Trending & Populer', items: trending),
          ];
        }
      } else {
        final List<MusicItem> trending = await scope.ytService.getTrending();
        sections = <MusicSection>[
          MusicSection(title: 'Trending & Populer', items: trending),
        ];
      }
      if (!mounted || generation != _generation) return;
      setState(() => _sections = sections);
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = error is SonoraApiException
            ? error.message
            : error is SonoraConfigurationException
            ? error.message
            : 'Gagal memuat beranda.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final SonoraScope scope = SonoraScope.of(context);
    final ColorScheme scheme = context.scheme;
    return ListenableBuilder(
      listenable: scope.settings,
      builder: (BuildContext context, Widget? _) {
        final Widget body;
        if (_error != null && _sections == null) {
          body = ErrorState(message: _error!, onRetry: _load);
        } else if (_sections == null) {
          body = const SkeletonHomeFeed();
        } else {
          body = RefreshIndicator(
            onRefresh: _load,
            child: _HomeFeed(sections: _sections!),
          );
        }
        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    kSpaceLg,
                    kSpaceLg,
                    kSpaceLg,
                    kSpaceSm,
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          'Sonora',
                          style: context.texts.displaySmall,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Muat ulang',
                        icon: const Icon(Icons.refresh_rounded),
                        onPressed: scope.settings.isConfigured ? _load : null,
                      ),
                    ],
                  ),
                ),
                Expanded(child: body),
              ],
            ),
          ),
          backgroundColor: scheme.surface,
        );
      },
    );
  }
}

/// Beranda menyajikan akses personal lokal, rekomendasi harian, dan rak proxy.
class _HomeFeed extends StatelessWidget {
  const _HomeFeed({required this.sections});

  final List<MusicSection> sections;

  @override
  Widget build(BuildContext context) {
    final actions = PlayerActions.of(context);
    final items = <MusicItem>[for (final section in sections) ...section.items];
    final featured = items.isEmpty ? null : items.first;
    final shelves = sections
        .where((s) => s.items.isNotEmpty)
        .toList(growable: false);
    final db = SonoraScope.of(context).database;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: kSpaceXxl),
      children: <Widget>[
        const _QuickAccessSection(),
        if (db != null)
          FutureBuilder<List<Map<String, Object?>>>(
            future: db.getPlaylists(),
            builder: (context, snapshot) {
              final playlists =
                  snapshot.data ?? const <Map<String, Object?>>[];
              if (playlists.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const SectionHeader(title: 'Playlist kamu'),
                  SizedBox(
                    height: 174,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: kSpaceLg),
                      itemCount: playlists.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(width: kSpaceMd),
                      itemBuilder: (context, index) {
                        final row = playlists[index];
                        return SizedBox(
                          width: 136,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              InkWell(
                                onTap: () => Navigator.of(context).push<void>(
                                  MaterialPageRoute<void>(
                                    builder: (_) => PlaylistDetailScreen(
                                      id: row['id'] as String,
                                      name:
                                          row['name'] as String? ?? 'Playlist',
                                    ),
                                  ),
                                ),
                                borderRadius: BorderRadius.circular(kRadiusMd),
                                child: _PlaylistCollage(
                                  id: row['id'] as String,
                                  size: 132,
                                  url: row['artwork_url'] as String?,
                                  path: row['artwork_path'] as String?,
                                ),
                              ),
                              const SizedBox(height: kSpaceXs),
                              Text(
                                row['name'] as String? ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.texts.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                'Kamu',
                                style: context.texts.bodySmall?.copyWith(
                                  color: context.scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        const _DailyRecommendations(),
        const _RecentListening(),
        if (featured != null)
          _FeaturedRelease(
            item: featured,
            onPlay: featured.isPlayable ? () => actions.play(featured) : null,
          ),
        for (int index = 0; index < shelves.length; index++)
          _HomeShelf(
            section: shelves[index],
            index: index,
            onOpen: actions.open,
          ),
      ],
    );
  }
}

class _QuickAccessSection extends StatelessWidget {
  const _QuickAccessSection();

  @override
  Widget build(BuildContext context) {
    final db = SonoraScope.of(context).database;
    if (db == null) return const SizedBox.shrink();

    return FutureBuilder<List<Object>>(
      future: Future.wait<Object>(<Future<Object>>[
        db.getPlaylists(),
        db.getRecentPlaybacks(limit: 8),
      ]),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final playlists = snapshot.data![0] as List<Map<String, Object?>>;
        final recent = snapshot.data![1] as List<MusicItem>;
        if (playlists.isEmpty && recent.isEmpty) return const SizedBox.shrink();
        final cards = <Widget>[
          for (final row in playlists.take(4))
            _QuickCard(
              item: MusicItem(
                type: 'playlist',
                title: row['name'] as String? ?? 'Playlist',
                thumbnail: row['artwork_url'] as String?,
                localThumbnailPath: row['artwork_path'] as String?,
                playlistId: row['id'] as String?,
              ),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => PlaylistDetailScreen(
                    id: row['id'] as String,
                    name: row['name'] as String? ?? 'Playlist',
                  ),
                ),
              ),
            ),
          for (final item in recent.take(8 - playlists.take(4).length))
            _QuickCard(
              item: item,
              onTap: () => PlayerActions.of(context).play(item),
            ),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SectionHeader(title: 'Akses cepat'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: kSpaceLg),
              child: GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                crossAxisSpacing: kSpaceSm,
                mainAxisSpacing: kSpaceSm,
                childAspectRatio: 3.1,
                children: cards,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _QuickCard extends StatelessWidget {
  const _QuickCard({required this.item, required this.onTap});

  final MusicItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(kRadiusSm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: <Widget>[
            if (item.type == 'playlist' && item.playlistId != null)
              _PlaylistCollage(
                id: item.playlistId!,
                size: 52,
                url: item.thumbnail,
                path: item.localThumbnailPath,
              )
            else
              CoverArt(
                url: item.thumbnail,
                localPath: item.localThumbnailPath,
                size: 52,
                radius: 0,
              ),
            const SizedBox(width: kSpaceSm),
            Expanded(
              child: Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.texts.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: kSpaceSm),
          ],
        ),
      ),
    );
  }
}

class _DailyRecommendations extends StatelessWidget {
  const _DailyRecommendations();

  @override
  Widget build(BuildContext context) {
    final db = SonoraScope.of(context).database;
    if (db == null) return const SizedBox.shrink();

    return FutureBuilder<List<MusicItem>>(
      future: db.getPlaybacksSince(
        DateTime.now().subtract(const Duration(days: 1)).millisecondsSinceEpoch,
      ),
      builder: (context, snapshot) {
        final heard = snapshot.data ?? const <MusicItem>[];
        if (heard.isEmpty) return const SizedBox.shrink();
        final counts = <String, int>{};
        for (final item in heard) {
          for (final artist in item.artist.split(',')) {
            final name = artist.trim();
            if (name.isNotEmpty) {
              counts.update(name, (count) => count + 1, ifAbsent: () => 1);
            }
          }
        }
        if (counts.isEmpty) return const SizedBox.shrink();
        final topArtist = counts.entries
            .reduce((a, b) => a.value >= b.value ? a : b)
            .key;
        return FutureBuilder<List<MusicSection>>(
          future: SonoraScope.of(context).api.search(topArtist),
          builder: (context, recommendations) {
            final matches = recommendations.data ?? const <MusicSection>[];
            final heardIds = heard
                .map((item) => item.videoId)
                .whereType<String>()
                .toSet();
            final items = <MusicItem>[];
            for (final section in matches) {
              for (final item in section.items) {
                if ((item.type == 'artist' || item.type == 'album') &&
                    !heardIds.contains(item.videoId)) {
                  items.add(item);
                }
              }
            }
            if (items.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SectionHeader(
                  title: 'Rekomendasi harian',
                  trailing: Text(
                    'Dari $topArtist',
                    style: context.texts.bodySmall,
                  ),
                ),
                SizedBox(
                  height: 214,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: kSpaceLg),
                    itemCount: items.take(10).length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(width: kSpaceMd),
                    itemBuilder: (_, index) => ShelfCard(
                      item: items[index],
                      onOpen: () =>
                          PlayerActions.of(context).open(items[index]),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _RecentListening extends StatelessWidget {
  const _RecentListening();

  @override
  Widget build(BuildContext context) {
    final db = SonoraScope.of(context).database;
    if (db == null) return const SizedBox.shrink();

    return FutureBuilder<List<MusicItem>>(
      future: db.getRecentPlaybacks(limit: 10),
      builder: (context, snapshot) {
        final tracks = snapshot.data ?? const <MusicItem>[];
        if (tracks.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SectionHeader(title: 'Terakhir diputar'),
            SizedBox(
              height: 214,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: kSpaceLg),
                itemCount: tracks.length,
                separatorBuilder: (_, _) => const SizedBox(width: kSpaceMd),
                itemBuilder: (_, index) => ShelfCard(
                  item: tracks[index],
                  onOpen: () => PlayerActions.of(context).play(tracks[index]),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PlaylistCollage extends StatelessWidget {
  const _PlaylistCollage({
    required this.id,
    required this.size,
    this.url,
    this.path,
  });

  final String id;
  final double size;
  final String? url;
  final String? path;

  @override
  Widget build(BuildContext context) {
    final db = SonoraScope.of(context).database;
    return FutureBuilder<List<MusicItem>>(
      future: db?.getPlaylistTracks(id) ?? Future.value(<MusicItem>[]),
      builder: (context, snapshot) {
        final tracks = snapshot.data ?? const <MusicItem>[];
        if (tracks.isEmpty) {
          return CoverArt(
            url: url,
            localPath: path,
            size: size,
            icon: id == 'favorites'
                ? Icons.favorite_rounded
                : Icons.queue_music_rounded,
          );
        }
        final art = tracks.take(4).toList(growable: false);
        return ClipRRect(
          borderRadius: BorderRadius.circular(kRadiusMd),
          child: SizedBox(
            width: size,
            height: size,
            child: Column(
              children: <Widget>[
                Expanded(
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: CoverArt(
                          url: art[0 % art.length].thumbnail,
                          size: size / 2,
                          radius: 0,
                        ),
                      ),
                      Expanded(
                        child: CoverArt(
                          url: art[1 % art.length].thumbnail,
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
                          url: art[2 % art.length].thumbnail,
                          size: size / 2,
                          radius: 0,
                        ),
                      ),
                      Expanded(
                        child: CoverArt(
                          url: art[3 % art.length].thumbnail,
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
}

class _FeaturedRelease extends StatelessWidget {
  const _FeaturedRelease({required this.item, required this.onPlay});

  final MusicItem item;
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(kSpaceLg, kSpaceMd, kSpaceLg, 0),
      child: Container(
        padding: const EdgeInsets.all(kSpaceMd),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(kRadiusLg),
        ),
        child: Row(
          children: <Widget>[
            CoverArt(url: item.thumbnail, size: 132, radius: kRadiusMd),
            const SizedBox(width: kSpaceMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      CoverArt(url: item.thumbnail, size: 24, circle: true),
                      const SizedBox(width: kSpaceXs),
                      Expanded(
                        child: Text(
                          'Rilis baru dari ${item.artist.isEmpty ? 'Sonora' : item.artist}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.texts.labelMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: kSpaceSm),
                  Text(
                    item.type.isEmpty ? 'Rilis baru' : item.type,
                    style: context.texts.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.titleMedium,
                  ),
                  Text(
                    item.artist.isEmpty ? (item.subtitle ?? '') : item.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: <Widget>[
                        IconButton.filled(
                          onPressed: onPlay,
                          icon: const Icon(Icons.play_arrow_rounded),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeShelf extends StatelessWidget {
  const _HomeShelf({
    required this.section,
    required this.index,
    required this.onOpen,
  });

  final MusicSection section;
  final int index;
  final void Function(MusicItem) onOpen;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      SectionHeader(title: _shelfTitle(section.title, index)),
      SizedBox(
        height: 214,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: kSpaceLg),
          itemCount: section.items.length,
          separatorBuilder: (_, _) => const SizedBox(width: kSpaceMd),
          itemBuilder: (_, int i) => ShelfCard(
            item: section.items[i],
            onOpen: () => onOpen(section.items[i]),
          ),
        ),
      ),
    ],
  );
}

String _shelfTitle(String title, int index) {
  final normalized = title.trim().toLowerCase();
  if (normalized == 'quick picks' || normalized == 'quick pick') {
    return 'Rekomendasi harian';
  }
  if (title.trim().isEmpty) {
    return index == 0 ? 'Playlist kamu' : 'Rekomendasi harian';
  }
  return title;
}
