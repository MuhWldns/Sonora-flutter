/// Permukaan pemutaran: kapsul mini-player yang menempel di atas bilah tab,
/// pemutar penuh (artwork/antrean), dan lembar antrean yang dapat disunting.
/// Semua kontrol benar-benar terhubung ke [PlayerController].
library;

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'player_controller.dart';

/// Mini-player: kapsul mengambang dengan sampul, judul, kontrol putar/berikut,
/// dan garis kemajuan. Ketuk untuk membuka pemutar penuh.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final PlayerController player = SonoraScope.of(context).player;
    final ColorScheme scheme = context.scheme;
    final SonoraColors sonora = context.sonora;
    return ListenableBuilder(
      listenable: player,
      builder: (BuildContext context, Widget? _) {
        final PlayerSnapshot snap = player.snapshot;
        final PlayerTrack? track = snap.current;
        if (track == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(kSpaceSm, kSpaceXs, kSpaceSm, 0),
          child: Material(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(kRadiusLg),
            clipBehavior: Clip.antiAlias,
            elevation: 3,
            child: InkWell(
              onTap: () => openFullPlayer(context),
              child: SizedBox(
                height: 60,
                child: Column(
                  children: <Widget>[
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: kSpaceSm,
                          vertical: kSpaceXs,
                        ),
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
                                      color: snap.error != null
                                          ? scheme.error
                                          : scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: snap.playing ? 'Jeda' : 'Putar',
                              iconSize: 30,
                              icon: Icon(
                                snap.playing
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                              ),
                              onPressed: player.togglePlay,
                            ),
                            IconButton(
                              tooltip: 'Berikutnya',
                              iconSize: 28,
                              icon: const Icon(Icons.skip_next_rounded),
                              onPressed: player.next,
                            ),
                          ],
                        ),
                      ),
                    ),
                    LinearProgressIndicator(
                      value: snap.progress,
                      minHeight: 2.5,
                      backgroundColor: sonora.glassSurfaceSubtle,
                      color: scheme.primary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
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

/// Pemutar penuh dengan dua tampilan: artwork dan antrean.
class FullPlayer extends StatefulWidget {
  const FullPlayer({super.key});

  @override
  State<FullPlayer> createState() => _FullPlayerState();
}

enum _PlayerView { artwork, queue }

class _FullPlayerState extends State<FullPlayer> {
  _PlayerView _view = _PlayerView.artwork;

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
          appBar: AppBar(
            leading: IconButton(
              tooltip: 'Tutup pemutar',
              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            title: const Text('Sedang diputar'),
            centerTitle: true,
            actions: <Widget>[
              if (track != null)
                IconButton(
                  tooltip: _view == _PlayerView.queue ? 'Tutup antrean' : 'Buka antrean',
                  icon: Icon(
                    _view == _PlayerView.queue
                        ? Icons.queue_music_rounded
                        : Icons.queue_music_outlined,
                  ),
                  onPressed: () => setState(() {
                    _view = _view == _PlayerView.queue
                        ? _PlayerView.artwork
                        : _PlayerView.queue;
                  }),
                ),
            ],
          ),
          body: track == null
              ? const EmptyState(
                  icon: Icons.music_off_rounded,
                  title: 'Tidak ada yang diputar',
                  message: 'Pilih lagu untuk mulai mendengarkan.',
                )
              : SafeArea(
                  top: false,
                  child: _view == _PlayerView.queue
                      ? QueueView(player: player)
                      : _ArtworkView(
                          player: player,
                          snap: snap,
                          track: track,
                          onShowQueue: () => setState(() => _view = _PlayerView.queue),
                        ),
                ),
          backgroundColor: scheme.surface,
        );
      },
    );
  }
}

class _ArtworkView extends StatelessWidget {
  const _ArtworkView({
    required this.player,
    required this.snap,
    required this.track,
    required this.onShowQueue,
  });

  final PlayerController player;
  final PlayerSnapshot snap;
  final PlayerTrack track;
  final VoidCallback onShowQueue;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = context.scheme;
    final SonoraColors sonora = context.sonora;
    final double artSize = _artworkSize(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: kSpaceXl),
      child: Column(
        children: <Widget>[
          const SizedBox(height: kSpaceLg),
          Stack(
            alignment: Alignment.center,
            children: <Widget>[
              Container(
                width: artSize * 1.1,
                height: artSize * 1.1,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: <Color>[sonora.glow, Colors.transparent],
                  ),
                ),
              ),
              CoverArt(
                url: track.thumbnail,
                size: artSize,
                radius: kRadiusLg,
                icon: Icons.music_note_rounded,
              ),
            ],
          ),
          const SizedBox(height: kSpaceXl),
          Text(
            track.title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: context.texts.headlineSmall,
          ),
          const SizedBox(height: kSpaceXs),
          Text(
            track.artist,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.texts.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: kSpaceXl),
          _ProgressBar(player: player, snap: snap),
          const SizedBox(height: kSpaceSm),
          _TransportControls(player: player, snap: snap),
          const SizedBox(height: kSpaceLg),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: <Widget>[
              IconButton.filledTonal(
                tooltip: snap.shuffle ? 'Acak aktif' : 'Acak',
                isSelected: snap.shuffle,
                icon: const Icon(Icons.shuffle_rounded),
                selectedIcon:
                    Icon(Icons.shuffle_rounded, color: scheme.onPrimaryContainer),
                onPressed: player.toggleShuffle,
              ),
              IconButton.filledTonal(
                tooltip: 'Buka antrean',
                icon: const Icon(Icons.queue_music_rounded),
                onPressed: onShowQueue,
              ),
              IconButton.filledTonal(
                tooltip: _repeatLabel(snap.repeat),
                isSelected: snap.repeat != PlayerRepeatMode.off,
                icon: Icon(_repeatIcon(snap.repeat)),
                selectedIcon:
                    Icon(_repeatIcon(snap.repeat), color: scheme.onPrimaryContainer),
                onPressed: player.cycleRepeat,
              ),
            ],
          ),
          const SizedBox(height: kSpaceLg),
        ],
      ),
    );
  }
}

double _artworkSize(BuildContext context) {
  final Size size = MediaQuery.sizeOf(context);
  final double available = size.width - kSpaceXl * 2;
  final double byHeight = size.height * 0.36;
  return <double>[available, byHeight, 320]
      .reduce((double a, double b) => a < b ? a : b);
}

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
    return Column(
      children: <Widget>[
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
          ),
          child: Slider(
            value: value,
            max: max,
            onChanged: totalMs > 0
                ? (double v) => player.seek(Duration(milliseconds: v.round()))
                : null,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: kSpaceSm),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(_fmt(snap.position), style: context.texts.bodySmall),
              Text(
                _fmt(snap.duration),
                style: context.texts.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
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

class _TransportControls extends StatelessWidget {
  const _TransportControls({required this.player, required this.snap});

  final PlayerController player;
  final PlayerSnapshot snap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = context.scheme;
    final SonoraColors sonora = context.sonora;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        IconButton(
          tooltip: 'Sebelumnya',
          iconSize: 40,
          icon: const Icon(Icons.skip_previous_rounded),
          onPressed: player.previous,
        ),
        const SizedBox(width: kSpaceLg),
        SizedBox(
          width: 72,
          height: 72,
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
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.6,
                      color: sonora.onAccent,
                    ),
                  )
                : Icon(
                    snap.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: 40,
                  ),
          ),
        ),
        const SizedBox(width: kSpaceLg),
        IconButton(
          tooltip: 'Berikutnya',
          iconSize: 40,
          icon: const Icon(Icons.skip_next_rounded),
          onPressed: player.next,
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

/// Tampilan antrean: lagu aktif disematkan, sisanya dapat diputar, diurutkan,
/// dan dihapus.
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
          padding: const EdgeInsets.fromLTRB(kSpaceLg, kSpaceSm, kSpaceLg, kSpaceSm),
          child: Row(
            children: <Widget>[
              Expanded(child: Text('Antrean', style: context.texts.titleLarge)),
              Text(
                '${currentIndex + 1}/${snap.queue.length}',
                style: context.texts.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
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
                child: ListTile(
                  onTap: () => player.playAt(index),
                  selected: active,
                  selectedTileColor: sonora.glassSurfaceSubtle,
                  leading: CoverArt(url: track.thumbnail, size: 44),
                  title: Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: active ? sonora.accentText : scheme.onSurface,
                    ),
                  ),
                  subtitle: Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: ReorderableDragStartListener(
                    index: index,
                    child: Icon(
                      Icons.drag_handle_rounded,
                      color: scheme.onSurfaceVariant,
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
