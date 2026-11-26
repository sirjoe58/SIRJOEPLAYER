import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../library.dart';
import '../models.dart';
import '../player_service.dart';
import 'common.dart';
import 'eq_screen.dart';

class NowPlayingScreen extends StatefulWidget {
  final bool standalone;
  const NowPlayingScreen({super.key, this.standalone = false});

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen> {
  String? _coverPath;
  Uint8List? _cover;
  double? _dragValue;

  void _loadCover(Track t) {
    if (_coverPath == t.path) return;
    _coverPath = t.path;
    _cover = null;
    Library.cover(t.path).then((bytes) {
      if (mounted && _coverPath == t.path) setState(() => _cover = bytes);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ps = app.player;
    final body = ListenableBuilder(
      listenable: ps,
      builder: (context, _) {
        final t = ps.current;
        if (t == null) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text('Nessun brano in ascolto.\nScegli un brano dalla Libreria o da una Playlist.',
                  textAlign: TextAlign.center),
            ),
          );
        }
        _loadCover(t);
        final scheme = Theme.of(context).colorScheme;
        final durMs = ps.duration.inMilliseconds.toDouble();
        final posMs = (_dragValue ?? ps.position.inMilliseconds.toDouble()).clamp(0.0, durMs > 0 ? durMs : 1.0);
        return LayoutBuilder(builder: (context, box) {
          final coverSize = (box.maxWidth * 0.7).clamp(140.0, 340.0).toDouble();
          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        width: coverSize,
                        height: coverSize,
                        color: scheme.surfaceContainerHighest,
                        child: _cover != null
                            ? Image.memory(_cover!, fit: BoxFit.cover, gaplessPlayback: true)
                            : Icon(Icons.album, size: coverSize * 0.6, color: scheme.primary),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(t.title,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(t.artist, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
                    Text('${t.album}  •  ${t.genre}  •  ${t.extension}',
                        textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 12),
                    Slider(
                      value: posMs,
                      max: durMs > 0 ? durMs : 1.0,
                      onChanged: durMs > 0 ? (v) => setState(() => _dragValue = v) : null,
                      onChangeEnd: (v) {
                        ps.seek(Duration(milliseconds: v.round()));
                        setState(() => _dragValue = null);
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(children: [
                        Text(formatDuration(Duration(milliseconds: posMs.round()))),
                        const Spacer(),
                        Text(formatDuration(ps.duration)),
                      ]),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton(
                          iconSize: 30,
                          tooltip: 'Ordine casuale',
                          isSelected: ps.shuffle,
                          color: ps.shuffle ? scheme.primary : null,
                          icon: const Icon(Icons.shuffle),
                          onPressed: ps.toggleShuffle,
                        ),
                        IconButton(iconSize: 46, tooltip: 'Precedente', icon: const Icon(Icons.skip_previous), onPressed: ps.previous),
                        IconButton.filled(
                          iconSize: 64,
                          tooltip: ps.playing ? 'Pausa' : 'Play',
                          icon: Icon(ps.playing ? Icons.pause : Icons.play_arrow),
                          onPressed: ps.playPause,
                        ),
                        IconButton(iconSize: 46, tooltip: 'Successivo', icon: const Icon(Icons.skip_next), onPressed: ps.next),
                        IconButton(
                          iconSize: 30,
                          tooltip: switch (ps.repeat) {
                            RepeatMode.off => 'Ripeti: no',
                            RepeatMode.all => 'Ripeti: tutti',
                            RepeatMode.one => 'Ripeti: questo brano',
                          },
                          color: ps.repeat != RepeatMode.off ? scheme.primary : null,
                          icon: Icon(ps.repeat == RepeatMode.one ? Icons.repeat_one : Icons.repeat),
                          onPressed: ps.cycleRepeat,
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton.icon(onPressed: () => ps.skipBy(-10), icon: const Icon(Icons.replay_10), label: const Text('-10 s')),
                        const SizedBox(width: 24),
                        TextButton.icon(onPressed: () => ps.skipBy(10), icon: const Icon(Icons.forward_10), label: const Text('+10 s')),
                      ],
                    ),
                    Row(children: [
                      IconButton(
                        tooltip: 'Muto',
                        icon: Icon(ps.settings.volume == 0 ? Icons.volume_off : Icons.volume_down),
                        onPressed: () => ps.setVolume(ps.settings.volume == 0 ? 60 : 0),
                      ),
                      Expanded(
                        child: Slider(
                          value: ps.settings.volume,
                          max: 100,
                          label: '${ps.settings.volume.round()}',
                          onChanged: ps.setVolume,
                        ),
                      ),
                      const Icon(Icons.volume_up),
                    ]),
                    const SizedBox(height: 8),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _ActionChip(icon: Icons.queue_music, label: 'Coda (${ps.queue.length})', onTap: () => _showQueue(context)),
                        _ActionChip(
                          icon: Icons.equalizer,
                          label: ps.settings.eqEnabled ? 'Equalizzatore: ${ps.settings.eqPreset}' : 'Equalizzatore',
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EqScreen())),
                        ),
                        _ActionChip(icon: Icons.speed, label: 'Velocità ${ps.settings.rate}x', onTap: () => _speed(context)),
                        _ActionChip(
                          icon: Icons.bedtime,
                          label: ps.sleepAt == null
                              ? 'Timer spegnimento'
                              : 'Si spegne alle ${TimeOfDay.fromDateTime(ps.sleepAt!).format(context)}',
                          onTap: () => _sleep(context),
                        ),
                        _ActionChip(
                          icon: Icons.playlist_add,
                          label: 'Aggiungi a playlist',
                          onTap: () => addToPlaylistDialog(context, [t.path]),
                        ),
                        _ActionChip(
                          icon: Icons.save,
                          label: 'Salva coda come playlist',
                          onTap: () async {
                            final name = await askText(context, 'Nome della playlist', ok: 'Salva');
                            if (name == null) return;
                            app.playlists.create(name, ps.queue);
                            if (context.mounted) toast(context, 'Playlist salvata');
                          },
                        ),
                        _ActionChip(icon: Icons.info_outline, label: 'Informazioni', onTap: () => showTrackInfo(context, t)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        });
      },
    );
    if (!widget.standalone) return body;
    return Scaffold(appBar: AppBar(title: const Text('In ascolto')), body: body);
  }

  void _speed(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final r in [0.5, 0.75, 0.9, 1.0, 1.1, 1.25, 1.5, 2.0])
              ChoiceChip(
                label: Text('${r}x'),
                selected: app.settings.rate == r,
                onSelected: (_) {
                  app.player.setRate(r);
                  Navigator.pop(ctx);
                },
              ),
            const SizedBox(width: double.infinity, height: 16),
          ],
        ),
      ),
    );
  }

  void _sleep(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final m in [10, 15, 30, 45, 60, 90, 120])
              ListTile(
                leading: const Icon(Icons.timer),
                title: Text('Tra $m minuti'),
                onTap: () {
                  app.player.setSleepTimer(Duration(minutes: m));
                  Navigator.pop(ctx);
                },
              ),
            ListTile(
              leading: const Icon(Icons.timer_off),
              title: const Text('Disattiva timer'),
              onTap: () {
                app.player.setSleepTimer(null);
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showQueue(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const QueueScreen()));
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionChip({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => ActionChip(
        avatar: Icon(icon),
        label: Text(label),
        onPressed: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      );
}

class QueueScreen extends StatelessWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ps = app.player;
    return Scaffold(
      appBar: AppBar(title: const Text('Coda di riproduzione')),
      body: ListenableBuilder(
        listenable: ps,
        builder: (context, _) {
          if (ps.queue.isEmpty) return const Center(child: Text('La coda è vuota'));
          return ReorderableListView.builder(
            itemCount: ps.queue.length,
            onReorder: (a, b) => ps.moveInQueue(a, b),
            itemBuilder: (context, i) {
              final t = app.library.trackFor(ps.queue[i]);
              final current = i == ps.index;
              return ListTile(
                key: ValueKey('${ps.queue[i]}#$i'),
                leading: CircleAvatar(
                  child: current ? const Icon(Icons.graphic_eq) : Text('${i + 1}'),
                ),
                title: Text(t.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: current ? FontWeight.bold : null)),
                subtitle: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => ps.jump(i),
                trailing: Padding(
                  padding: const EdgeInsets.only(right: 32),
                  child: IconButton(
                    tooltip: 'Togli dalla coda',
                    icon: const Icon(Icons.close),
                    onPressed: () => ps.removeFromQueue(i),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
