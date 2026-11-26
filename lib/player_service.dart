import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' hide Track;

import 'library.dart';
import 'models.dart';
import 'settings.dart';

enum PlayRepeat { off, all, one }

class PlayerService extends ChangeNotifier {
  final Settings settings;
  final Library library;
  final Player player = Player(
    configuration: const PlayerConfiguration(title: 'SirJoe Player'),
  );

  PlayerService(this.settings, this.library);

  final List<StreamSubscription> _subs = [];
  bool playing = false;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  List<String> queue = [];
  int index = -1;
  bool shuffle = false;
  PlayRepeat repeat = PlayRepeat.off;
  DateTime? sleepAt;
  Timer? _sleepTimer;
  Timer? _saveTimer;
  List<AudioDevice> audioDevices = [];
  AudioDevice? audioDevice;

  Track? get current =>
      (index >= 0 && index < queue.length) ? library.trackFor(queue[index]) : null;

  NativePlayer? get _native {
    final pl = player.platform;
    return pl is NativePlayer ? pl : null;
  }

  Future<void> init() async {
    await player.setVolume(settings.volume);
    await player.setRate(settings.rate);
    await applyAudioOptions();
    await applyEq();

    _subs.add(player.stream.playing.listen((v) {
      playing = v;
      notifyListeners();
    }));
    _subs.add(player.stream.position.listen((v) {
      position = v;
      notifyListeners();
    }));
    _subs.add(player.stream.duration.listen((v) {
      duration = v;
      notifyListeners();
    }));
    _subs.add(player.stream.playlist.listen((pl) {
      queue = pl.medias
          .map((m) => (m.extras?['path'] as String?) ?? m.uri)
          .toList();
      index = pl.index;
      notifyListeners();
    }));
    _subs.add(player.stream.shuffle.listen((v) {
      shuffle = v;
      notifyListeners();
    }));
    _subs.add(player.stream.audioDevices.listen((v) {
      audioDevices = v;
      notifyListeners();
    }));
    _subs.add(player.stream.audioDevice.listen((v) {
      audioDevice = v;
      notifyListeners();
    }));

    _startWatchdog();

    // Salva periodicamente il punto di ascolto.
    _saveTimer = Timer.periodic(const Duration(seconds: 10), (_) => saveState());

    if (settings.resumeLast && settings.lastQueue.isNotEmpty) {
      await _open(settings.lastQueue, settings.lastIndex, play: false);
      if (settings.lastPositionMs > 0) {
        // Attende che il brano sia caricato prima di spostarsi.
        Future.delayed(const Duration(milliseconds: 700), () {
          player.seek(Duration(milliseconds: settings.lastPositionMs));
        });
      }
    }
  }

  Future<void> saveState() async {
    if (queue.isEmpty) return;
    await settings.saveLastPlayback(queue, index < 0 ? 0 : index, position.inMilliseconds);
  }

  Media _media(String path) => Media(path, extras: {'path': path});

  Future<void> _open(List<String> paths, int start, {bool play = true}) async {
    if (paths.isEmpty) return;
    await player.open(
      Playlist(paths.map(_media).toList(), index: start.clamp(0, paths.length - 1)),
      play: play,
    );
  }

  Future<void> playPaths(List<String> paths, {int start = 0, bool shuffled = false}) async {
    if (shuffle) await player.setShuffle(false);
    await _open(paths, shuffled ? 0 : start);
    if (shuffled) {
      // L'ordine casuale viene applicato dopo l'apertura.
      await player.setShuffle(true);
    }
    saveState();
  }

  Future<void> playTracks(List<Track> tracks, {int start = 0, bool shuffled = false}) =>
      playPaths(tracks.map((t) => t.path).toList(), start: start, shuffled: shuffled);

  Future<void> addToQueue(List<String> paths) async {
    if (queue.isEmpty) {
      await _open(paths, 0);
      return;
    }
    for (final x in paths) {
      await player.add(_media(x));
    }
  }

  Future<void> playNext(List<String> paths) async {
    if (queue.isEmpty) {
      await _open(paths, 0);
      return;
    }
    var target = index + 1;
    var last = queue.length; // posizione del primo brano aggiunto
    for (final x in paths) {
      await player.add(_media(x));
      await player.move(last, target);
      target++;
      last++;
    }
  }

  Future<void> removeFromQueue(int i) => player.remove(i);
  Future<void> moveInQueue(int from, int to) => player.move(from, to);
  Future<void> jump(int i) async {
    await player.jump(i);
    await player.play();
  }

  Future<void> playPause() async {
    if (queue.isEmpty) return;
    await player.playOrPause();
  }

  Future<void> play() => player.play();
  Future<void> pause() => player.pause();
  Future<void> stop() => player.stop();

  Future<void> next() => player.next();

  Future<void> previous() async {
    // Come nei player professionali: oltre 3 secondi torna all'inizio del brano.
    if (position > const Duration(seconds: 3)) {
      await player.seek(Duration.zero);
    } else {
      await player.previous();
    }
  }

  Future<void> seek(Duration d) => player.seek(d);

  Future<void> skipBy(int seconds) async {
    var t = position + Duration(seconds: seconds);
    if (t < Duration.zero) t = Duration.zero;
    if (duration > Duration.zero && t > duration) t = duration;
    await player.seek(t);
  }

  Future<void> setVolume(double v) async {
    settings.volume = v.clamp(0, 100);
    await player.setVolume(settings.volume);
    notifyListeners();
    settings.save();
  }

  Future<void> setRate(double r) async {
    settings.rate = r;
    await player.setRate(r);
    notifyListeners();
    settings.save();
  }

  Future<void> toggleShuffle() => player.setShuffle(!shuffle);

  Future<void> cycleRepeat() async {
    repeat = PlayRepeat.values[(repeat.index + 1) % PlayRepeat.values.length];
    await player.setPlaylistMode(switch (repeat) {
      PlayRepeat.off => PlaylistMode.none,
      PlayRepeat.all => PlaylistMode.loop,
      PlayRepeat.one => PlaylistMode.single,
    });
    notifyListeners();
  }

  Future<void> setAudioDevice(AudioDevice d) => player.setAudioDevice(d);

  // ---- Opzioni audio avanzate (mpv) ----

  Future<void> applyAudioOptions() async {
    final n = _native;
    if (n == null) return;
    try {
      await n.setProperty('replaygain', settings.replayGain ? 'track' : 'no');
      await n.setProperty('replaygain-clip', 'no');
      await n.setProperty('gapless-audio', settings.gapless ? 'yes' : 'weak');
      await n.setProperty('audio-pitch-correction', 'yes');
    } catch (_) {}
  }

  Future<void> applyEq() async {
    final n = _native;
    if (n == null) return;
    try {
      final gains = settings.eqGains;
      if (!settings.eqEnabled || gains.every((g) => g == 0)) {
        await n.setProperty('af', '');
        await _setGain(0);
        return;
      }
      // Solo il filtro "equalizer": il motore audio incluso non ha altri filtri.
      final parts = <String>[];
      for (var i = 0; i < kEqBands.length; i++) {
        if (gains[i] == 0) continue;
        parts.add('equalizer=f=${kEqBands[i]}:t=o:w=1:g=${gains[i].toStringAsFixed(1)}');
      }
      await n.setProperty('af', 'lavfi=[${parts.join(',')}]');
      // Abbassa un po' il volume quando si alzano le frequenze, per non distorcere.
      final maxGain = gains.reduce((a, b) => a > b ? a : b);
      await _setGain(maxGain > 0 ? -maxGain : 0);
    } catch (_) {}
  }

  Future<void> _setGain(double db) async {
    try {
      await _native?.setProperty('volume-gain', db.toStringAsFixed(1));
    } catch (_) {}
  }

  /// Fa ripartire l'uscita audio (es. dopo il collegamento di cuffie o casse Bluetooth).
  Future<void> reloadAudioOutput() async {
    try {
      await _native?.command(['ao-reload']);
    } catch (_) {}
  }

  // ---- Controllo automatico: se il brano risulta in riproduzione ma resta fermo ----

  final notice = ValueNotifier<String?>(null);
  Timer? _watchdog;
  Duration _lastPos = Duration.zero;
  int _stuckTicks = 0;
  int _repairStep = 0;

  void _startWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer.periodic(const Duration(seconds: 2), (_) => _checkStuck());
  }

  Future<void> _checkStuck() async {
    if (!playing || queue.isEmpty) {
      _stuckTicks = 0;
      _repairStep = 0;
      return;
    }
    if (position != _lastPos) {
      _lastPos = position;
      _stuckTicks = 0;
      _repairStep = 0;
      return;
    }
    _stuckTicks++;
    if (_stuckTicks < 2) return; // fermo da circa 4 secondi
    _stuckTicks = 0;
    final at = position;
    switch (_repairStep++) {
      case 0:
        // 1) Riavvia l'uscita audio (dispositivo Bluetooth cambiato o scollegato).
        await reloadAudioOutput();
        await player.seek(at);
      case 1:
        // 2) Se l'equalizzatore blocca l'audio, lo disattiva.
        if (settings.eqEnabled) {
          settings.eqEnabled = false;
          await settings.save();
          await applyEq();
          notice.value = null;
          notice.value = 'L\'equalizzatore bloccava l\'audio ed è stato disattivato';
        }
        await player.seek(at);
      case 2:
        // 3) Riapre il brano.
        final i = index;
        await player.jump(i < 0 ? 0 : i);
        await player.play();
      default:
        notice.value = null;
        notice.value = 'Questo brano non si riesce a riprodurre: passo al successivo';
        _repairStep = 0;
        await player.next();
    }
  }

  // ---- Timer di spegnimento ----

  void setSleepTimer(Duration? d) {
    _sleepTimer?.cancel();
    if (d == null) {
      sleepAt = null;
    } else {
      sleepAt = DateTime.now().add(d);
      _sleepTimer = Timer(d, () async {
        // Abbassa gradualmente il volume prima di fermarsi.
        final start = settings.volume;
        for (var i = 10; i >= 0; i--) {
          await player.setVolume(start * i / 10);
          await Future.delayed(const Duration(milliseconds: 400));
        }
        await player.pause();
        await player.setVolume(start);
        sleepAt = null;
        notifyListeners();
      });
    }
    notifyListeners();
  }

  @override
  void dispose() {
    saveState();
    for (final s in _subs) {
      s.cancel();
    }
    _sleepTimer?.cancel();
    _saveTimer?.cancel();
    _watchdog?.cancel();
    player.dispose();
    super.dispose();
  }
}
