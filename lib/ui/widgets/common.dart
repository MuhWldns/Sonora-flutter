/// Widget bersama: gambar sampul, baris lagu, kartu rak, header seksi,
/// skeleton shimmer, dan keadaan kosong/galat. Semua mengambil warna dari
/// tema Sonora (Nocturne).
library;

import 'package:flutter/material.dart';

import '../../data/music_models.dart';
import '../theme.dart';

/// Format durasi milidetik menjadi `m:ss` atau `h:mm:ss`.
String formatDurationMs(int? ms) {
  if (ms == null || ms <= 0) return '';
  final int totalSeconds = ms ~/ 1000;
  final int hours = totalSeconds ~/ 3600;
  final int minutes = (totalSeconds % 3600) ~/ 60;
  final int seconds = totalSeconds % 60;
  final String ss = seconds.toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:$ss';
  }
  return '$minutes:$ss';
}

/// Nama artis untuk sebuah item (dari kontrak [MusicItem.artist]).
String artistOf(MusicItem item) => item.artist;

/// Subjudul ringkas untuk baris lagu.
String subtitleOf(MusicItem item) {
  final String artist = item.artist;
  final String duration = item.duration ?? '';
  if (artist.isNotEmpty && duration.isNotEmpty) return '$artist • $duration';
  if (artist.isNotEmpty) return artist;
  return item.subtitle ?? duration;
}
/// Target browse sebuah item, atau `null` bila item tidak dapat dibuka.
String? browseTargetOf(MusicItem item) => item.browseTarget;

/// Sampul dengan cadangan ikon saat gambar gagal dimuat.
class CoverArt extends StatelessWidget {
  const CoverArt({
    super.key,
    this.url,
    required this.size,
    this.circle = false,
    this.radius = kRadiusSm,
    this.icon = Icons.music_note_rounded,
  });

  final String? url;
  final double size;
  final bool circle;
  final double radius;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = context.scheme;
    final BorderRadius borderRadius =
        BorderRadius.circular(circle ? size / 2 : radius);
    final String? source = (url != null && url!.isNotEmpty) ? url : null;
    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox(
        width: size,
        height: size,
        child: ColoredBox(
          color: scheme.surfaceContainerHighest,
          child: source == null
              ? _fallback(scheme)
              : Image.network(
                  source,
                  fit: BoxFit.cover,
                  width: size,
                  height: size,
                  errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
                      _fallback(scheme),
                  loadingBuilder: (BuildContext context, Widget child,
                      ImageChunkEvent? progress) {
                    if (progress == null) return child;
                    return _fallback(scheme);
                  },
                ),
        ),
      ),
    );
  }

  Widget _fallback(ColorScheme scheme) => Center(
        child: Icon(icon, size: size * 0.42, color: scheme.onSurfaceVariant),
      );
}

/// Header seksi: judul besar (titleLarge 21/700) dengan aksi opsional.
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(kSpaceLg, kSpaceXl, kSpaceSm, kSpaceMd),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              title,
              style: context.texts.titleLarge,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Label kecil huruf besar semua (overline Nocturne 10/700/+0.08em).
class Overline extends StatelessWidget {
  const Overline(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: context.texts.labelSmall?.copyWith(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: color ?? context.scheme.onSurfaceVariant,
      ),
    );
  }
}

/// Indikator "sedang diputar": empat batang crimson yang menari.
/// Hormat `MediaQuery.disableAnimations` — bila aktif, batang diam.
class PlayingWave extends StatefulWidget {
  const PlayingWave({super.key, this.height = 16, this.width = 17});

  final double height;
  final double width;

  @override
  State<PlayingWave> createState() => _PlayingWaveState();
}

class _PlayingWaveState extends State<PlayingWave>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // MediaQuery dibaca di sini (bukan initState) sesuai kontrak inherited widget.
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const List<double> phases = <double>[0.0, 0.25, 0.5, 0.15];
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? _) => Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            for (int i = 0; i < phases.length; i++)
              _bar(_controller.value, phases[i]),
          ],
        ),
      ),
    );
  }

  Widget _bar(double t, double phase) {
    final double wave = 0.5 + 0.5 * _sin((t + phase) * 2 * 3.14159);
    return Expanded(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: FractionallySizedBox(
          heightFactor: 0.35 + 0.65 * wave,
          child: Container(
            width: 3,
            decoration: BoxDecoration(
              color: context.sonora.accentText,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }

  static double _sin(double x) {
    // Kurva sinus ringan tanpa dart:math agar fase tetap sederhana.
    double v = x % (2 * 3.14159);
    if (v < 0) v += 2 * 3.14159;
    return v < 3.14159 ? (v / 3.14159) * 2 - 1 : ((2 * 3.14159 - v) / 3.14159) * 2 - 1;
  }
}

/// Baris lagu 56px (kontrak tracklist Nocturne): sampul 44, judul semibold,
/// subtitel redup; baris aktif diberi tint lembut + [PlayingWave].
class SongRow extends StatelessWidget {
  const SongRow({
    super.key,
    required this.item,
    required this.onPlay,
    this.onAddToQueue,
    this.active = false,
    this.trackNumber,
    this.trailing,
  });

  final MusicItem item;
  final VoidCallback onPlay;
  final void Function(bool next)? onAddToQueue;
  final bool active;

  /// Nomor trek (mis. `01`) yang menggantikan sampul — dipakai layar album.
  final String? trackNumber;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = context.scheme;
    final bool playable = item.isPlayable;
    final String subtitle = subtitleOf(item);
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final Widget cover = CoverArt(url: item.thumbnail, size: 44);
    final Widget leading = trackNumber != null
        ? SizedBox(
            width: 26,
            child: Text(
              trackNumber!,
              textAlign: TextAlign.center,
              style: context.texts.bodySmall?.copyWith(
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                color: scheme.onSurfaceVariant,
              ),
            ),
          )
        : (active && playable
            // Hero hanya pada baris aktif agar tag unik per rute.
            ? Hero(
                tag: 'sonora-art-${item.videoId}',
                child: cover,
              )
            : cover);
    return Material(
      color: active
          ? (dark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.black.withValues(alpha: 0.04))
          : Colors.transparent,
      child: InkWell(
        onTap: playable ? onPlay : null,
        child: SizedBox(
          height: 56,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: kSpaceLg),
            child: Row(
              children: <Widget>[
                leading,
                const SizedBox(width: kSpaceMd),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.texts.bodyLarge?.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: active
                              ? context.sonora.accentText
                              : scheme.onSurface,
                        ),
                      ),
                      if (subtitle.isNotEmpty)
                        Text(
                          subtitle,
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
                if (active)
                  const Padding(
                    padding: EdgeInsets.only(left: kSpaceSm),
                    child: PlayingWave(),
                  ),
                if (trailing != null)
                  trailing!
                else if (onAddToQueue != null && playable)
                  IconButton(
                    tooltip: 'Tambahkan ke antrean',
                    iconSize: 20,
                    color: scheme.onSurfaceVariant,
                    icon: const Icon(Icons.more_vert_rounded),
                    onPressed: () => _showQueueMenu(context),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showQueueMenu(BuildContext context) async {
    final bool? next = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(kSpaceLg, 0, kSpaceLg, kSpaceSm),
              child: Row(
                children: <Widget>[
                  CoverArt(url: item.thumbnail, size: 44),
                  const SizedBox(width: kSpaceMd),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.texts.titleSmall,
                        ),
                        Text(
                          artistOf(item),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.texts.bodySmall
                              ?.copyWith(color: context.scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.playlist_play_rounded),
              title: const Text('Putar berikutnya'),
              onTap: () => Navigator.of(context).pop(true),
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add_rounded),
              title: const Text('Tambahkan ke akhir antrean'),
              onTap: () => Navigator.of(context).pop(false),
            ),
            const SizedBox(height: kSpaceSm),
          ],
        ),
      ),
    );
    if (next != null) onAddToQueue?.call(next);
  }
}

/// Kartu rak horizontal (album/artis/playlist).
class ShelfCard extends StatelessWidget {
  const ShelfCard({super.key, required this.item, required this.onOpen});

  final MusicItem item;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = context.scheme;
    final bool circle = item.type == 'artist';
    final String subtitle = artistOf(item).isNotEmpty
        ? artistOf(item)
        : (item.subtitle ?? _capitalize(item.type));
    return SizedBox(
      width: 150,
      child: InkWell(
        borderRadius: BorderRadius.circular(kRadiusMd),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(kSpaceXs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              CoverArt(
                url: item.thumbnail,
                size: 150,
                radius: kRadiusMd,
                circle: circle,
                icon: circle ? Icons.person_rounded : Icons.album_rounded,
              ),
              const SizedBox(height: kSpaceSm),
              Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.texts.bodyLarge?.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (subtitle.isNotEmpty)
                Text(
                  subtitle,
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
      ),
    );
  }
}

/// Tinggi tetap rak [MusicShelf] (sampul 150 + teks dua baris).
const double kShelfHeight = 202;

/// Rak horizontal satu sumber untuk Home/Search/Browse — menggantikan tiga
/// salinan pola `SizedBox(height: 214)` + `ListView.separated`.
class MusicShelf extends StatelessWidget {
  const MusicShelf({super.key, required this.items, required this.onOpen});

  final List<MusicItem> items;
  final void Function(MusicItem item) onOpen;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kShelfHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: kSpaceLg),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: kSpaceMd),
        itemBuilder: (BuildContext context, int index) =>
            ShelfCard(item: items[index], onOpen: () => onOpen(items[index])),
      ),
    );
  }
}

/// Kotak skeleton dengan kilau berjalan. Hormat `MediaQuery.disableAnimations`.
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 12,
    this.radius = kRadiusSm,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = context.scheme;
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            ColoredBox(color: scheme.surfaceContainer),
            AnimatedBuilder(
              animation: _controller,
              builder: (BuildContext context, Widget? _) {
                final double t = (_controller.value * 2) - 1;
                return FractionallySizedBox(
                  alignment: Alignment(t, 0),
                  widthFactor: 0.6,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: <Color>[
                          Colors.transparent,
                          (dark ? Colors.white : Colors.black)
                              .withValues(alpha: 0.05),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Kerangka muat beranda: dua rak + daftar baris, meniru bentuk akhir.
class SkeletonHomeFeed extends StatelessWidget {
  const SkeletonHomeFeed({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: kSpaceMd, bottom: kSpaceXxl),
      children: <Widget>[
        const Padding(
          padding: EdgeInsets.fromLTRB(kSpaceLg, 0, kSpaceLg, kSpaceMd),
          child: SkeletonBox(width: 140, height: 20, radius: 6),
        ),
        SizedBox(
          height: 160,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: kSpaceLg),
            itemCount: 3,
            separatorBuilder: (_, _) => const SizedBox(width: kSpaceMd),
            itemBuilder: (BuildContext context, int index) =>
                const SkeletonBox(width: 150, height: 150, radius: kRadiusMd),
          ),
        ),
        const SizedBox(height: kSpaceXl),
        const Padding(
          padding: EdgeInsets.fromLTRB(kSpaceLg, 0, kSpaceLg, kSpaceMd),
          child: SkeletonBox(width: 180, height: 20, radius: 6),
        ),
        SizedBox(
          height: 220,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: kSpaceLg),
            itemCount: 2,
            separatorBuilder: (_, _) => const SizedBox(width: kSpaceMd),
            itemBuilder: (BuildContext context, int index) => const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SkeletonBox(width: 150, height: 150, radius: kRadiusMd),
                SizedBox(height: kSpaceSm),
                SkeletonBox(width: 110, height: 12),
                SizedBox(height: kSpaceXs),
                SkeletonBox(width: 70, height: 10),
              ],
            ),
          ),
        ),
        const SizedBox(height: kSpaceLg),
        for (int i = 0; i < 4; i++) ...<Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: kSpaceLg,
              vertical: kSpaceMd,
            ),
            child: Row(
              children: <Widget>[
                const SkeletonBox(width: 44, height: 44),
                const SizedBox(width: kSpaceMd),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SkeletonBox(height: 12),
                      SizedBox(height: kSpaceXs),
                      SkeletonBox(width: 120, height: 10),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Keadaan kosong yang ramah dengan aksi opsional.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = context.scheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(kSpaceXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: scheme.surfaceContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 34, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: kSpaceLg),
            Text(title, style: context.texts.titleMedium, textAlign: TextAlign.center),
            if (message != null) ...<Widget>[
              const SizedBox(height: kSpaceSm),
              Text(
                message!,
                style: context.texts.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...<Widget>[
              const SizedBox(height: kSpaceXl),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Keadaan galat dengan tombol coba lagi.
class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    required this.message,
    this.onRetry,
    this.title = 'Tidak bisa memuat',
  });

  final String message;
  final VoidCallback? onRetry;
  final String title;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = context.scheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(kSpaceXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.cloud_off_rounded, size: 44, color: scheme.onSurfaceVariant),
            const SizedBox(height: kSpaceLg),
            Text(title, style: context.texts.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: kSpaceSm),
            Text(
              message,
              style: context.texts.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...<Widget>[
              const SizedBox(height: kSpaceXl),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Coba lagi'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Indikator muat tengah (dipakai layar non-feed; feed memakai skeleton).
class LoadingState extends StatelessWidget {
  const LoadingState({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const CircularProgressIndicator(),
          if (label != null) ...<Widget>[
            const SizedBox(height: kSpaceLg),
            Text(
              label!,
              style: context.texts.bodyMedium
                  ?.copyWith(color: context.scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

/// Menampilkan pesan singkat yang konsisten di seluruh aplikasi.
void showSonoraSnack(BuildContext context, String message, {bool success = false}) {
  final SonoraColors sonora = context.sonora;
  final ColorScheme scheme = context.scheme;
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  messenger
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: <Widget>[
            Icon(
              success ? Icons.check_circle_rounded : Icons.info_outline_rounded,
              color: success ? sonora.success : scheme.onInverseSurface,
              size: 20,
            ),
            const SizedBox(width: kSpaceMd),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
}

String _capitalize(String value) =>
    value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);
