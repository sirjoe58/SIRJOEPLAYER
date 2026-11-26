import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Comportamento del Bluetooth all'avvio.
enum BtStartMode {
  /// Si collega da solo al dispositivo predefinito.
  auto,

  /// Chiede ogni volta se collegarsi.
  ask,

  /// Non fa nulla.
  off,
}

const kEqBands = <int>[31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];

const kEqPresets = <String, List<double>>{
  'Piatto': [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
  'Bassi potenti': [7, 6, 5, 3, 1, 0, 0, 0, 0, 0],
  'Rock': [5, 4, 2, 0, -1, -1, 1, 3, 4, 5],
  'Pop': [-1, 1, 3, 4, 3, 1, 0, 0, 1, 1],
  'Jazz': [3, 2, 1, 2, -1, -1, 0, 1, 2, 3],
  'Classica': [4, 3, 2, 1, 0, 0, 0, 1, 2, 3],
  'Dance': [6, 5, 2, 0, 0, -2, -1, 0, 3, 4],
  'Voce': [-2, -2, -1, 1, 3, 4, 4, 3, 1, 0],
  'Acuti': [0, 0, 0, 0, 0, 1, 3, 5, 6, 7],
  'Notte (basso volume)': [5, 4, 2, 0, 0, 0, 0, 2, 3, 4],
};

class Settings extends ChangeNotifier {
  late SharedPreferences _p;

  // Libreria
  List<String> folders = [];

  // Bluetooth
  BtStartMode btMode = BtStartMode.ask;
  bool btAutoEnable = true;
  String? btDeviceId;
  String? btDeviceName;

  // Audio
  double volume = 80;
  bool eqEnabled = false;
  String eqPreset = 'Piatto';
  List<double> eqGains = List.filled(10, 0);
  double rate = 1.0;
  bool replayGain = true;
  bool gapless = true;
  bool resumeLast = true;

  // Aspetto
  bool largeText = true;

  // Brani ricevuti via Bluetooth già importati (Android)
  Set<String> btImported = {};

  // Ultima riproduzione
  List<String> lastQueue = [];
  int lastIndex = 0;
  int lastPositionMs = 0;

  Future<void> load() async {
    _p = await SharedPreferences.getInstance();
    folders = _p.getStringList('folders') ?? [];
    btMode = BtStartMode.values[(_p.getInt('btMode') ?? 1).clamp(0, 2)];
    btAutoEnable = _p.getBool('btAutoEnable') ?? true;
    btDeviceId = _p.getString('btDeviceId');
    btDeviceName = _p.getString('btDeviceName');
    volume = _p.getDouble('volume') ?? 80;
    eqEnabled = _p.getBool('eqEnabled') ?? false;
    eqPreset = _p.getString('eqPreset') ?? 'Piatto';
    final g = _p.getString('eqGains');
    if (g != null) {
      final list = (jsonDecode(g) as List).map((e) => (e as num).toDouble()).toList();
      if (list.length == 10) eqGains = list;
    }
    rate = _p.getDouble('rate') ?? 1.0;
    replayGain = _p.getBool('replayGain') ?? true;
    gapless = _p.getBool('gapless') ?? true;
    resumeLast = _p.getBool('resumeLast') ?? true;
    largeText = _p.getBool('largeText') ?? true;
    btImported = (_p.getStringList('btImported') ?? []).toSet();
    lastQueue = _p.getStringList('lastQueue') ?? [];
    lastIndex = _p.getInt('lastIndex') ?? 0;
    lastPositionMs = _p.getInt('lastPositionMs') ?? 0;
  }

  Future<void> save() async {
    await _p.setStringList('folders', folders);
    await _p.setInt('btMode', btMode.index);
    await _p.setBool('btAutoEnable', btAutoEnable);
    if (btDeviceId == null) {
      await _p.remove('btDeviceId');
      await _p.remove('btDeviceName');
    } else {
      await _p.setString('btDeviceId', btDeviceId!);
      await _p.setString('btDeviceName', btDeviceName ?? btDeviceId!);
    }
    await _p.setDouble('volume', volume);
    await _p.setBool('eqEnabled', eqEnabled);
    await _p.setString('eqPreset', eqPreset);
    await _p.setString('eqGains', jsonEncode(eqGains));
    await _p.setDouble('rate', rate);
    await _p.setBool('replayGain', replayGain);
    await _p.setBool('gapless', gapless);
    await _p.setBool('resumeLast', resumeLast);
    await _p.setBool('largeText', largeText);
    notifyListeners();
  }

  Future<void> saveLastPlayback(List<String> queue, int index, int positionMs) async {
    lastQueue = queue;
    lastIndex = index;
    lastPositionMs = positionMs;
    await _p.setStringList('lastQueue', queue);
    await _p.setInt('lastIndex', index);
    await _p.setInt('lastPositionMs', positionMs);
  }

  Future<void> markBtImported(Iterable<String> paths) async {
    btImported.addAll(paths);
    await _p.setStringList('btImported', btImported.toList());
  }

  void update(void Function(Settings s) change) {
    change(this);
    save();
  }
}
