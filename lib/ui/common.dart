import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import 'now_playing.dart';

void toast(BuildContext context, String msg, {SnackBarAction? action}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(msg),
      action: action,
      duration: const Duration(seconds: 5),
    ));
}

Future<String?> askText(BuildContext context, String title,
    {String initial = '', String ok = 'Salva', String hint = ''}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annulla')),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: Text(ok)),
      ],
    ),
  );
}

Future<bool> confirm(BuildContext context, String title, String text, {String ok = 'Sì'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(text),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ok)),
      ],
    ),
  );
  return r == true;
}

/// Finestra per aggiungere uno o più brani a una playlist (anche nuova).
Future<void> addToPlaylistDialog(BuildContext context, List<String> paths) async {
  final store = app.playlists;
  final choice = await showModalBottomSheet<Object>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              paths.length == 1 ? 'Aggiungi a playlist' : 'Aggiungi ${paths.length} brani a playlist',
              style: Theme.of(ctx).textTheme.titleLarge,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.add_circle, size: 32),
            title: const Text('Nuova playlist'),
            onTap: () => Navigator.pop(ctx, 'new'),
          ),
          const Divider(),
          for (final pl in store.items)
            ListTile(
              leading: const Icon(Icons.queue_music),
              title: Text(pl.name),
              subtitle: Text('${pl.paths.length} brani'),
              onTap: () => Navigator.pop(ctx, pl),
            ),
        ],
      ),
    ),
  );
  if (!context.mounted || choice == null) return;
  if (choice == 'new') {
    final name = await askText(context, 'Nome della nuova playlist', hint: 'Es. Musica in auto', ok: 'Crea');
    if (name == null || !context.mounted) return;
    final pl = store.create(name, paths);
    toast(context, 'Creata la playlist "${pl.name}"');
  } else if (choice is SavedPlaylist) {
    store.addTracks(choice, paths);
    toast(context, 'Aggiunto a "${choice.name}"');
  }
}

void showTrackInfo(BuildContext context, Track t) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(t.title),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _info('Artista', t.artist),
            _info('Album', t.album),
            _info('Genere', t.genre),
            if (t.year != null) _info('Anno', '${t.year}'),
            if (t.durationMs > 0) _info('Durata', formatDuration(Duration(milliseconds: t.durationMs))),
            _info('Formato', t.extension),
            _info('File', t.path),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Chiudi'))],
    ),
  );
}

Widget _info(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: SelectableText.rich(TextSpan(children: [
        TextSpan(text: '$k: ', style: const TextStyle(fontWeight: FontWeight.bold)),
        TextSpan(text: v),
      ])),
    );

/// Riga di un brano con menu delle azioni.
class TrackTile extends StatelessWidget {
  final Track track;
  final VoidCallback onTap;
  final List<PopupMenuEntry<String>> extraItems;
  final void Function(String action)? onExtra;
  final Widget? leading;

  const TrackTile({
    super.key,
    required this.track,
    required this.onTap,
    this.extraItems = const [],
    this.onExtra,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    final ps = app.player;
    return ListenableBuilder(
      listenable: ps,
      builder: (context, _) {
        final isCurrent = ps.current?.path == track.path;
        final color = Theme.of(context).colorScheme.primary;
        return ListTile(
          onTap: onTap,
          leading: leading ??
              CircleAvatar(
                backgroundColor: isCurrent ? color : Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Icon(
                  isCurrent && ps.playing ? Icons.graphic_eq : Icons.music_note,
                  color: isCurrent ? Theme.of(context).colorScheme.onPrimary : null,
                ),
              ),
          title: Text(
            track.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
              color: isCurrent ? color : null,
            ),
          ),
          subtitle: Text(
            '${track.artist}  •  ${track.genre}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (track.durationMs > 0)
                Text(formatDuration(Duration(milliseconds: track.durationMs))),
              PopupMenuButton<String>(
                tooltip: 'Altre azioni',
                onSelected: (a) {
                  switch (a) {
                    case 'next':
                      ps.playNext([track.path]);
                      toast(context, 'Suonerà dopo il brano attuale');
                    case 'queue':
                      ps.addToQueue([track.path]);
                      toast(context, 'Aggiunto alla coda');
                    case 'playlist':
                      addToPlaylistDialog(context, [track.path]);
                    case 'info':
                      showTrackInfo(context, track);
                    default:
                      onExtra?.call(a);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'next', child: ListTile(leading: Icon(Icons.playlist_play), title: Text('Riproduci dopo'))),
                  const PopupMenuItem(value: 'queue', child: ListTile(leading: Icon(Icons.queue), title: Text('Aggiungi alla coda'))),
                  const PopupMenuItem(value: 'playlist', child: ListTile(leading: Icon(Icons.playlist_add), title: Text('Aggiungi a playlist'))),
                  const PopupMenuItem(value: 'info', child: ListTile(leading: Icon(Icons.info_outline), title: Text('Informazioni'))),
                  ...extraItems,
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Barra in basso con il brano in ascolto.
class MiniPlayer extends StatelessWidget {
  final VoidCallback onOpen;
  const MiniPlayer({super.key, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final ps = app.player;
    return ListenableBuilder(
      listenable: ps,
      builder: (context, _) {
        final t = ps.current;
        if (t == null) return const SizedBox.shrink();
        final progress = ps.duration.inMilliseconds > 0
            ? ps.position.inMilliseconds / ps.duration.inMilliseconds
            : 0.0;
        return Material(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          child: InkWell(
            onTap: onOpen,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(value: progress.clamp(0.0, 1.0), minHeight: 3),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.album, size: 40),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.bold)),
                            Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                      IconButton(
                        iconSize: 34,
                        tooltip: 'Precedente',
                        icon: const Icon(Icons.skip_previous),
                        onPressed: ps.previous,
                      ),
                      IconButton.filled(
                        iconSize: 40,
                        tooltip: ps.playing ? 'Pausa' : 'Play',
                        icon: Icon(ps.playing ? Icons.pause : Icons.play_arrow),
                        onPressed: ps.playPause,
                      ),
                      IconButton(
                        iconSize: 34,
                        tooltip: 'Successivo',
                        icon: const Icon(Icons.skip_next),
                        onPressed: ps.next,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Pulsanti grandi "Riproduci" e "Casuale" per un elenco di brani.
class PlayButtonsRow extends StatelessWidget {
  final List<Track> tracks;
  final Widget? extra;
  const PlayButtonsRow({super.key, required this.tracks, this.extra});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            onPressed: tracks.isEmpty ? null : () => app.player.playTracks(tracks),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Riproduci'),
          ),
          FilledButton.tonalIcon(
            onPressed: tracks.isEmpty ? null : () => app.player.playTracks(tracks, shuffled: true),
            icon: const Icon(Icons.shuffle),
            label: const Text('Casuale'),
          ),
          OutlinedButton.icon(
            onPressed: tracks.isEmpty
                ? null
                : () => addToPlaylistDialog(context, tracks.map((t) => t.path).toList()),
            icon: const Icon(Icons.playlist_add),
            label: const Text('In playlist'),
          ),
          if (extra != null) extra!,
        ],
      ),
    );
  }
}

void openNowPlaying(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NowPlayingScreen(standalone: true)));
}
