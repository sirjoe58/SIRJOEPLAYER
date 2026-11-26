import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'models.dart';

/// Un'unità esterna (chiavetta USB, disco esterno, scheda SD).
class Volume {
  final String path;
  final String label;
  final bool removable;
  const Volume(this.path, this.label, {this.removable = true});
}

class ImportResult {
  final List<String> copied;
  final int skipped;
  final int failed;
  final bool cancelled;
  const ImportResult(this.copied, this.skipped, this.failed, this.cancelled);
}

class Importer {
  static const _android = MethodChannel('sirjoe/bluetooth');

  /// Cartella dove vengono copiati i brani importati.
  static Future<String> destinationDir() async {
    String base;
    if (Platform.isAndroid) {
      base = '/storage/emulated/0/Music';
    } else {
      final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
      if (home != null && await Directory(p.join(home, 'Music')).exists()) {
        base = p.join(home, 'Music');
      } else {
        base = (await getApplicationDocumentsDirectory()).path;
      }
    }
    final dir = Directory(p.join(base, 'SirJoe Player'));
    await dir.create(recursive: true);
    return dir.path;
  }

  /// Trova i file audio in una cartella (anche nelle sottocartelle).
  static Future<List<String>> findAudio(String dir, {bool recursive = true}) async {
    final out = <String>[];
    final d = Directory(dir);
    if (!await d.exists()) return out;
    try {
      await for (final e in d.list(recursive: recursive, followLinks: false).handleError((_) {})) {
        if (e is File && isAudioFile(e.path)) out.add(e.path);
      }
    } catch (_) {}
    out.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return out;
  }

  /// Chiavette USB / dischi esterni collegati.
  static Future<List<Volume>> externalVolumes() async {
    final out = <Volume>[];
    try {
      if (Platform.isAndroid) {
        final storage = Directory('/storage');
        if (await storage.exists()) {
          await for (final e in storage.list(followLinks: false).handleError((_) {})) {
            final name = p.basename(e.path);
            if (name == 'emulated' || name == 'self') continue;
            if (e is Directory) out.add(Volume(e.path, 'Chiavetta / scheda $name'));
          }
        }
      } else if (Platform.isWindows) {
        final sys = (Platform.environment['SystemDrive'] ?? 'C:').toUpperCase();
        final r = await Process.run('powershell.exe', [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          r'Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -eq 2 -or $_.DriveType -eq 3 } | ForEach-Object { "$($_.DeviceID)|$($_.DriveType)|$($_.VolumeName)" }',
        ]);
        for (final line in (r.stdout as String).split('\n')) {
          final parts = line.trim().split('|');
          if (parts.length < 3) continue;
          final drive = parts[0].toUpperCase();
          if (drive == sys) continue;
          final removable = parts[1] == '2';
          final name = parts[2].trim().isEmpty ? (removable ? 'Chiavetta USB' : 'Disco') : parts[2].trim();
          out.add(Volume('$drive\\', '$name ($drive)', removable: removable));
        }
        // Le chiavette prima dei dischi.
        out.sort((a, b) => (a.removable == b.removable) ? a.path.compareTo(b.path) : (a.removable ? -1 : 1));
      } else if (Platform.isMacOS) {
        await for (final e in Directory('/Volumes').list(followLinks: false).handleError((_) {})) {
          if (await FileSystemEntity.isLink(e.path)) continue; // il disco di sistema
          if (e is Directory) out.add(Volume(e.path, p.basename(e.path)));
        }
      }
    } catch (_) {}
    return out;
  }

  /// Cartelle dove Android salva i file ricevuti via Bluetooth.
  static const androidBluetoothFolders = [
    '/storage/emulated/0/Download/Bluetooth',
    '/storage/emulated/0/Bluetooth',
    '/storage/emulated/0/Downloads/Bluetooth',
    '/storage/emulated/0/Download',
  ];

  /// Brani ricevuti via Bluetooth non ancora importati (Android).
  static Future<List<String>> bluetoothReceived(Set<String> alreadyImported) async {
    if (!Platform.isAndroid) return [];
    final found = <String>{};
    for (final f in androidBluetoothFolders) {
      // Nella cartella Download si guardano solo i file, non le sottocartelle.
      final recursive = !f.endsWith('/Download');
      found.addAll(await findAudio(f, recursive: recursive));
    }
    return found.where((x) => !alreadyImported.contains(x)).toList()..sort();
  }

  /// Copia i brani nella cartella di destinazione.
  /// Con [baseDir] mantiene le sottocartelle (es. Chiavetta/Album/brano.mp3 -> SirJoe Player/Chiavetta/Album/brano.mp3).
  static Future<ImportResult> copyFiles(
    List<String> files, {
    String? baseDir,
    String? subfolder,
    void Function(int done, int total, String current)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final dest = await destinationDir();
    final copied = <String>[];
    var skipped = 0, failed = 0;
    for (var i = 0; i < files.length; i++) {
      if (isCancelled?.call() == true) {
        return ImportResult(copied, skipped, failed, true);
      }
      final src = files[i];
      onProgress?.call(i, files.length, p.basename(src));
      try {
        String rel;
        if (baseDir != null && p.isWithin(baseDir, src)) {
          rel = p.relative(src, from: baseDir);
        } else {
          rel = p.basename(src);
        }
        var target = p.join(dest, subfolder ?? '', rel);
        final srcFile = File(src);
        final srcLen = await srcFile.length();
        final t = File(target);
        if (await t.exists()) {
          if (await t.length() == srcLen) {
            skipped++;
            copied.add(target); // già presente: va comunque nella libreria
            continue;
          }
          // Stesso nome ma file diverso: si aggiunge un numero.
          var n = 2;
          final dir = p.dirname(target), name = p.basenameWithoutExtension(target), ext = p.extension(target);
          while (await File(target).exists()) {
            target = p.join(dir, '$name ($n)$ext');
            n++;
          }
        }
        await Directory(p.dirname(target)).create(recursive: true);
        await srcFile.copy(target);
        copied.add(target);
      } catch (_) {
        failed++;
      }
    }
    onProgress?.call(files.length, files.length, '');
    if (Platform.isAndroid && copied.isNotEmpty) {
      // Avvisa Android dei nuovi brani (così li vedono anche le altre app).
      try {
        await _android.invokeMethod('scanFiles', {'paths': copied});
      } catch (_) {}
    }
    return ImportResult(copied, skipped, failed, false);
  }

  // ---- Strumenti del sistema ----

  static Future<void> openFolder(String path) async {
    if (Platform.isWindows) {
      await Process.run('explorer.exe', [path]);
    } else if (Platform.isMacOS) {
      await Process.run('open', [path]);
    }
  }

  /// Apre la procedura di Windows/Mac per ricevere file via Bluetooth.
  static Future<bool> bluetoothReceiveWizard() async {
    try {
      if (Platform.isWindows) {
        await Process.start('fsquirt.exe', ['-receive'], mode: ProcessStartMode.detached);
        return true;
      }
      if (Platform.isMacOS) {
        await Process.run('open', ['-a', 'Bluetooth File Exchange']);
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// Apre la procedura di Windows/Mac per inviare file via Bluetooth (es. al telefono).
  static Future<bool> bluetoothSendWizard() async {
    try {
      if (Platform.isWindows) {
        await Process.start('fsquirt.exe', ['-send'], mode: ProcessStartMode.detached);
        return true;
      }
      if (Platform.isMacOS) {
        await Process.run('open', ['-a', 'Bluetooth File Exchange']);
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// Cartella dove Windows/Mac di solito salvano i file ricevuti via Bluetooth.
  static String? desktopReceivedFolder() {
    final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    if (home == null) return null;
    if (Platform.isWindows) {
      for (final c in [
        p.join(home, 'Documents', 'Bluetooth Exchange Folder'),
        p.join(home, 'Documents', 'Cartella Scambio Bluetooth'),
        p.join(home, 'Downloads'),
      ]) {
        if (Directory(c).existsSync()) return c;
      }
    }
    if (Platform.isMacOS) return p.join(home, 'Downloads');
    return null;
  }
}
