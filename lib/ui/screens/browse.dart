/// Layar Browse: album, playlist, artis, atau "lihat semua". Header artwork
/// besar (overline jenis, tombol Putar semua & Acak), daftar lagu bernomor,
/// dan rak terkait.
library;

import 'dart:math';

import 'package:flutter/material.dart';

import '../../data/music_models.dart';
import '../../data/sonora_api.dart';
import '../app_scope.dart';
import '../player/player_controller.dart';
import '../player_actions.dart';
import '../theme.dart';
import '../widgets/common.dart';

class BrowseScreen extends StatefulWidget {
  const BrowseScreen({
    super.key,
    required this.browseId,
    required this.title,
    this.thumbnail,
    this.typeLabel = 'Album',
  });

  final String browseId;
  final String title;
  final String? thumbnail;

  /// Label jenis sumber untuk overline header (album/playlist/artis).
  final String typeLabel;

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
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: kSpaceXs),
              child: Row(
                children: <Widget>[
                  IconButton(
                    tooltip: 'Kembali',
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _error != null && sections == null
                  ? ErrorState(message: _error!, onRetry: _load)
                  : sections == null
                      ? const SkeletonHomeFeed()
                      : _BrowseBody(
                          sections: sections,
                          title: widget.title,
                          thumbnail: widget.thumbnail,
                          typeLabel: widget.typeLabel,
                        ),
            ),
          ],
        ),
      ),
      backgroundColor: scheme.surface,
    );
  }
}

class _BrowseBody extends StatelessWidget {
  const _BrowseBody({
    required this.sections,
    required this.title,
    required this.thumbnail,
    required this.typeLabel,
  });

  final List<MusicSection> sections;
  final String title;
  final String? thumbnail;
  final String typeLabel;

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
    // Kumpulan lagu yang dapat diputar untuk aksi "Putar semua"/"Acak".
    final List<MusicItem> playable = <MusicItem>[
      for (final MusicSection section in visible)
        for (final MusicItem item in section.items)
          if (item.isPlayable) item,
    ];
    return ListenableBuilder(
      listenable: player,
      builder: (BuildContext context, Widget? _) => ListView.builder(
        padding: const EdgeInsets.only(bottom: kSpaceXxl),
        itemCount: visible.length + 1,
        itemBuilder: (BuildContext context, int index) {
          if (index == 0) {
            return _BrowseHeader(
              playable: playable,
              actions: actions,
              title: title,
              thumbnail: thumbnail,
              typeLabel: typeLabel,
            );
          }
          final MusicSection section = visible[index - 1];
          final bool songList = section.items.every((MusicItem item) => item.isPlayable);
          if (songList) {
            final int startNumber = _numberBase(visible, section);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (section.title.isNotEmpty) SectionHeader(title: section.title),
                for (final (int i, MusicItem item) in section.items.indexed)
                  SongRow(
                    item: item,
                    trackNumber: (startNumber + i).toString().padLeft(2, '0'),
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

  /// Nomor trek berjalan lintas seksi lagu (mis. album multi-disk).
  static int _numberBase(List<MusicSection> visible, MusicSection current) {
    int base = 1;
    for (final MusicSection section in visible) {
      if (identical(section, current)) break;
      if (section.items.isNotEmpty && section.items.every((MusicItem i) => i.isPlayable)) {
        base += section.items.length;
      }
    }
    return base;
  }
}

/// Header artwork besar: overline jenis, judul display, aksi Putar semua/Acak.
class _BrowseHeader extends StatelessWidget {
  const _BrowseHeader({
    required this.playable,
    required this.actions,
    required this.title,
    required this.thumbnail,
    required this.typeLabel,
  });

  final List<MusicItem> playable;
  final PlayerActions actions;
  final String title;
  final String? thumbnail;
  final String typeLabel;

  @override
  Widget build(BuildContext context) {
    final double artSize = <double>[
      MediaQuery.sizeOf(context).width - kSpaceXl * 2,
      360,
    ].reduce((double a, double b) => a < b ? a : b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: kSpaceSm),
        Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(kRadiusXl),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  offset: const Offset(0, 20),
                  blurRadius: 40,
                  spreadRadius: -10,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(kRadiusXl),
              child: CoverArt(
                url: thumbnail,
                size: artSize,
                radius: kRadiusXl,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(kSpaceLg, kSpaceXl, kSpaceLg, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Overline(typeLabel),
              const SizedBox(height: kSpaceXs),
              Text(
                title,
                style: context.texts.displaySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: kSpaceLg),
              Row(
                children: <Widget>[
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: playable.isEmpty
                          ? null
                          : () => actions.playQueue(playable),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text(playable.isEmpty
                          ? 'Putar semua'
                          : 'Putar semua (${playable.length})'),
                    ),
                  ),
                  const SizedBox(width: kSpaceMd),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: playable.isEmpty
                          ? null
                          : () => actions.playQueue(
                              playable,
                              startIndex: Random().nextInt(playable.length),
                            ),
                      icon: const Icon(Icons.shuffle_rounded),
                      label: const Text('Acak'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: kSpaceSm),
      ],
    );
  }
}
