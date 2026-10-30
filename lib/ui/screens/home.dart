/// Layar Home: feed personal dari proxy. Menampilkan rak dan daftar lagu asli,
/// dengan keadaan muat (skeleton), galat, dan belum-dikonfigurasi eksplisit.
library;

import 'package:flutter/material.dart';

import '../../data/music_models.dart';
import '../../data/settings_store.dart';
import '../../data/sonora_api.dart';
import '../app_scope.dart';
import '../player/player_controller.dart';
import '../player_actions.dart';
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
    }
    if (_sections == null && _error == null) _load();
  }

  @override
  void dispose() {
    _settings?.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    // Endpoint berubah: buang hasil lama dan muat ulang dari nol.
    setState(() {
      _sections = null;
      _error = null;
    });
    _load();
  }

  Future<void> _load() async {
    final SonoraScope scope = SonoraScope.of(context);
    if (!scope.settings.isConfigured) {
      if (!mounted) return;
      setState(() {
        _sections = null;
        _error = null;
      });
      return;
    }
    final int generation = ++_generation;
    try {
      final List<MusicSection> sections = await scope.api.home();
      if (!mounted || generation != _generation) return;
      setState(() {
        _sections = sections;
        _error = null;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = _message(error));
    }
  }

  String _message(Object error) =>
      error is SonoraApiException ? error.message : error.toString();

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = context.scheme;
    final SonoraScope scope = SonoraScope.of(context);
    return ListenableBuilder(
      listenable: scope.settings,
      builder: (BuildContext context, Widget? _) {
        final Widget body;
        if (!scope.settings.isConfigured) {
          body = EmptyState(
            icon: Icons.settings_ethernet_rounded,
            title: 'Proxy belum diatur',
            message:
                'Masukkan alamat proxy Sonora milikmu di Pengaturan untuk mulai '
                'mendengarkan musik.',
            action: FilledButton.icon(
              onPressed: () => scope.tabs.goTo(AppTabs.settings),
              icon: const Icon(Icons.settings_rounded),
              label: const Text('Buka Pengaturan'),
            ),
          );
        } else if (_error != null && _sections == null) {
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
                  padding: const EdgeInsets.fromLTRB(kSpaceLg, kSpaceLg, kSpaceLg, kSpaceSm),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text('Sonora', style: context.texts.displaySmall),
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

class _HomeFeed extends StatelessWidget {
  const _HomeFeed({required this.sections});

  final List<MusicSection> sections;

  @override
  Widget build(BuildContext context) {
    final PlayerController player = SonoraScope.of(context).player;
    final PlayerActions actions = PlayerActions.of(context);
    final List<MusicSection> visible = sections
        .where((MusicSection section) => section.items.isNotEmpty)
        .toList(growable: false);
    if (visible.isEmpty) {
      return const EmptyState(
        icon: Icons.library_music_outlined,
        title: 'Beranda kosong',
        message: 'Proxy tidak mengembalikan konten untuk beranda.',
      );
    }
    return ListenableBuilder(
      listenable: player,
      builder: (BuildContext context, Widget? _) => ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: kSpaceXxl),
        itemCount: visible.length,
        itemBuilder: (BuildContext context, int index) {
          final MusicSection section = visible[index];
          final bool songList = section.items.first.isPlayable &&
              section.items.every((MusicItem item) => item.isPlayable);
          if (songList) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SectionHeader(
                  title: section.title,
                  trailing: TextButton.icon(
                    onPressed: () => actions.playQueue(section.items),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Putar'),
                  ),
                ),
                for (final MusicItem item in section.items)
                  SongRow(
                    item: item,
                    active: actions.activeVideoId == item.videoId,
                    onPlay: () => actions.play(item),
                    onAddToQueue: (bool next) => actions.addToQueue(item, next: next),
                  ),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (section.title.isNotEmpty) SectionHeader(title: section.title),
              MusicShelf(items: section.items, onOpen: actions.open),
            ],
          );
        },
      ),
    );
  }
}
