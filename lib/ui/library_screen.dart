import 'package:flutter/material.dart';

import '../app_state.dart';
import '../library.dart';
import '../models.dart';
import 'common.dart';
import 'import_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  Catalog catalog = Catalog.titolo;
  String query = '';
  final _search = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final lib = app.library;
    return ListenableBuilder(
      listenable: lib,
      builder: (context, _) {
        if (lib.tracks.isEmpty && !lib.scanning) return _empty(context);
        return Column(
          children: [
            if (lib.scanning)
              Container(
                width: double.infinity,
                color: Theme.of(context).colorScheme.secondaryContainer,
                padding: const EdgeInsets.all(10),
                child: Row(children: [
                  const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 12),
                  Expanded(child: Text('${lib.scanStatus}  (${lib.scanFound} trovati)')),
                ]),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                controller: _search,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Cerca titolo, artista, album o genere',
                  border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(30))),
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () => setState(() {
                            _search.clear();
                            query = '';
                          }),
                        ),
                ),
                onChanged: (v) => setState(() => query = v),
              ),
            ),
            SizedBox(
              height: 56,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                children: [
                  for (final c in Catalog.values)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(
                        label: Text(c.label),
                        selected: catalog == c,
                        onSelected: (_) => setState(() => catalog = c),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: query.isNotEmpty || catalog == Catalog.titolo
                  ? _trackList(lib.search(query))
                  : _groupList(lib.groups(catalog)),
            ),
          ],
        );
      },
    );
  }

  Widget _trackList(List<Track> tracks) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: PlayButtonsRow(tracks: tracks)),
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text('${tracks.length} brani'),
            ),
          ],
        ),
        Expanded(
          child: ListView.builder(
            itemCount: tracks.length,
            itemBuilder: (context, i) => TrackTile(
              track: tracks[i],
              onTap: () => app.player.playTracks(tracks, start: i),
            ),
          ),
        ),
      ],
    );
  }

  Widget _groupList(Map<String, List<Track>> groups) {
    final keys = groups.keys.toList();
    final icon = switch (catalog) {
      Catalog.artista => Icons.person,
      Catalog.genere => Icons.category,
      Catalog.album => Icons.album,
      Catalog.cartella => Icons.folder,
      Catalog.titolo => Icons.music_note,
    };
    return ListView.builder(
      itemCount: keys.length,
      itemBuilder: (context, i) {
        final k = keys[i];
        final list = groups[k]!;
        final subtitle = switch (catalog) {
          Catalog.artista => '${list.length} brani  •  ${list.map((t) => t.genre).toSet().take(2).join(', ')}',
          Catalog.genere => '${list.length} brani  •  ${list.map((t) => t.artist).toSet().length} artisti',
          Catalog.album => '${list.first.artist}  •  ${list.length} brani',
          _ => '${list.length} brani',
        };
        return ListTile(
          leading: CircleAvatar(child: Icon(icon)),
          title: Text(k, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: IconButton(
            tooltip: 'Riproduci',
            icon: const Icon(Icons.play_circle, size: 36),
            onPressed: () => app.player.playTracks(list),
          ),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => GroupScreen(title: k, catalog: catalog),
          )),
        );
      },
    );
  }

  Widget _empty(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.library_music, size: 96, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text('La libreria è vuota', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text(
              'Scegli la cartella dove tieni la musica:\nl\'app troverà da sola tutti i brani.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18)),
              onPressed: () => app.addFolder(),
              icon: const Icon(Icons.create_new_folder),
              label: const Text('Aggiungi cartella di musica'),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18)),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ImportScreen())),
              icon: const Icon(Icons.download),
              label: const Text('Importa brani (chiavetta, PC, Bluetooth)'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final tracks = await app.pickFiles();
                if (tracks.isNotEmpty) app.player.playTracks(tracks);
              },
              icon: const Icon(Icons.audio_file),
              label: const Text('Apri singoli brani'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Brani di un artista / genere / album / cartella.
class GroupScreen extends StatelessWidget {
  final String title;
  final Catalog catalog;
  const GroupScreen({super.key, required this.title, required this.catalog});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListenableBuilder(
        listenable: app.library,
        builder: (context, _) {
          final tracks = app.library.groups(catalog)[title] ?? [];
          return Column(
            children: [
              PlayButtonsRow(tracks: tracks),
              Expanded(
                child: ListView.builder(
                  itemCount: tracks.length,
                  itemBuilder: (context, i) => TrackTile(
                    track: tracks[i],
                    onTap: () => app.player.playTracks(tracks, start: i),
                  ),
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: MiniPlayer(onOpen: () => openNowPlaying(context)),
    );
  }
}
