/// Widget bersama: gambar sampul, baris lagu, kartu rak, header seksi, dan
/// keadaan kosong/galat. Semua mengambil warna dari tema Sonora.
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

/// Header seksi bergaya kanon streaming: judul besar, tanpa kicker.
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(kSpaceLg, kSpaceMd, kSpaceSm, kSpaceSm),
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

/// Baris lagu dengan aksi putar dan antrean.
class SongRow extends StatelessWidget {
  const SongRow({
    super.key,
    required this.item,
    required this.onPlay,
    this.onAddToQueue,
    this.active = false,
    this.trailing,
  });

  final MusicItem item;
  final VoidCallback onPlay;
  final void Function(bool next)? onAddToQueue;
  final bool active;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = context.scheme;
    final SonoraColors sonora = context.sonora;
    final bool playable = item.isPlayable;
    final String subtitle = subtitleOf(item);
    return InkWell(
      onTap: playable ? onPlay : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: kSpaceLg, vertical: kSpaceSm),
        child: Row(
          children: <Widget>[
            CoverArt(url: item.thumbnail, size: 48),
            const SizedBox(width: kSpaceMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: active ? sonora.accentText : scheme.onSurface,
                    ),
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            if (active)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: kSpaceSm),
                child: Icon(Icons.graphic_eq_rounded, size: 20, color: sonora.accentText),
              ),
            if (trailing != null)
              trailing!
            else if (onAddToQueue != null && playable)
              IconButton(
                tooltip: 'Tambahkan ke antrean',
                icon: const Icon(Icons.playlist_add_rounded),
                onPressed: () => _showQueueMenu(context),
              ),
          ],
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
      width: 152,
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
                size: 144,
                circle: circle,
                icon: circle ? Icons.person_rounded : Icons.album_rounded,
              ),
              const SizedBox(height: kSpaceSm),
              Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.texts.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              if (subtitle.isNotEmpty)
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
            ],
          ),
        ),
      ),
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
                color: scheme.surfaceContainerHigh,
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

/// Indikator muat tengah.
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
