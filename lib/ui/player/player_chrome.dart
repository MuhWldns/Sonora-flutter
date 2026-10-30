/// Permukaan pemutaran Nocturne: dock mini-player kaca di atas bilah tab,
/// pemutar penuh (artwork/lirik/antrean), dan tampilan lirik tersinkronisasi
/// LRCLIB. Semua kontrol benar-benar terhubung ke [PlayerController].
library;

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../data/local_database.dart';
import '../../data/lyrics_store.dart';
import '../../data/music_models.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'player_controller.dart';

/// Dock mini-player: kaca translusen (blur 16 + border tipis), micro-bar
/// progres 2px di tepi atas, dan tombol putar bulat. Ketuk membuka pemutar
/// penuh.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final PlayerController player = SonoraScope.of(context).player;
    return ListenableBuilder(
      listenable: player,
      builder: (BuildContext context, Widget? _) {
        final PlayerSnapshot snap = player.snapshot;
        final PlayerTrack? track = snap.current;
        if (track == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(kSpaceMd, kSpaceXs, kSpaceMd, kSpaceSm),
          child: GlassContainer(
            borderRadius: BorderRadius.circular(kRadiusLg),
            child: SizedBox(
              height: 64,
              child: Stack(
                children: <Widget>[
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: SizedBox(
                      height: 2,
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: snap.progress.clamp(0.0, 1.0),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: context.scheme.primary,
                            borderRadius: const BorderRadius.horizontal(
                              right: Radius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(kSpaceSm, kSpaceSm + 2, kSpaceSm, kSpaceSm),
                    child: Row(
                      children: <Widget>[
                        CoverArt(url: track.thumbnail, size: 44),
                        const SizedBox(width: kSpaceMd),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                track.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.texts.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              Text(
                                snap.error ?? track.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.texts.bodySmall?.copyWith(
                                  fontSize: 12,
                                  color: snap.error != null
                                      ? context.scheme.error
                                      : context.scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _DockPlayButton(player: player, snap: snap),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Tombol bulat 36px di dock: kontras membalik (isi `onSurface`, ikon permukaan).
class _DockPlayButton extends StatelessWidget {
  const _DockPlayButton({required this.player, required this.snap});

  final PlayerController player;
  final PlayerSnapshot snap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = context.scheme;
    return SizedBox(
      width: 36,
      height: 36,
      child: Material(
        color: scheme.onSurface,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: player.togglePlay,
          child: Icon(
            snap.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: 22,
            color: scheme.surfaceContainerLowest,
          ),
        ),
      ),
    );
  }
}

/// Membuka pemutar penuh sebagai halaman slide-up.
Future<void> openFullPlayer(BuildContext context) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (BuildContext context) => const FullPlayer(),
    ),
  );
}

/// Tampilan pemutar penuh.
enum _PlayerView { artwork, lyrics, queue }

/// Pemutar penuh: tiga tampilan — artwork, lirik LRCLIB, dan antrean.
class FullPlayer extends StatefulWidget {
  const FullPlayer({super.key});

  @override
  State<FullPlayer> createState() => _FullPlayerState();
}

class _FullPlayerState extends State<FullPlayer> {
  _PlayerView _view = _PlayerView.artwork;

  void _setView(_PlayerView view) {
    if (_view == view) return;
    setState(() => _view = view);
  }

  @override
  Widget build(BuildContext context) {
    final PlayerController player = SonoraScope.of(context).player;
    final ColorScheme scheme = context.scheme;
    return ListenableBuilder(
      listenable: player,
      builder: (BuildContext context, Widget? _) {
        final PlayerSnapshot snap = player.snapshot;
        final PlayerTrack? track = snap.current;
        return Scaffold(
          backgroundColor: scheme.surface,
          body: track == null
              ? const SafeArea(
                  child: EmptyState(
                    icon: Icons.music_off_rounded,
                    title: 'Tidak ada yang diputar',
                    message: 'Pilih lagu untuk mulai mendengarkan.',
                  ),
                )
              : SafeArea(
                  child: Column(
                    children: <Widget>[
                      _PlayerTopBar(
                        view: _view,
                        onToggleQueue: () => _setView(
                          _view == _PlayerView.queue
                              ? _PlayerView.artwork
                              : _PlayerView.queue,
                        ),
                      ),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          child: switch (_view) {
                            _PlayerView.artwork => _ArtworkView(
                                key: const ValueKey<String>('artwork'),
                                player: player,
                                snap: snap,
                                track: track,
                                onShowLyrics: () => _setView(_PlayerView.lyrics),
                              ),
                            _PlayerView.lyrics => _LyricsView(
                                key: const ValueKey<String>('lyrics'),
                                player: player,
                                snap: snap,
                                track: track,
                              ),
                            _PlayerView.queue => QueueView(
                                key: const ValueKey<String>('queue'),
                                player: player,
                              ),
                          },
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

/// Bilah atas pemutar: chevron turun + (saat antrean) judul + ikon antrean.
class _PlayerTopBar extends StatelessWidget {
  const _PlayerTopBar({required this.view, required this.onToggleQueue});

  final _PlayerView view;
  final VoidCallback onToggleQueue;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: kSpaceXs),
        child: Row(
          children: <Widget>[
            IconButton(
              tooltip: 'Tutup pemutar',
              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: view == _PlayerView.queue
                  ? Text(
                      'Antrean',
                      textAlign: TextAlign.center,
                      style: context.texts.titleLarge,
                    )
                  : const SizedBox.shrink(),
            ),
            if (view != _PlayerView.queue)
              IconButton(
                tooltip: view == _PlayerView.queue ? 'Tutup antrean' : 'Buka antrean',
                icon: Icon(
                  view == _PlayerView.queue
                      ? Icons.queue_music_rounded
                      : Icons.queue_music_outlined,
                ),
                onPressed: onToggleQueue,
              )
            else
              const SizedBox(width: kTouchTarget),
          ],
        ),
      ),
    );
  }
}

/// Tampilan artwork: glow ambien crimson, judul, scrubber, transport.
class _ArtworkView extends StatefulWidget {
  const _ArtworkView({
    super.key,
    required this.player,
    required this.snap,
    required this.track,
    required this.onShowLyrics,
  });

  final PlayerController player;
  final PlayerSnapshot snap;
  final PlayerTrack track;
  final VoidCallback onShowLyrics;

  @override
  State<_ArtworkView> createState() => _ArtworkViewState();
}

class _ArtworkViewState extends State<_ArtworkView> {
  bool _favorite = false;
  String _favoriteKey = '';

  @override
  void initState() {
    super.initState();
    _loadFavorite();
  }

  @override
  void didUpdateWidget(_ArtworkView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.videoId != widget.track.videoId) _loadFavorite();
  }

  Future<void> _loadFavorite() async {
    final String key = widget.track.videoId;
    final LocalDatabase? db = SonoraScope.of(context).database;
    _favoriteKey = key;
    if (db == null || key.isEmpty) {
      if (mounted) setState(() => _favorite = false);
      return;
    }
    final bool favorite = await db.isFavorite(key);
    // Balasan basi: lagu sudah berganti saat pemeriksaan berjalan.
    if (!mounted || _favoriteKey != key || _favorite == favorite) return;
    setState(() => _favorite = favorite);
  }

  Future<void> _toggleFavorite() async {
    final LocalDatabase? db = SonoraScope.of(context).database;
    if (db == null) return;
    final PlayerTrack track = widget.track;
    if (_favorite) {
      await db.removeFavorite(track.videoId);
    } else {
      await db.addFavorite(
        MusicItem(
          type: 'song',
          title: track.title,
          artist: track.artist,
          thumbnail: track.thumbnail,
          videoId: track.videoId,
          duration: formatDurationMs(
            track.durationMs > 0 ? track.durationMs : null,
          ),
        ),
      );
    }
    if (mounted) setState(() => _favorite = !_favorite);
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = context.scheme;
    final SonoraColors sonora = context.sonora;
    final double artSize = _artworkSize(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const SizedBox(height: kSpaceMd),
                Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    Container(
                      width: artSize * 1.15,
                      height: artSize * 1.15,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: <Color>[sonora.glow, Colors.transparent],
                        ),
                      ),
                    ),
                    Hero(
                      tag: 'sonora-art-${widget.track.videoId}',
                      child: CoverArt(
                        url: widget.track.thumbnail,
                        size: artSize,
                        radius: kRadiusXl,
                        icon: Icons.music_note_rounded,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: kSpaceXl),
                Overline('Sedang diputar'),
                const SizedBox(height: kSpaceXs),
                Text(
                  widget.track.title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.headlineSmall,
                ),
                const SizedBox(height: kSpaceXs),
                Text(
                  widget.track.artist,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.bodyLarge
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: kSpaceXl),
                _ProgressBar(player: widget.player, snap: widget.snap),
                const SizedBox(height: kSpaceSm),
                _TransportControls(player: widget.player, snap: widget.snap),
                const SizedBox(height: kSpaceLg),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: <Widget>[
                    if (SonoraScope.of(context).database != null)
                      IconButton(
                        tooltip: _favorite ? 'Hapus dari favorit' : 'Tambahkan ke favorit',
                        iconSize: 24,
                        color: _favorite ? sonora.accentText : scheme.onSurfaceVariant,
                        icon: Icon(
                          _favorite
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                        ),
                        onPressed: _toggleFavorite,
                      ),
                    IconButton(
                      tooltip: 'Lihat lirik',
                      iconSize: 24,
                      color: scheme.onSurfaceVariant,
                      icon: const Icon(Icons.lyrics_outlined),
                      onPressed: widget.onShowLyrics,
                    ),
                  ],
                ),
                const SizedBox(height: kSpaceLg),
              ],
            ),
          ),
        );
      },
    );
  }
}

double _artworkSize(BuildContext context) {
  final Size size = MediaQuery.sizeOf(context);
  final double available = size.width - kSpaceXl * 2;
  final double byHeight = size.height * 0.34;
  return <double>[available, byHeight, 320]
      .reduce((double a, double b) => a < b ? a : b);
}

/// Scrubber 4px dengan timestamp mono (JetBrains Mono 11).
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.player, required this.snap});

  final PlayerController player;
  final PlayerSnapshot snap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = context.scheme;
    final int totalMs = snap.duration.inMilliseconds;
    final double max = totalMs > 0 ? totalMs.toDouble() : 1;
    final double value = totalMs > 0
        ? snap.position.inMilliseconds.clamp(0, totalMs).toDouble()
        : 0;
    final TextStyle mono = GoogleFonts.jetBrainsMono(
      fontSize: 11,
      fontWeight: FontWeight.w500,
      color: scheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kSpaceLg),
      child: Column(
        children: <Widget>[
          Slider(
            value: value,
            max: max,
            onChanged: totalMs > 0
                ? (double v) => player.seek(Duration(milliseconds: v.round()))
                : null,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: kSpaceXs),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(_fmt(snap.position), style: mono),
                Text(_fmt(snap.duration), style: mono),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _fmt(Duration d) {
    final int total = d.inSeconds;
    final int h = total ~/ 3600;
    final int m = (total % 3600) ~/ 60;
    final int s = total % 60;
    final String mm = h > 0 ? m.toString().padLeft(2, '0') : '$m';
    final String ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }
}

/// Transport utama: tombol crimson 64px sebagai titik fokus tunggal.
class _TransportControls extends StatelessWidget {
  const _TransportControls({required this.player, required this.snap});

  final PlayerController player;
  final PlayerSnapshot snap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = context.scheme;
    final SonoraColors sonora = context.sonora;
    final bool shuffleOn = snap.shuffle;
    final bool repeatOn = snap.repeat != PlayerRepeatMode.off;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        IconButton(
          tooltip: snap.shuffle ? 'Acak aktif' : 'Acak',
          isSelected: shuffleOn,
          iconSize: 26,
          icon: Icon(Icons.shuffle_rounded, color: scheme.onSurfaceVariant),
          selectedIcon: Icon(Icons.shuffle_rounded, color: sonora.accentText),
          onPressed: player.toggleShuffle,
        ),
        const SizedBox(width: kSpaceMd),
        IconButton(
          tooltip: 'Sebelumnya',
          iconSize: 34,
          color: scheme.onSurface,
          icon: const Icon(Icons.skip_previous_rounded),
          onPressed: player.previous,
        ),
        const SizedBox(width: kSpaceMd),
        SizedBox(
          width: 64,
          height: 64,
          child: FilledButton(
            onPressed: player.togglePlay,
            style: FilledButton.styleFrom(
              shape: const CircleBorder(),
              padding: EdgeInsets.zero,
              backgroundColor: scheme.primary,
              foregroundColor: sonora.onAccent,
            ),
            child: snap.buffering
                ? SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: sonora.onAccent,
                    ),
                  )
                : Icon(
                    snap.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: 34,
                  ),
          ),
        ),
        const SizedBox(width: kSpaceMd),
        IconButton(
          tooltip: 'Berikutnya',
          iconSize: 34,
          color: scheme.onSurface,
          icon: const Icon(Icons.skip_next_rounded),
          onPressed: player.next,
        ),
        const SizedBox(width: kSpaceMd),
        IconButton(
          tooltip: _repeatLabel(snap.repeat),
          isSelected: repeatOn,
          iconSize: 26,
          icon: Icon(_repeatIcon(snap.repeat), color: scheme.onSurfaceVariant),
          selectedIcon: Icon(_repeatIcon(snap.repeat), color: sonora.accentText),
          onPressed: player.cycleRepeat,
        ),
      ],
    );
  }
}

IconData _repeatIcon(PlayerRepeatMode mode) => switch (mode) {
      PlayerRepeatMode.off => Icons.repeat_rounded,
      PlayerRepeatMode.all => Icons.repeat_rounded,
      PlayerRepeatMode.one => Icons.repeat_one_rounded,
    };

String _repeatLabel(PlayerRepeatMode mode) => switch (mode) {
      PlayerRepeatMode.off => 'Ulangi: mati',
      PlayerRepeatMode.all => 'Ulangi: semua',
      PlayerRepeatMode.one => 'Ulangi: satu lagu',
    };

/// Fase pemuatan lirik.
enum _LyricsPhase { idle, loading, ready, unavailable }

/// Tampilan lirik: latar artwork blur + scrim, baris rata kiri, baris aktif
/// crimson besar yang fade saat berganti, kontrol kompak di bawah.
class _LyricsView extends StatefulWidget {
  const _LyricsView({
    super.key,
    required this.player,
    required this.snap,
    required this.track,
  });

  final PlayerController player;
  final PlayerSnapshot snap;
  final PlayerTrack track;

  @override
  State<_LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<_LyricsView> {
  LyricsRepository? _repo;
  _LyricsPhase _phase = _LyricsPhase.idle;
  LrcLyrics? _lyrics;
  String _lyricsKey = '';
  int _lastActive = -1;
  final Map<int, GlobalKey> _lineKeys = <int, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    _loadLyrics();
  }

  @override
  void didUpdateWidget(_LyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.videoId != widget.track.videoId) _loadLyrics();
  }

  @override
  void dispose() {
    _repo?.dispose();
    super.dispose();
  }

  Future<void> _loadLyrics() async {
    final String key = widget.track.videoId;
    if (key == _lyricsKey) return;
    _lyricsKey = key;
    _lineKeys.clear();
    _lastActive = -1;
    if (key.isEmpty) {
      if (mounted) setState(() => _phase = _LyricsPhase.unavailable);
      return;
    }
    if (mounted) setState(() => _phase = _LyricsPhase.loading);
    _repo ??= LyricsRepository();
    final LrcLyrics? lyrics = await _repo!.find(
      track: widget.track.title,
      artist: widget.track.artist,
      durationMs: widget.track.durationMs > 0 ? widget.track.durationMs : null,
    );
    // Balasan basi: lagu sudah berganti saat permintaan berjalan.
    if (!mounted || _lyricsKey != widget.track.videoId) return;
    setState(() {
      if (lyrics == null) {
        _phase = _LyricsPhase.unavailable;
        _lyrics = null;
      } else {
        _phase = _LyricsPhase.ready;
        _lyrics = lyrics;
      }
    });
  }

  void _scheduleAutoScroll(int? active) {
    if (active == null || active == _lastActive) return;
    _lastActive = active;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final BuildContext? lineContext = _lineKeys[active]?.currentContext;
      if (lineContext == null) return;
      Scrollable.ensureVisible(
        lineContext,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
        alignment: 0.35,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = context.scheme;
    final SonoraColors sonora = context.sonora;
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final LrcLyrics? lyrics = _lyrics;
    final int? active =
        _phase == _LyricsPhase.ready && lyrics!.hasSynced
            ? lyrics.activeIndexAt(widget.snap.position)
            : null;
    _scheduleAutoScroll(active);

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        // Latar artwork blur (kaca/pemudaran punya sesuatu untuk direfraksikan).
        if ((widget.track.thumbnail ?? '').isNotEmpty)
          Positioned.fill(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 46, sigmaY: 46),
              child: Image.network(
                widget.track.thumbnail!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          )
        else
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: <Color>[sonora.glow, scheme.surface],
                ),
              ),
            ),
          ),
        // Scrim berjenjang agar teks selalu terbaca.
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const <double>[0.0, 0.45, 1.0],
                colors: <Color>[
                  scheme.surface.withValues(alpha: dark ? 0.32 : 0.55),
                  scheme.surface.withValues(alpha: dark ? 0.42 : 0.62),
                  scheme.surface.withValues(alpha: dark ? 0.88 : 0.94),
                ],
              ),
            ),
          ),
        ),
        // Isi: baris lirik + kontrol kompak.
        Column(
          children: <Widget>[
            Expanded(child: _lyricsBody(context, active)),
            _CompactControls(player: widget.player, snap: widget.snap),
          ],
        ),
      ],
    );
  }

  Widget _lyricsBody(BuildContext context, int? active) {
    switch (_phase) {
      case _LyricsPhase.idle:
      case _LyricsPhase.loading:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: kSpaceXl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              for (final double w in <double>[0.7, 0.9, 0.55, 0.8, 0.65]) ...<Widget>[
                Align(
                  alignment: Alignment.centerLeft,
                  child: SkeletonBox(width: w * 260, height: 18, radius: 6),
                ),
                const SizedBox(height: kSpaceLg),
              ],
            ],
          ),
        );
      case _LyricsPhase.unavailable:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.lyrics_outlined,
                size: 40,
                color: context.scheme.onSurfaceVariant,
              ),
              const SizedBox(height: kSpaceMd),
              Text('Lirik tidak tersedia', style: context.texts.titleMedium),
              const SizedBox(height: kSpaceXs),
              Text(
                'LRCLIB tidak memiliki lirik untuk lagu ini.',
                style: context.texts.bodySmall
                    ?.copyWith(color: context.scheme.onSurfaceVariant),
              ),
            ],
          ),
        );
      case _LyricsPhase.ready:
        final List<LrcLine> lines = _lyrics!.synced;
        if (lines.isEmpty) {
          // Lirik polos tanpa sinkronisasi: tampil sebagai paragraf.
          return SingleChildScrollView(
            padding: const EdgeInsets.all(kSpaceXl),
            child: Text(
              _lyrics!.plain ?? '',
              style: context.texts.bodyLarge?.copyWith(height: 1.7),
            ),
          );
        }
        return ListView.builder(
          padding: EdgeInsets.only(
            top: MediaQuery.sizeOf(context).height * 0.18,
            bottom: MediaQuery.sizeOf(context).height * 0.24,
          ),
          itemCount: lines.length,
          itemBuilder: (BuildContext context, int index) {
            final bool isActive = active != null && index == active;
            final bool isNear = active != null && (index - active).abs() == 1;
            _lineKeys.putIfAbsent(index, () => GlobalKey());
            final Color base = context.scheme.onSurface;
            final Color color = isActive
                ? context.sonora.accentText
                : base.withValues(alpha: isNear ? 0.66 : 0.40);
            return GestureDetector(
              key: _lineKeys[index],
              behavior: HitTestBehavior.opaque,
              onTap: () => widget.player.seek(lines[index].timestamp),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: kSpaceXl,
                  vertical: kSpaceSm + 2,
                ),
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 450),
                  curve: Curves.easeOutCubic,
                  style: (isActive
                          ? context.texts.headlineSmall!
                          : context.texts.titleLarge!)
                      .copyWith(
                    fontSize: isActive ? 27 : 21,
                    height: 1.4,
                    color: color,
                  ),
                  child: Text(lines[index].text),
                ),
              ),
            );
          },
        );
    }
  }
}

/// Kontrol kompak di bawah lirik: judul, scrubber, transport ringkas.
class _CompactControls extends StatelessWidget {
  const _CompactControls({required this.player, required this.snap});

  final PlayerController player;
  final PlayerSnapshot snap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = context.scheme;
    final int totalMs = snap.duration.inMilliseconds;
    final double max = totalMs > 0 ? totalMs.toDouble() : 1;
    final double value = totalMs > 0
        ? snap.position.inMilliseconds.clamp(0, totalMs).toDouble()
        : 0;
    final TextStyle mono = GoogleFonts.jetBrainsMono(
      fontSize: 11,
      fontWeight: FontWeight.w500,
      color: scheme.onSurfaceVariant,
    );
    return Padding(
      padding: EdgeInsets.only(
        left: kSpaceXl,
        right: kSpaceXl,
        bottom: MediaQuery.paddingOf(context).bottom + kSpaceLg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            snap.current?.title ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.texts.titleSmall?.copyWith(fontSize: 15),
          ),
          Text(
            snap.current?.artist ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.texts.bodySmall?.copyWith(
              fontSize: 12,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: kSpaceMd),
          Slider(
            value: value,
            max: max,
            onChanged: totalMs > 0
                ? (double v) => player.seek(Duration(milliseconds: v.round()))
                : null,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(_fmt(snap.position), style: mono),
              Text(_fmt(snap.duration), style: mono),
            ],
          ),
          const SizedBox(height: kSpaceSm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              IconButton(
                tooltip: 'Sebelumnya',
                iconSize: 28,
                color: scheme.onSurface.withValues(alpha: 0.75),
                icon: const Icon(Icons.skip_previous_rounded),
                onPressed: player.previous,
              ),
              const SizedBox(width: kSpaceXl),
              SizedBox(
                width: 48,
                height: 48,
                child: FilledButton(
                  onPressed: player.togglePlay,
                  style: FilledButton.styleFrom(
                    shape: const CircleBorder(),
                    padding: EdgeInsets.zero,
                    backgroundColor: scheme.primary,
                    foregroundColor: context.sonora.onAccent,
                  ),
                  child: snap.buffering
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: context.sonora.onAccent,
                          ),
                        )
                      : Icon(
                          snap.playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: 26,
                        ),
                ),
              ),
              const SizedBox(width: kSpaceXl),
              IconButton(
                tooltip: 'Berikutnya',
                iconSize: 28,
                color: scheme.onSurface.withValues(alpha: 0.75),
                icon: const Icon(Icons.skip_next_rounded),
                onPressed: player.next,
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _fmt(Duration d) {
    final int total = d.inSeconds;
    final int h = total ~/ 3600;
    final int m = (total % 3600) ~/ 60;
    final int s = total % 60;
    final String mm = h > 0 ? m.toString().padLeft(2, '0') : '$m';
    final String ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }
}

/// Tampilan antrean: kartu "sedang diputar", seksi "berikutnya", baris
/// reorderable yang dapat digeser dan dihapus.
class QueueView extends StatelessWidget {
  const QueueView({super.key, required this.player});

  final PlayerController player;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = context.scheme;
    final SonoraColors sonora = context.sonora;
    final PlayerSnapshot snap = player.snapshot;
    if (snap.queue.isEmpty) {
      return const EmptyState(
        icon: Icons.queue_music_rounded,
        title: 'Antrean kosong',
        message: 'Lagu yang kamu putar akan muncul di sini.',
      );
    }
    final int currentIndex = snap.index;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(kSpaceLg, 0, kSpaceLg, kSpaceSm),
          child: Row(
            children: <Widget>[
              const Expanded(child: Overline('Sedang diputar')),
              Text(
                '${currentIndex + 1} / ${snap.queue.length}',
                style: context.texts.bodySmall?.copyWith(
                  fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (snap.current != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(kSpaceLg, 0, kSpaceLg, kSpaceMd),
            child: Container(
              padding: const EdgeInsets.all(kSpaceMd),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(kRadiusLg),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Row(
                children: <Widget>[
                  CoverArt(url: snap.current!.thumbnail, size: 48),
                  const SizedBox(width: kSpaceMd),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          snap.current!.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.texts.bodyLarge?.copyWith(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: sonora.accentText,
                          ),
                        ),
                        Text(
                          snap.current!.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.texts.bodySmall?.copyWith(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: kSpaceSm),
                  const SizedBox(
                    height: 14,
                    width: 14,
                    child: PlayingWave(),
                  ),
                ],
              ),
            ),
          ),
        const Padding(
          padding: EdgeInsets.fromLTRB(kSpaceLg, kSpaceXs, kSpaceLg, kSpaceSm),
          child: Overline('Berikutnya'),
        ),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.only(bottom: kSpaceXl),
            buildDefaultDragHandles: false,
            itemCount: snap.queue.length,
            onReorderItem: (int oldIndex, int newIndex) =>
                player.moveItem(oldIndex, newIndex),
            itemBuilder: (BuildContext context, int index) {
              final PlayerTrack track = snap.queue[index];
              final bool active = index == currentIndex;
              return Dismissible(
                key: ValueKey<String>('${track.videoId}-$index'),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: kSpaceXl),
                  color: scheme.errorContainer,
                  child:
                      Icon(Icons.delete_outline_rounded, color: scheme.onErrorContainer),
                ),
                onDismissed: (_) => player.removeAt(index),
                child: InkWell(
                  onTap: () => player.playAt(index),
                  child: SizedBox(
                    height: 56,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: kSpaceLg),
                      child: Row(
                        children: <Widget>[
                          CoverArt(url: track.thumbnail, size: 40),
                          const SizedBox(width: kSpaceMd),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Text(
                                  track.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: context.texts.bodyLarge?.copyWith(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: active
                                        ? sonora.accentText
                                        : scheme.onSurface,
                                  ),
                                ),
                                Text(
                                  track.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: context.texts.bodySmall?.copyWith(
                                    fontSize: 11,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ReorderableDragStartListener(
                            index: index,
                            child: Icon(
                              Icons.drag_handle_rounded,
                              size: 22,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
