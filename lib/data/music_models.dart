/// Model data yang memetakan kontrak respons proxy Sonora
/// (`packages/proxy/src/parsers.ts`).
///
/// Parsing sengaja toleran: field tak dikenal diabaikan dan nilai yang salah
/// tipe diturunkan ke default aman, sehingga satu baris rusak tidak pernah
/// menggagalkan seluruh feed. Seluruh model memiliki konstruktor `const` dan
/// `fromJson` yang menerima `Object?` apa pun.
library;

/// Helper bersama untuk koersi JSON yang defensif. Dipakai juga oleh
/// `sonora_api.dart` supaya validasi payload konsisten.
Map<String, Object?> jsonObject(Object? value) {
  if (value is! Map) return const <String, Object?>{};
  final out = <String, Object?>{};
  for (final entry in value.entries) {
    out[entry.key.toString()] = entry.value;
  }
  return out;
}

List<Object?> jsonList(Object? value) =>
    value is List ? value : const <Object?>[];

/// String apa adanya; string kosong dianggap tidak ada (`null`).
String? jsonString(Object? value) {
  if (value == null) return null;
  if (value is String) return value.isEmpty ? null : value;
  if (value is num || value is bool) return value.toString();
  return null;
}

String jsonText(Object? value, [String fallback = '']) =>
    jsonString(value) ?? fallback;

int? jsonInt(Object? value) {
  if (value is int) return value;
  if (value is double) return value.isFinite ? value.toInt() : null;
  if (value is String) return int.tryParse(value.trim());
  return null;
}

bool jsonBool(Object? value, {bool fallback = false}) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'true') return true;
    if (normalized == 'false') return false;
  }
  return fallback;
}

/// Mengubah durasi `"m:ss"` atau `"h:mm:ss"` menjadi milidetik.
/// Mengembalikan `null` untuk nilai kosong/format tak dikenal.
int? parseDurationMs(String? value) {
  final raw = value?.trim();
  if (raw == null || raw.isEmpty) return null;
  final parts = raw.split(':');
  if (parts.length < 2 || parts.length > 3) return null;
  var seconds = 0;
  for (final part in parts) {
    final amount = int.tryParse(part.trim());
    if (amount == null || amount < 0) return null;
    seconds = seconds * 60 + amount;
  }
  return seconds * 1000;
}

/// Artis/album yang direferensikan pada sebuah item.
class MusicPerson {
  const MusicPerson({required this.name, this.browseId});

  final String name;
  final String? browseId;

  static MusicPerson? fromJson(Object? value) {
    final map = jsonObject(value);
    final name = jsonString(map['name']);
    if (name == null) return null;
    return MusicPerson(name: name, browseId: jsonString(map['browseId']));
  }

  @override
  String toString() => 'MusicPerson($name)';
}

/// Satu kartu pada feed (song/album/playlist/artist).
class MusicItem {
  const MusicItem({
    required this.type,
    required this.title,
    this.subtitle,
    this.thumbnail,
    this.artists = const <MusicPerson>[],
    this.album,
    this.duration,
    this.videoId,
    this.playlistId,
    this.browseId,
    this.browseType,
    this.watchPlaylist = false,
  });

  final String type;
  final String title;
  final String? subtitle;
  final String? thumbnail;
  final List<MusicPerson> artists;
  final MusicPerson? album;
  final String? duration;
  final String? videoId;
  final String? playlistId;
  final String? browseId;
  final String? browseType;
  final bool watchPlaylist;

  bool get isSong => type == 'song';
  bool get isAlbum => type == 'album';
  bool get isPlaylist => type == 'playlist';
  bool get isPlayable => videoId != null;
  int? get durationMs => parseDurationMs(duration);

  /// Target navigasi paling relevan untuk item ini.
  String? get browseTarget => browseId ?? playlistId ?? videoId;

  factory MusicItem.fromJson(Object? value) {
    final map = jsonObject(value);
    final artists = jsonList(map['artists'])
        .map(MusicPerson.fromJson)
        .whereType<MusicPerson>()
        .toList(growable: false);
    return MusicItem(
      type: jsonText(map['type'], 'unknown'),
      title: jsonText(map['title']),
      subtitle: jsonString(map['subtitle']),
      thumbnail: jsonString(map['thumbnail']),
      artists: artists,
      album: MusicPerson.fromJson(map['album']),
      duration: jsonString(map['duration']),
      videoId: jsonString(map['videoId']),
      playlistId: jsonString(map['playlistId']),
      browseId: jsonString(map['browseId']),
      browseType: jsonString(map['browseType']),
      watchPlaylist: jsonBool(map['watchPlaylist']),
    );
  }

  @override
  String toString() => 'MusicItem($type, $title)';
}

/// Sekelompok item berjudul (mis. "Quick picks", "Songs").
class MusicSection {
  const MusicSection({
    required this.title,
    this.items = const <MusicItem>[],
    this.list = false,
  });

  final String title;
  final List<MusicItem> items;
  final bool list;

  bool get isEmpty => items.isEmpty;

  factory MusicSection.fromJson(Object? value) {
    final map = jsonObject(value);
    return MusicSection(
      title: jsonText(map['title']),
      items: jsonList(
        map['items'],
      ).map(MusicItem.fromJson).toList(growable: false),
      list: jsonBool(map['list']),
    );
  }
}

/// Respons feed standar: `{ "sections": [...] }` untuk /home, /search,
/// /library, /history.
class MusicFeed {
  const MusicFeed({this.sections = const <MusicSection>[]});

  static const MusicFeed empty = MusicFeed();

  final List<MusicSection> sections;

  bool get isEmpty => sections.every((section) => section.items.isEmpty);

  /// Semua item dari seluruh section, berurutan.
  List<MusicItem> get items => [
    for (final section in sections) ...section.items,
  ];

  factory MusicFeed.fromJson(Object? value) {
    final map = jsonObject(value);
    return MusicFeed(
      sections: jsonList(
        map['sections'],
      ).map(MusicSection.fromJson).toList(growable: false),
    );
  }
}

/// Satu entri antrean dari /next.
class QueueItem {
  const QueueItem({
    required this.videoId,
    this.title = '',
    this.artist = '',
    this.duration = '',
    this.thumbnail,
    this.selected = false,
  });

  final String videoId;
  final String title;
  final String artist;
  final String duration;
  final String? thumbnail;
  final bool selected;

  bool get isPlayable => videoId.isNotEmpty;
  int? get durationMs => parseDurationMs(duration);

  factory QueueItem.fromJson(Object? value) {
    final map = jsonObject(value);
    return QueueItem(
      videoId: jsonText(map['videoId']),
      title: jsonText(map['title']),
      artist: jsonText(map['artist']),
      duration: jsonText(map['duration']),
      thumbnail: jsonString(map['thumbnail']),
      selected: jsonBool(map['selected']),
    );
  }

  @override
  String toString() => 'QueueItem($videoId, $title)';
}

/// Respons /next dan /next/continue.
class PlaybackQueue {
  const PlaybackQueue({this.queue = const <QueueItem>[], this.continuation});

  final List<QueueItem> queue;
  final String? continuation;

  bool get isEmpty => queue.isEmpty;

  /// Item yang ditandai `selected` oleh upstream, bila ada.
  QueueItem? get selected {
    for (final item in queue) {
      if (item.selected) return item;
    }
    return null;
  }

  factory PlaybackQueue.fromJson(Object? value) {
    final map = jsonObject(value);
    return PlaybackQueue(
      queue: jsonList(
        map['queue'],
      ).map(QueueItem.fromJson).toList(growable: false),
      continuation: jsonString(map['continuation']),
    );
  }
}

/// Respons /player: URL stream langsung dari googlevideo.
class PlayerInfo {
  const PlayerInfo({
    required this.videoId,
    required this.url,
    this.mimeType = '',
    this.bitrate = 0,
    this.audioQuality = '',
    this.title = '',
    this.artist = '',
    this.durationMs = 0,
  });

  final String videoId;
  final String url;
  final String mimeType;
  final int bitrate;
  final String audioQuality;
  final String title;
  final String artist;
  final int durationMs;

  bool get isUsable => url.isNotEmpty;
  Uri? get urlUri => Uri.tryParse(url);

  factory PlayerInfo.fromJson(Object? value) {
    final map = jsonObject(value);
    return PlayerInfo(
      videoId: jsonText(map['videoId']),
      url: jsonText(map['url']),
      mimeType: jsonText(map['mimeType']),
      bitrate: jsonInt(map['bitrate']) ?? 0,
      audioQuality: jsonText(map['audioQuality']),
      title: jsonText(map['title']),
      artist: jsonText(map['artist']),
      durationMs: jsonInt(map['durationMs']) ?? 0,
    );
  }
}

/// Satu baris lirik; `startMs`/`endMs` null untuk lirik tak tersinkron.
class LyricsLine {
  const LyricsLine({required this.text, this.startMs, this.endMs});

  final String text;
  final int? startMs;
  final int? endMs;

  factory LyricsLine.fromJson(Object? value) {
    final map = jsonObject(value);
    return LyricsLine(
      text: jsonText(map['text']),
      startMs: jsonInt(map['startMs']),
      endMs: jsonInt(map['endMs']),
    );
  }
}

/// Objek `lyrics` di dalam respons /lyrics.
class Lyrics {
  const Lyrics({
    this.lines = const <LyricsLine>[],
    this.synced = false,
    this.source,
  });

  final List<LyricsLine> lines;
  final bool synced;
  final String? source;

  bool get hasLines => lines.isNotEmpty;

  factory Lyrics.fromJson(Object? value) {
    final map = jsonObject(value);
    return Lyrics(
      lines: jsonList(
        map['lines'],
      ).map(LyricsLine.fromJson).toList(growable: false),
      synced: jsonBool(map['synced']),
      source: jsonString(map['source']),
    );
  }
}

/// Status simpan/batal-simpan playlist milik akun.
class PlaylistLibraryState {
  const PlaylistLibraryState({required this.id, required this.saved});

  final String id;
  final bool saved;

  factory PlaylistLibraryState.fromJson(Object? value) {
    final map = jsonObject(value);
    return PlaylistLibraryState(
      id: jsonText(map['id']),
      saved: jsonBool(map['saved']),
    );
  }
}

/// Respons /browse: sections plus metadata library opsional.
class BrowseResult {
  const BrowseResult({this.sections = const <MusicSection>[], this.playlist});

  final List<MusicSection> sections;
  final PlaylistLibraryState? playlist;

  factory BrowseResult.fromJson(Object? value) {
    final map = jsonObject(value);
    final playlist = map['playlist'];
    return BrowseResult(
      sections: jsonList(
        map['sections'],
      ).map(MusicSection.fromJson).toList(growable: false),
      playlist: playlist == null
          ? null
          : PlaylistLibraryState.fromJson(playlist),
    );
  }
}

/// Respons /healthz.
class HealthStatus {
  const HealthStatus({required this.ok, this.ts = 0});

  final bool ok;
  final int ts;

  factory HealthStatus.fromJson(Object? value) {
    final map = jsonObject(value);
    return HealthStatus(ok: jsonBool(map['ok']), ts: jsonInt(map['ts']) ?? 0);
  }
}
