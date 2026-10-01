/// Model data untuk kontrak respons proxy Sonora.
///
/// Parsing toleran: field tak dikenal diabaikan dan nilai salah tipe
/// diturunkan ke default aman. Hanya dua model yang dibutuhkan UI/audio:
/// [MusicItem] dan [MusicSection].
library;

Map<String, Object?> _object(Object? value) {
  if (value is! Map) return const <String, Object?>{};
  final out = <String, Object?>{};
  for (final entry in value.entries) {
    out[entry.key.toString()] = entry.value;
  }
  return out;
}

List<Object?> _list(Object? value) =>
    value is List ? value : const <Object?>[];

String? _string(Object? value) {
  if (value is String) return value.isEmpty ? null : value;
  if (value is num || value is bool) return value.toString();
  return null;
}

String _text(Object? value) => _string(value) ?? '';

/// Satu kartu pada feed (song/album/playlist/artist).
class MusicItem {
  const MusicItem({
    required this.type,
    required this.title,
    this.subtitle,
    this.thumbnail,
    this.videoId,
    this.browseId,
    this.playlistId,
    this.duration,
    this.artist = '',
  });

  final String type;
  final String title;
  final String? subtitle;
  final String? thumbnail;
  final String? videoId;
  final String? browseId;
  final String? playlistId;
  final String? duration;
  final String artist;

  /// Dapat diputar bila punya videoId yang tidak kosong.
  bool get isPlayable {
    final id = videoId;
    return id != null && id.isNotEmpty;
  }

  /// Target navigasi: [browseId] bila ada, selain itu [playlistId] yang
  /// dinormalkan ke bentuk kanonik `VL...`.
  String? get browseTarget {
    final browse = browseId;
    if (browse != null && browse.isNotEmpty) return browse;
    final playlist = playlistId;
    if (playlist != null && playlist.isNotEmpty) {
      return playlist.startsWith('VL') ? playlist : 'VL$playlist';
    }
    return null;
  }

  factory MusicItem.fromJson(Object? value) {
    final map = _object(value);
    final artistNames = _artistFrom(map['artists']);
    final subtitle = _string(map['subtitle']);
    return MusicItem(
      type: _text(map['type']),
      title: _text(map['title']),
      subtitle: subtitle,
      thumbnail: _string(map['thumbnail']),
      videoId: _string(map['videoId']),
      browseId: _string(map['browseId']),
      playlistId: _string(map['playlistId']),
      duration: _string(map['duration']),
      artist: artistNames.isNotEmpty ? artistNames : (subtitle ?? ''),
    );
  }
}

/// Sekelompok item berjudul (mis. "Quick picks", "Songs").
class MusicSection {
  const MusicSection({
    required this.title,
    this.items = const <MusicItem>[],
  });

  final String title;
  final List<MusicItem> items;

  factory MusicSection.fromJson(Object? value) {
    final map = _object(value);
    return MusicSection(
      title: _text(map['title']),
      items: _list(
        map['items'],
      ).map(MusicItem.fromJson).toList(growable: false),
    );
  }
}

/// Menggabungkan nama-nama artis (`artists[].name`) menjadi satu string.
String _artistFrom(Object? value) {
  final names = <String>[];
  for (final entry in _list(value)) {
    final name = _string(_object(entry)['name']);
    if (name != null) names.add(name);
  }
  return names.join(', ');
}
