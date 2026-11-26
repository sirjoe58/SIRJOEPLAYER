import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';

import 'bt_windows_script.dart';

class BtDevice {
  final String id;
  final String name;
  final bool connected;
  final bool isAudio;
  const BtDevice({
    required this.id,
    required this.name,
    this.connected = false,
    this.isAudio = true,
  });
}

/// Esito di un tentativo di collegamento automatico.
class BtResult {
  final bool ok;
  final String message;
  const BtResult(this.ok, this.message);
}

abstract class BtBackend {
  /// True se l'app può accendere il Bluetooth senza chiedere nulla.
  bool get canTurnOnSilently;
  Future<bool> ensurePermissions() async => true;
  Future<bool?> isOn();
  Future<bool> turnOn();
  Future<List<BtDevice>> paired();
  Future<bool> isConnected(String id);
  Future<bool> connect(String id);
  Future<void> openSystemSettings();

  static BtBackend? create() {
    if (kIsWeb) return null;
    if (Platform.isAndroid) return AndroidBt();
    if (Platform.isWindows) return WindowsBt();
    if (Platform.isMacOS) return MacBt();
    return null;
  }
}

// ---------------------------------------------------------------- Android

class AndroidBt extends BtBackend {
  static const _ch = MethodChannel('sirjoe/bluetooth');

  @override
  bool get canTurnOnSilently => false;

  @override
  Future<bool> ensurePermissions() async {
    final st = await Permission.bluetoothConnect.request();
    return st.isGranted || st.isLimited;
  }

  @override
  Future<bool?> isOn() async => await _ch.invokeMethod<bool>('isOn');

  @override
  Future<bool> turnOn() async => (await _ch.invokeMethod<bool>('turnOn')) ?? false;

  @override
  Future<List<BtDevice>> paired() async {
    final list = await _ch.invokeListMethod<Map>('paired') ?? [];
    return list
        .map((m) => BtDevice(
              id: m['id'] as String,
              name: (m['name'] as String?) ?? m['id'] as String,
              connected: (m['connected'] as bool?) ?? false,
              isAudio: (m['audio'] as bool?) ?? true,
            ))
        .toList();
  }

  @override
  Future<bool> isConnected(String id) async =>
      (await _ch.invokeMethod<bool>('isConnected', {'id': id})) ?? false;

  @override
  Future<bool> connect(String id) async =>
      (await _ch.invokeMethod<bool>('connect', {'id': id})) ?? false;

  @override
  Future<void> openSystemSettings() => _ch.invokeMethod('openSettings');
}

// ---------------------------------------------------------------- Windows

class WindowsBt extends BtBackend {
  String? _script;

  @override
  bool get canTurnOnSilently => true;

  Future<String> _scriptPath() async {
    if (_script != null) return _script!;
    final f = File(p.join(Directory.systemTemp.path, 'sirjoe_player_bt.ps1'));
    await f.writeAsString(kWindowsBtScript);
    return _script = f.path;
  }

  Future<String> _run(String action, [String addr = '']) async {
    final script = await _scriptPath();
    final r = await Process.run('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-WindowStyle',
      'Hidden',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      script,
      '-Action',
      action,
      if (addr.isNotEmpty) ...['-Addr', addr],
    ]).timeout(const Duration(seconds: 45));
    return (r.stdout as String).trim();
  }

  @override
  Future<bool?> isOn() async {
    try {
      final out = await _run('status');
      if (out.contains('NORADIO')) return null;
      return out.contains('On');
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> turnOn() async {
    try {
      final out = await _run('on');
      return out.contains('On');
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<BtDevice>> paired() async {
    try {
      final out = await _run('list');
      final devices = <BtDevice>[];
      for (final line in const LineSplitter().convert(out)) {
        final parts = line.split('|');
        if (parts.length < 4) continue;
        final cod = int.tryParse(parts[2]) ?? 0;
        final major = (cod >> 8) & 0x1F;
        devices.add(BtDevice(
          id: parts[0],
          connected: parts[1] == '1',
          isAudio: major == 4 || cod == 0,
          name: parts.sublist(3).join('|').trim().isEmpty ? parts[0] : parts.sublist(3).join('|').trim(),
        ));
      }
      return devices;
    } catch (_) {
      return [];
    }
  }

  @override
  Future<bool> isConnected(String id) async {
    final list = await paired();
    return list.any((d) => d.id == id && d.connected);
  }

  @override
  Future<bool> connect(String id) async {
    try {
      final out = await _run('connect', id);
      return out.contains('CONNECTED');
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> openSystemSettings() async {
    await Process.run('cmd', ['/c', 'start', 'ms-settings:bluetooth']);
  }
}

// ---------------------------------------------------------------- macOS

class MacBt extends BtBackend {
  String? _bin;

  @override
  bool get canTurnOnSilently => false;

  Future<String?> _blueutil() async {
    if (_bin != null) return _bin;
    final exe = Platform.resolvedExecutable; // .../Contents/MacOS/app
    final candidates = [
      p.join(p.dirname(p.dirname(exe)), 'Resources', 'blueutil'),
      '/opt/homebrew/bin/blueutil',
      '/usr/local/bin/blueutil',
    ];
    for (final c in candidates) {
      if (await File(c).exists()) return _bin = c;
    }
    return null;
  }

  Future<ProcessResult?> _run(List<String> args) async {
    final bin = await _blueutil();
    if (bin == null) return null;
    return Process.run(bin, args).timeout(const Duration(seconds: 30));
  }

  @override
  Future<bool?> isOn() async {
    try {
      final r = await _run(['-p']);
      if (r == null) return null;
      return (r.stdout as String).trim() == '1';
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> turnOn() async {
    // Apple non consente alle app di accendere il Bluetooth in modo ufficiale:
    // si prova comunque con blueutil; se non riesce si aprono le Impostazioni.
    try {
      await _run(['-p', '1']);
      await Future.delayed(const Duration(seconds: 2));
      return (await isOn()) == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<BtDevice>> paired() async {
    try {
      final r = await _run(['--paired', '--format', 'json']);
      if (r == null) return [];
      final list = jsonDecode(r.stdout as String) as List;
      return list.map((e) {
        final m = e as Map<String, dynamic>;
        final id = m['address'] as String;
        return BtDevice(
          id: id,
          name: (m['name'] as String?) ?? id,
          connected: m['connected'] == true,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<bool> isConnected(String id) async {
    try {
      final r = await _run(['--is-connected', id]);
      return r != null && (r.stdout as String).trim() == '1';
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> connect(String id) async {
    try {
      await _run(['--connect', id]);
      for (var i = 0; i < 10; i++) {
        if (await isConnected(id)) return true;
        await Future.delayed(const Duration(seconds: 1));
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> openSystemSettings() async {
    await Process.run('open', ['x-apple.systempreferences:com.apple.BluetoothSettings']);
  }
}

// ---------------------------------------------------------------- Servizio

class BluetoothService extends ChangeNotifier {
  final BtBackend? backend = BtBackend.create();
  bool busy = false;
  String status = '';
  bool? radioOn;
  bool deviceConnected = false;

  bool get supported => backend != null;

  /// Chiamato dopo un collegamento riuscito (per far ripartire l'uscita audio).
  Future<void> Function()? onConnected;

  Future<List<BtDevice>> pairedDevices() async {
    final b = backend;
    if (b == null) return [];
    if (!await b.ensurePermissions()) return [];
    final list = await b.paired();
    list.sort((a, c) {
      if (a.isAudio != c.isAudio) return a.isAudio ? -1 : 1;
      return a.name.toLowerCase().compareTo(c.name.toLowerCase());
    });
    return list;
  }

  void _set(String s, {bool? busy}) {
    status = s;
    if (busy != null) this.busy = busy;
    notifyListeners();
  }

  /// Accende il Bluetooth (se serve e se permesso) e collega il dispositivo.
  Future<BtResult> connectTo(String id, String name, {bool autoEnable = true}) async {
    final b = backend;
    if (b == null) return const BtResult(false, 'Bluetooth non disponibile su questo sistema');
    if (busy) return const BtResult(false, 'Collegamento già in corso');
    _set('Controllo il Bluetooth...', busy: true);
    try {
      if (!await b.ensurePermissions()) {
        _set('Permesso Bluetooth negato', busy: false);
        return const BtResult(false, 'Serve il permesso "Dispositivi nelle vicinanze" per usare il Bluetooth');
      }
      radioOn = await b.isOn();
      if (radioOn == false) {
        if (!autoEnable) {
          _set('Bluetooth spento', busy: false);
          return const BtResult(false, 'Il Bluetooth è spento');
        }
        _set('Accendo il Bluetooth...');
        final ok = await b.turnOn();
        radioOn = ok;
        if (!ok) {
          _set('Bluetooth spento', busy: false);
          return BtResult(false, Platform.isMacOS
              ? 'Su Mac il Bluetooth va acceso dalle Impostazioni di Sistema'
              : 'Non sono riuscito ad accendere il Bluetooth');
        }
        // Il sistema spesso ricollega da solo l'ultimo dispositivo.
        await Future.delayed(const Duration(seconds: 3));
      }

      for (var attempt = 1; attempt <= 3; attempt++) {
        if (await b.isConnected(id)) {
          deviceConnected = true;
          _set('Collegato a $name', busy: false);
          return BtResult(true, 'Collegato a $name');
        }
        _set('Collego $name... (tentativo $attempt di 3)');
        if (await b.connect(id)) {
          deviceConnected = true;
          _set('Collegato a $name', busy: false);
          // Il sistema ha appena cambiato l'uscita audio: si riallinea il player.
          await Future.delayed(const Duration(seconds: 2));
          await onConnected?.call();
          return BtResult(true, 'Collegato a $name');
        }
        await Future.delayed(const Duration(seconds: 4));
      }
      deviceConnected = false;
      _set('$name non trovato', busy: false);
      return BtResult(false, '$name non risponde: controlla che sia acceso e vicino');
    } catch (e) {
      _set('Errore Bluetooth', busy: false);
      return BtResult(false, 'Errore Bluetooth: $e');
    }
  }

  Future<void> refresh(String? id) async {
    final b = backend;
    if (b == null) return;
    try {
      radioOn = await b.isOn();
      deviceConnected = id != null && radioOn == true && await b.isConnected(id);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> openSettings() async => backend?.openSystemSettings();
}
