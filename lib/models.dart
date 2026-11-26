import 'package:path/path.dart' as p;

/// Estensioni audio che il motore (mpv/FFmpeg) riesce a leggere.
const kAudioExtensions = <String>{
  'mp3', 'flac', 'wav', 'ogg', 'oga', 'opus', 'm4a', 'm4b', 'aac', 'wma',
  'ape', 'alac', 'aiff', 'aif', 'aifc', 'mka', 'mpc', 'wv', 'tta', 'dsf',
  'dff', 'ac3', 'dts', 'amr', 'au', 'caf', 'spx', 'mp2', 'mp4', 'webm',
  '3gp',
};

bool isAudioFile(String path) {
  final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
  return kAudioExtensions.contains(ext);
}

const kUnknownArtist = 'Artista sconosciuto';
const kUnknownAlbum = 'Album sconosciuto';
const kUnknownGenre = 'Genere sconosciuto';

class Track {
  final String path;
  final String title;
  final String artist;
  final String album;
  final String genre;
  final int? year;
  final int? trackNumber;
  final int durationMs;

  const Track({
    required this.path,
    required this.title,
    this.artist = kUnknownArtist,
    this.album = kUnknownAlbum,
    this.genre = kUnknownGenre,
    this.year,
    this.trackNumber,
    this.durationMs = 0,
  });

  String get folder => p.basename(p.dirname(path));
  String get extension => p.extension(path).replaceFirst('.', '').toUpperCase();

  /// Ricava titolo e artista dal nome del file ("Artista - Titolo.mp3").
  factory Track.fromFileName(String path) {
    final name = p.basenameWithoutExtension(path);
    final parts = name.split(' - ');
    if (parts.length >= 2) {
      return Track(
        path: path,
        artist: parts.first.trim(),
        title: parts.sublist(1).join(' - ').trim(),
      );
    }
    return Track(path: path, title: name);
  }

  Track copyWith({String? title, String? artist, String? album, String? genre, int? year}) => Track(
        path: path,
        title: title ?? this.title,
        artist: artist ?? this.artist,
        album: album ?? this.album,
        genre: genre ?? this.genre,
        year: year ?? this.year,
        trackNumber: trackNumber,
        durationMs: durationMs,
      );

  Map<String, dynamic> toJson() => {
        'p': path,
        't': title,
        'a': artist,
        'al': album,
        'g': genre,
        if (year != null) 'y': year,
        if (trackNumber != null) 'n': trackNumber,
        'd': durationMs,
      };

  factory Track.fromJson(Map<String, dynamic> j) => Track(
        path: j['p'] as String,
        title: (j['t'] as String?) ?? p.basenameWithoutExtension(j['p'] as String),
        artist: (j['a'] as String?) ?? kUnknownArtist,
        album: (j['al'] as String?) ?? kUnknownAlbum,
        genre: (j['g'] as String?) ?? kUnknownGenre,
        year: j['y'] as int?,
        trackNumber: j['n'] as int?,
        durationMs: (j['d'] as int?) ?? 0,
      );
}

class SavedPlaylist {
  String id;
  String name;
  List<String> paths;
  DateTime updated;

  SavedPlaylist({
    required this.id,
    required this.name,
    required this.paths,
    required this.updated,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'paths': paths,
        'updated': updated.toIso8601String(),
      };

  factory SavedPlaylist.fromJson(Map<String, dynamic> j) => SavedPlaylist(
        id: j['id'] as String,
        name: j['name'] as String,
        paths: (j['paths'] as List).cast<String>(),
        updated: DateTime.tryParse(j['updated'] as String? ?? '') ?? DateTime.now(),
      );
}

String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(h > 0 ? 2 : 1, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}
