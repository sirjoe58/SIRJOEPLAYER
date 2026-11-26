import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import 'bluetooth.dart';
import 'importer.dart';
import 'library.dart';
import 'models.dart';
import 'player_service.dart';
import 'playlists.dart';
import 'settings.dart';

class AppState {
  final settings = Settings();
  final library = Library();
  final playlists = PlaylistStore();
  final bt = BluetoothService();
  late final PlayerService player = PlayerService(settings, library);

  /// Su Android chiede il permesso di leggere la musica.
  Future<bool> ensureMusicPermission() async {
    if (!Platform.isAndroid) return true;
    final audio = await Permission.audio.request();
    if (audio.isGranted) return true;
    final storage = await Permission.storage.request();
    return storage.isGranted;
  }

  /// Prima apertura su Android: usa le cartelle Musica e Download.
  Future<void> firstRunSetup() async {
    if (!Platform.isAndroid || settings.folders.isNotEmpty) return;
    if (!await ensureMusicPermission()) return;
    final candidates = ['/storage/emulated/0/Music', '/storage/emulated/0/Download'];
    final existing = <String>[];
    for (final c in candidates) {
      if (await Directory(c).exists()) existing.add(c);
    }
    if (existing.isEmpty) return;
    settings.folders = existing;
    await settings.save();
    await library.scan(settings.folders);
  }

  /// La cartella dei brani importati fa sempre parte della libreria.
  Future<void> ensureImportFolderInLibrary() async {
    final dest = await Importer.destinationDir();
    if (!settings.folders.contains(dest)) {
      settings.folders = [...settings.folders, dest];
      await settings.save();
    }
  }

  Future<bool> addFolder() async {
    if (!await ensureMusicPermission()) return false;
    final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Scegli una cartella di musica');
    if (dir == null) return false;
    if (!settings.folders.contains(dir)) {
      settings.folders = [...settings.folders, dir];
      await settings.save();
    }
    await library.scan(settings.folders);
    return true;
  }

  Future<List<Track>> pickFiles() async {
    if (!await ensureMusicPermission()) return [];
    final res = await FilePicker.platform.pickFiles(
      dialogTitle: 'Scegli i brani',
      allowMultiple: true,
      type: Platform.isAndroid ? FileType.audio : FileType.custom,
      allowedExtensions: Platform.isAndroid ? null : kAudioExtensions.toList(),
    );
    if (res == null) return [];
    final paths = res.paths.whereType<String>().toList();
    return library.addFiles(paths);
  }
}

final app = AppState();
