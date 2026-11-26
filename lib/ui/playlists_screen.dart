import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../app_state.dart';
import '../models.dart';
import '../playlists.dart';
import 'common.dart';

class PlaylistsScreen extends StatelessWidget {
  const PlaylistsScreen({super.key});

  Future<void> _new(BuildContext context) async {
    final name = await askText(context, 'Nome della nuova playlist', hint: 'Es. Musica in auto', ok: 'Crea');
    if (name == null || !context.mounted) return;
    final pl = app.playlists.create(name);
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlaylistDetail(playlist: pl, pickNow: true)));
  }

  Future<void> _import(BuildContext context) async {
    final res = await FilePicker.platform.pickFiles(
      dialogTitle: 'Importa playlist M3U',
      type: FileType.any,
    );
    final path = res?.paths.firstOrNull;
    if (path == null) return;
    try {
      final content = await File(path).readAsString();
      final paths = PlaylistStore.parseM3u(content, p.dirname(path));
      await app.library.addFiles(paths.where((x) => File(x).existsSync()).toList());
      app.playlists.create(p.basenameWithoutExtension(path), paths);
      if (context.mounted) toast(context, 'Playlist importata (${paths.length} brani)');
    } catch (e) {
      if (context.mounted) toast(context, 'Impossibile leggere il file: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = app.playlists;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _new(context),
        icon: const Icon(Icons.add),
        label: const Text('Nuova playlist'),
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              ListTile(
                leading: const Icon(Icons.file_open),
                title: const Text('Importa playlist (M3U)'),
                onTap: () => _import(context),
              ),
              const Divider(),
              if (store.items.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'Non hai ancora playlist.\nPremi "Nuova playlist" per crearne una.',
                    textAlign: TextAlign.center,
                  ),
                ),
              for (final pl in store.items)
                ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.queue_music)),
                  title: Text(pl.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${pl.paths.length} brani  •  ${_totalTime(pl)}'),
                  trailing: IconButton(
                    tooltip: 'Riproduci',
                    icon: const Icon(Icons.play_circle, size: 40),
                    onPressed: pl.paths.isEmpty ? null : () => app.player.playPaths(pl.paths),
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => PlaylistDetail(playlist: pl)),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

String _totalTime(SavedPlaylist pl) {
  var ms = 0;
  for (final x in pl.paths) {
    ms += app.library.trackFor(x).durationMs;
  }
  return formatDuration(Duration(milliseconds: ms));
}

class PlaylistDetail extends StatefulWidget {
  final SavedPlaylist playlist;
  final bool pickNow;
  const PlaylistDetail({super.key, required this.playlist, this.pickNow = false});

  @override
  State<PlaylistDetail> createState() => _PlaylistDetailState();
}

class _PlaylistDetailState extends State<PlaylistDetail> {
  SavedPlaylist get pl => widget.playlist;

  @override
  void initState() {
    super.initState();
    if (widget.pickNow) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _addTracks());
    }
  }

  Future<void> _addTracks() async {
    final chosen = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(builder: (_) => TrackPickerScreen(exclude: pl.paths.toSet())),
    );
    if (chosen != null && chosen.isNotEmpty) {
      app.playlists.addTracks(pl, chosen);
      if (mounted) toast(context, 'Aggiunti ${chosen.length} brani');
    }
  }

  Future<void> _export() async {
    final content = app.playlists.toM3u(pl, app.library.trackFor);
    try {
      final out = await FilePicker.platform.saveFile(
        dialogTitle: 'Salva playlist',
        fileName: '${pl.name}.m3u',
        bytes: utf8.encode(content),
      );
      if (out != null && !Platform.isAndroid) {
        await File(out).writeAsString(content);
      }
      if (out != null && mounted) toast(context, 'Playlist salvata');
    } catch (e) {
      if (mounted) toast(context, 'Errore nel salvataggio: $e');
    }
  }

  Future<void> _menu(String a) async {
    switch (a) {
      case 'rename':
        final name = await askText(context, 'Rinomina playlist', initial: pl.name);
        if (name != null && name.trim().isNotEmpty) app.playlists.rename(pl, name);
      case 'sortTitle':
        app.playlists.sortBy(pl, (x) => app.library.trackFor(x).title.toLowerCase());
      case 'sortArtist':
        app.playlists.sortBy(pl, (x) => app.library.trackFor(x).artist.toLowerCase());
      case 'sortGenre':
        app.playlists.sortBy(pl, (x) => app.library.trackFor(x).genre.toLowerCase());
      case 'export':
        await _export();
      case 'delete':
        if (await confirm(context, 'Eliminare la playlist?', 'La playlist "${pl.name}" verrà eliminata. I brani restano sul disco.', ok: 'Elimina')) {
          app.playlists.delete(pl);
          if (mounted) Navigator.of(context).pop();
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app.playlists,
      builder: (context, _) {
        final tracks = pl.paths.map(app.library.trackFor).toList();
        return Scaffold(
          appBar: AppBar(
            title: Text(pl.name),
            actions: [
              PopupMenuButton<String>(
                onSelected: _menu,
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rename', child: ListTile(leading: Icon(Icons.edit), title: Text('Rinomina'))),
                  PopupMenuItem(value: 'sortTitle', child: ListTile(leading: Icon(Icons.sort_by_alpha), title: Text('Ordina per titolo'))),
                  PopupMenuItem(value: 'sortArtist', child: ListTile(leading: Icon(Icons.person), title: Text('Ordina per artista'))),
                  PopupMenuItem(value: 'sortGenre', child: ListTile(leading: Icon(Icons.category), title: Text('Ordina per genere'))),
                  PopupMenuItem(value: 'export', child: ListTile(leading: Icon(Icons.save_alt), title: Text('Esporta (M3U)'))),
                  PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete), title: Text('Elimina playlist'))),
                ],
              ),
            ],
          ),
          body: Column(
            children: [
              PlayButtonsRow(
                tracks: tracks,
                extra: OutlinedButton.icon(
                  onPressed: _addTracks,
                  icon: const Icon(Icons.add),
                  label: const Text('Aggiungi brani'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  Text('${tracks.length} brani  •  ${_totalTime(pl)}'),
                  const Spacer(),
                  const Text('Tieni premuto e trascina per spostare', style: TextStyle(fontSize: 12)),
                ]),
              ),
              Expanded(
                child: tracks.isEmpty
                    ? const Center(child: Text('Playlist vuota: premi "Aggiungi brani"'))
                    : ReorderableListView.builder(
                        itemCount: tracks.length,
                        onReorder: (a, b) => app.playlists.reorder(pl, a, b),
                        itemBuilder: (context, i) => TrackTile(
                          key: ValueKey('${pl.paths[i]}#$i'),
                          track: tracks[i],
                          onTap: () => app.player.playPaths(pl.paths, start: i),
                          extraItems: const [
                            PopupMenuItem(
                              value: 'remove',
                              child: ListTile(leading: Icon(Icons.remove_circle_outline), title: Text('Togli dalla playlist')),
                            ),
                          ],
                          onExtra: (a) {
                            if (a == 'remove') app.playlists.removeAt(pl, i);
                          },
                        ),
                      ),
              ),
            ],
          ),
          bottomNavigationBar: MiniPlayer(onOpen: () => openNowPlaying(context)),
        );
      },
    );
  }
}

/// Schermata per scegliere più brani con le caselle di spunta.
class TrackPickerScreen extends StatefulWidget {
  final Set<String> exclude;
  const TrackPickerScreen({super.key, this.exclude = const {}});

  @override
  State<TrackPickerScreen> createState() => _TrackPickerScreenState();
}

class _TrackPickerScreenState extends State<TrackPickerScreen> {
  final selected = <String>[];
  String query = '';

  @override
  Widget build(BuildContext context) {
    final tracks = app.library.search(query).where((t) => !widget.exclude.contains(t.path)).toList();
    final allSelected = tracks.isNotEmpty && tracks.every((t) => selected.contains(t.path));
    return Scaffold(
      appBar: AppBar(
        title: Text(selected.isEmpty ? 'Scegli i brani' : '${selected.length} selezionati'),
        actions: [
          TextButton.icon(
            onPressed: () async {
              final added = await app.pickFiles();
              setState(() {
                for (final t in added) {
                  if (!selected.contains(t.path)) selected.add(t.path);
                }
              });
            },
            icon: const Icon(Icons.audio_file),
            label: const Text('Da file'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Cerca titolo, artista, album o genere',
              ),
              onChanged: (v) => setState(() => query = v),
            ),
          ),
          CheckboxListTile(
            value: allSelected,
            title: Text(query.isEmpty ? 'Seleziona tutti' : 'Seleziona tutti i risultati'),
            onChanged: (v) => setState(() {
              for (final t in tracks) {
                if (v == true) {
                  if (!selected.contains(t.path)) selected.add(t.path);
                } else {
                  selected.remove(t.path);
                }
              }
            }),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: tracks.length,
              itemBuilder: (context, i) {
                final t = tracks[i];
                return CheckboxListTile(
                  value: selected.contains(t.path),
                  title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${t.artist}  •  ${t.genre}', maxLines: 1, overflow: TextOverflow.ellipsis),
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      selected.add(t.path);
                    } else {
                      selected.remove(t.path);
                    }
                  }),
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
            onPressed: selected.isEmpty ? null : () => Navigator.pop(context, selected),
            icon: const Icon(Icons.check),
            label: Text('Aggiungi ${selected.length} brani'),
          ),
        ),
      ),
    );
  }
}
