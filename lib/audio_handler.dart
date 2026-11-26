import 'package:audio_service/audio_service.dart';

import 'player_service.dart';

/// Collega il player alla notifica di Android, alla schermata di blocco
/// e ai tasti delle cuffie/casse Bluetooth (play, pausa, avanti, indietro).
class SirJoeAudioHandler extends BaseAudioHandler with SeekHandler {
  final PlayerService ps;

  SirJoeAudioHandler(this.ps) {
    ps.addListener(_update);
    _update();
  }

  String? _lastPath;
  String _lastKey = '';
  int _lastDur = -1;

  void _update() {
    final t = ps.current;
    // Aggiorna al massimo una volta al secondo.
    final key = '${t?.path}|${ps.playing}|${ps.position.inSeconds}|${ps.duration.inSeconds}';
    if (key == _lastKey) return;
    _lastKey = key;
    if (t != null && (t.path != _lastPath || ps.duration.inSeconds != _lastDur)) {
      _lastPath = t.path;
      _lastDur = ps.duration.inSeconds;
      mediaItem.add(MediaItem(
        id: t.path,
        title: t.title,
        artist: t.artist,
        album: t.album,
        genre: t.genre,
        duration: ps.duration > Duration.zero ? ps.duration : null,
      ));
    }
    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        ps.playing ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {MediaAction.seek},
      androidCompactActionIndices: const [0, 1, 2],
      processingState: t == null ? AudioProcessingState.idle : AudioProcessingState.ready,
      playing: ps.playing,
      updatePosition: ps.position,
      speed: ps.settings.rate,
    ));
  }

  @override
  Future<void> play() => ps.play();
  @override
  Future<void> pause() => ps.pause();
  @override
  Future<void> stop() => ps.pause();
  @override
  Future<void> skipToNext() => ps.next();
  @override
  Future<void> skipToPrevious() => ps.previous();
  @override
  Future<void> seek(Duration position) => ps.seek(position);
}
