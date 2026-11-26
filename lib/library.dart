import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'models.dart';

/// Legge i tag di una lista di file (eseguito in un isolate separato).
List<Map<String, dynamic>> _readTags(List<String> paths) {
  final out = <Map<String, dynamic>>[];
  for (final path in paths) {
    Track t = Track.fromFileName(path);
    try {
      final m = readMetadata(File(path), getImage: false);
      String clean(String? s) => (s ?? '').trim();
      final title = clean(m.title);
      final artist = clean(m.artist).isNotEmpty ? clean(m.artist) : clean(m.albumArtist);
      final album = clean(m.album);
      final genre = m.genres.map((g) => g.trim()).where((g) => g.isNotEmpty).join(', ');
      t = Track(
        path: path,
        title: title.isNotEmpty ? title : t.title,
        artist: artist.isNotEmpty ? artist : t.artist,
        album: album.isNotEmpty ? album : kUnknownAlbum,
        genre: genre.isNotEmpty ? _normalizeGenre(genre) : kUnknownGenre,
        year: m.year?.year,
        trackNumber: m.trackNumber,
        durationMs: m.duration?.inMilliseconds ?? 0,
      );
    } catch (_) {
      // Formato senza tag leggibili: si usa il nome del file.
    }
    out.add(t.toJson());
  }
  return out;
}

/// Uniforma i generi (es. "(17)" ID3v1, maiuscole).
String _normalizeGenre(String g) {
  final id3 = RegExp(r'^\((\d+)\)').firstMatch(g);
  if (id3 != null) {
    final n = int.parse(id3.group(1)!);
    if (n < _id3Genres.length) return _id3Genres[n];
  }
  final n = int.tryParse(g);
  if (n != null && n < _id3Genres.length) return _id3Genres[n];
  if (g.isEmpty) return kUnknownGenre;
  return g[0].toUpperCase() + g.substring(1);
}

const _id3Genres = [
  'Blues', 'Classic Rock', 'Country', 'Dance', 'Disco', 'Funk', 'Grunge',
  'Hip-Hop', 'Jazz', 'Metal', 'New Age', 'Oldies', 'Other', 'Pop', 'R&B',
  'Rap', 'Reggae', 'Rock', 'Techno', 'Industrial', 'Alternative', 'Ska',
  'Death Metal', 'Pranks', 'Soundtrack', 'Euro-Techno', 'Ambient',
  'Trip-Hop', 'Vocal', 'Jazz+Funk', 'Fusion', 'Trance', 'Classical',
  'Instrumental', 'Acid', 'House', 'Game', 'Sound Clip', 'Gospel', 'Noise',
  'Alternative Rock', 'Bass', 'Soul', 'Punk', 'Space', 'Meditative',
  'Instrumental Pop', 'Instrumental Rock', 'Ethnic', 'Gothic', 'Darkwave',
  'Techno-Industrial', 'Electronic', 'Pop-Folk', 'Eurodance', 'Dream',
  'Southern Rock', 'Comedy', 'Cult', 'Gangsta', 'Top 40', 'Christian Rap',
  'Pop/Funk', 'Jungle', 'Native American', 'Cabaret', 'New Wave',
  'Psychedelic', 'Rave', 'Showtunes', 'Trailer', 'Lo-Fi', 'Tribal',
  'Acid Punk', 'Acid Jazz', 'Polka', 'Retro', 'Musical', 'Rock & Roll',
  'Hard Rock',
];

Uint8List? _readCover(String path) {
  try {
    final m = readMetadata(File(path), getImage: true);
    if (m.pictures.isNotEmpty) return m.pictures.first.bytes;
  } catch (_) {}
  return null;
}

/// Raggruppamenti disponibili nella libreria.
enum Catalog { titolo, artista, genere, album, cartella }

extension CatalogLabel on Catalog {
  String get label => switch (this) {
        Catalog.titolo => 'Titolo',
        Catalog.artista => 'Artista',
        Catalog.genere => 'Genere',
        Catalog.album => 'Album',
        Catalog.cartella => 'Cartella',
      };
}

class Library extends ChangeNotifier {
  List<Track> tracks = [];
  final Map<String, Track> _byPath = {};
  bool scanning = false;
  int scanFound = 0;
  String scanStatus = '';

  Track? byPath(String path) => _byPath[path];

  Track trackFor(String path) => _byPath[path] ?? Track.fromFileName(path);

  Future<File> _cacheFile() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, 'libreria.json'));
  }

  Future<void> load() async {
    try {
      final f = await _cacheFile();
      if (await f.exists()) {
        final list = jsonDecode(await f.readAsString()) as List;
        _set(list.map((e) => Track.fromJson(e as Map<String, dynamic>)).toList());
      }
    } catch (_) {}
  }

  void _set(List<Track> list) {
    tracks = list;
    _byPath
      ..clear()
      ..addEntries(list.map((t) => MapEntry(t.path, t)));
    _sortTracks();
    notifyListeners();
  }

  void _sortTracks() {
    tracks.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  }

  Future<void> _saveCache() async {
    try {
      final f = await _cacheFile();
      await f.parent.create(recursive: true);
      await f.writeAsString(jsonEncode(tracks.map((t) => t.toJson()).toList()));
    } catch (_) {}
  }

  /// Cerca i file audio nelle cartelle e ne legge i tag.
  Future<void> scan(List<String> folders) async {
    if (scanning) return;
    scanning = true;
    scanFound = 0;
    scanStatus = 'Cerco i brani...';
    notifyListeners();

    final found = <String>{};
    for (final folder in folders) {
      final dir = Directory(folder);
      if (!await dir.exists()) continue;
      try {
        await for (final e in dir.list(recursive: true, followLinks: false).handleError((_) {})) {
          if (e is File && isAudioFile(e.path)) {
            found.add(e.path);
            if (found.length % 50 == 0) {
              scanFound = found.length;
              notifyListeners();
            }
          }
        }
      } catch (_) {}
    }
    scanFound = found.length;

    // I brani già noti non vengono riletti.
    final known = <Track>[];
    final toRead = <String>[];
    for (final path in found) {
      final t = _byPath[path];
      if (t != null) {
        known.add(t);
      } else {
        toRead.add(path);
      }
    }

    final result = <Track>[...known];
    const batch = 200;
    for (var i = 0; i < toRead.length; i += batch) {
      final chunk = toRead.sublist(i, (i + batch).clamp(0, toRead.length));
      scanStatus = 'Leggo le informazioni: ${i + chunk.length} di ${toRead.length}';
      notifyListeners();
      final maps = await Isolate.run(() => _readTags(chunk));
      result.addAll(maps.map(Track.fromJson));
    }

    _set(result);
    await _saveCache();
    scanning = false;
    scanStatus = '';
    notifyListeners();
  }

  /// Aggiunge file singoli (anche fuori dalle cartelle della libreria).
  Future<List<Track>> addFiles(List<String> paths) async {
    final audio = paths.where(isAudioFile).toList();
    final newPaths = audio.where((x) => !_byPath.containsKey(x)).toList();
    if (newPaths.isNotEmpty) {
      final maps = await Isolate.run(() => _readTags(newPaths));
      _set([...tracks, ...maps.map(Track.fromJson)]);
      await _saveCache();
    }
    return audio.map(trackFor).toList();
  }

  static Future<Uint8List?> cover(String path) => Isolate.run(() => _readCover(path));

  /// Restituisce i gruppi (nome -> brani) per il catalogo scelto.
  Map<String, List<Track>> groups(Catalog c) {
    final map = <String, List<Track>>{};
    for (final t in tracks) {
      final keys = switch (c) {
        Catalog.titolo => [t.title.isEmpty ? '#' : _initial(t.title)],
        Catalog.artista => [t.artist],
        Catalog.genere => t.genre.split(',').map((g) => g.trim()).where((g) => g.isNotEmpty).toList(),
        Catalog.album => [t.album],
        Catalog.cartella => [t.folder],
      };
      for (final k in keys.isEmpty ? [kUnknownGenre] : keys) {
        (map[k] ??= []).add(t);
      }
    }
    final sortedKeys = map.keys.toList()
      ..sort((a, b) {
        // Gli "sconosciuti" vanno in fondo.
        final ua = a.endsWith('sconosciuto') ? 1 : 0;
        final ub = b.endsWith('sconosciuto') ? 1 : 0;
        if (ua != ub) return ua - ub;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });
    final out = <String, List<Track>>{};
    for (final k in sortedKeys) {
      final list = map[k]!;
      if (c == Catalog.album) {
        list.sort((a, b) => (a.trackNumber ?? 999).compareTo(b.trackNumber ?? 999));
      }
      out[k] = list;
    }
    return out;
  }

  static String _initial(String s) {
    final ch = s.trim().isEmpty ? '#' : s.trim()[0].toUpperCase();
    return RegExp(r'[A-ZÀ-Ý]').hasMatch(ch) ? ch : '#';
  }

  List<Track> search(String q) {
    final s = q.toLowerCase().trim();
    if (s.isEmpty) return tracks;
    return tracks
        .where((t) =>
            t.title.toLowerCase().contains(s) ||
            t.artist.toLowerCase().contains(s) ||
            t.album.toLowerCase().contains(s) ||
            t.genre.toLowerCase().contains(s))
        .toList();
  }
}
