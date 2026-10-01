/// Layar Browse: album, playlist, artis, atau "lihat semua". Menampilkan daftar
/// lagu (dengan identitas lagu terpilih dipertahankan) dan rak terkait.
library;

import 'package:flutter/material.dart';

import '../../data/music_models.dart';
import '../../data/sonora_api.dart';
import '../app_scope.dart';
import '../player/player_controller.dart';
import '../player_actions.dart';
import '../theme.dart';
import '../widgets/common.dart';

class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key, required this.browseId, required this.title});

  final String browseId;
  final String title;

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  List<MusicSection>? _sections;
  String? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final int generation = ++_generation;
    setState(() => _error = null);
    try {
      final List<MusicSection> sections =
          await SonoraScope.of(context).api.browse(widget.browseId);
      if (!mounted || generation != _generation) return;
      setState(() => _sections = sections);
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
    final List<MusicSection>? sections = _sections;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: _error != null && sections == null
          ? ErrorState(message: _error!, onRetry: _load)
          : sections == null
              ? const LoadingState()
              : _BrowseBody(sections: sections),
      backgroundColor: scheme.surface,
    );
  }
}

class _BrowseBody extends StatelessWidget {
  const _BrowseBody({required this.sections});

  final List<MusicSection> sections;

  @override
  Widget build(BuildContext context) {
    final PlayerActions actions = PlayerActions.of(context);
    final PlayerController player = SonoraScope.of(context).player;
    final List<MusicSection> visible = sections
        .where((MusicSection section) => section.items.isNotEmpty)
        .toList(growable: false);
    if (visible.isEmpty) {
      return const EmptyState(
        icon: Icons.album_outlined,
        title: 'Tidak ada konten',
        message: 'Sumber ini belum memiliki lagu yang bisa ditampilkan.',
      );
    }
    // Kumpulan lagu yang dapat diputar untuk aksi "Putar semua".
    final List<MusicItem> playable = <MusicItem>[
      for (final MusicSection section in visible)
        for (final MusicItem item in section.items)
          if (item.isPlayable) item,
    ];
    return ListenableBuilder(
      listenable: player,
      builder: (BuildContext context, Widget? _) => ListView.builder(
        padding: const EdgeInsets.only(bottom: kSpaceXxl),
        itemCount: visible.length + (playable.isNotEmpty ? 1 : 0),
        itemBuilder: (BuildContext context, int index) {
          if (playable.isNotEmpty && index == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(kSpaceLg, kSpaceLg, kSpaceLg, kSpaceSm),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: () => actions.playQueue(playable),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text('Putar semua (${playable.length})'),
                ),
              ),
            );
          }
          final MusicSection section = visible[index - (playable.isNotEmpty ? 1 : 0)];
          final bool songList = section.items.every((MusicItem item) => item.isPlayable);
          if (songList) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (section.title.isNotEmpty) SectionHeader(title: section.title),
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
              SizedBox(
                height: 214,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: kSpaceLg),
                  itemCount: section.items.length,
                  separatorBuilder: (_, _) => const SizedBox(width: kSpaceMd),
                  itemBuilder: (BuildContext context, int index) {
                    final MusicItem item = section.items[index];
                    return ShelfCard(item: item, onOpen: () => actions.open(item));
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
