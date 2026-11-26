import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'models.dart';

class PlaylistStore extends ChangeNotifier {
  List<SavedPlaylist> items = [];

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, 'playlist.json'));
  }

  Future<void> load() async {
    try {
      final f = await _file();
      if (await f.exists()) {
        final list = jsonDecode(await f.readAsString()) as List;
        items = list.map((e) => SavedPlaylist.fromJson(e as Map<String, dynamic>)).toList();
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    final f = await _file();
    await f.parent.create(recursive: true);
    await f.writeAsString(jsonEncode(items.map((e) => e.toJson()).toList()));
    notifyListeners();
  }

  SavedPlaylist create(String name, [List<String> paths = const []]) {
    final pl = SavedPlaylist(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name.trim().isEmpty ? 'Nuova playlist' : name.trim(),
      paths: List.of(paths),
      updated: DateTime.now(),
    );
    items.insert(0, pl);
    _save();
    return pl;
  }

  void rename(SavedPlaylist pl, String name) {
    pl.name = name.trim();
    pl.updated = DateTime.now();
    _save();
  }

  void delete(SavedPlaylist pl) {
    items.remove(pl);
    _save();
  }

  void addTracks(SavedPlaylist pl, List<String> paths) {
    for (final x in paths) {
      if (!pl.paths.contains(x)) pl.paths.add(x);
    }
    pl.updated = DateTime.now();
    _save();
  }

  void removeAt(SavedPlaylist pl, int index) {
    pl.paths.removeAt(index);
    pl.updated = DateTime.now();
    _save();
  }

  void reorder(SavedPlaylist pl, int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    final x = pl.paths.removeAt(oldIndex);
    pl.paths.insert(newIndex, x);
    pl.updated = DateTime.now();
    _save();
  }

  void sortBy(SavedPlaylist pl, Comparable Function(String path) key) {
    pl.paths.sort((a, b) => key(a).compareTo(key(b)));
    pl.updated = DateTime.now();
    _save();
  }

  // ---- M3U ----

  String toM3u(SavedPlaylist pl, Track Function(String) info) {
    final b = StringBuffer('#EXTM3U\n#PLAYLIST:${pl.name}\n');
    for (final path in pl.paths) {
      final t = info(path);
      b.writeln('#EXTINF:${(t.durationMs / 1000).round()},${t.artist} - ${t.title}');
      b.writeln(path);
    }
    return b.toString();
  }

  static List<String> parseM3u(String content, String baseDir) {
    final out = <String>[];
    for (var line in const LineSplitter().convert(content)) {
      line = line.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      if (line.startsWith('file://')) {
        try {
          line = Uri.parse(line).toFilePath();
        } catch (_) {}
      }
      final path = p.isAbsolute(line) ? line : p.normalize(p.join(baseDir, line));
      out.add(path);
    }
    return out;
  }
}
