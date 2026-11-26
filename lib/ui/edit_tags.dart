import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import 'common.dart';

const kCommonGenres = [
  'Pop', 'Rock', 'Classic Rock', 'Hard Rock', 'Metal', 'Blues', 'Jazz', 'Soul',
  'R&B', 'Funk', 'Disco', 'Dance', 'Elettronica', 'House', 'Techno', 'Ambient',
  'Hip-Hop', 'Rap', 'Reggae', 'Country', 'Folk', 'Liscio', 'Musica italiana',
  'Cantautori', 'Classica', 'Opera', 'Colonne sonore', 'Strumentale', 'Latino',
  'Anni 60', 'Anni 70', 'Anni 80', 'Anni 90', 'Natale', 'Bambini',
];

List<String> _existing(String Function(Track) f, String unknown) {
  final set = app.library.tracks.map(f).where((x) => x.isNotEmpty && x != unknown).toSet().toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return set;
}

/// Campo di testo con suggerimenti (valori già usati + generi comuni).
class _SuggestField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final List<String> suggestions;
  const _SuggestField({required this.controller, required this.label, required this.suggestions, this.hint});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: controller,
            decoration: InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder()),
          ),
        ),
        if (suggestions.isNotEmpty)
          PopupMenuButton<String>(
            tooltip: 'Scegli dall\'elenco',
            icon: const Icon(Icons.arrow_drop_down_circle_outlined),
            onSelected: (v) => controller.text = v,
            itemBuilder: (_) => [for (final s in suggestions.take(200)) PopupMenuItem(value: s, child: Text(s))],
          ),
      ]),
    );
  }
}

/// Modifica le informazioni di un brano.
Future<void> editTrackDialog(BuildContext context, Track t) async {
  final title = TextEditingController(text: t.title);
  final artist = TextEditingController(text: t.artist == kUnknownArtist ? '' : t.artist);
  final album = TextEditingController(text: t.album == kUnknownAlbum ? '' : t.album);
  final genre = TextEditingController(text: t.genre == kUnknownGenre ? '' : t.genre);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Modifica informazioni'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _SuggestField(controller: title, label: 'Titolo', suggestions: const []),
            _SuggestField(controller: artist, label: 'Artista', suggestions: _existing((x) => x.artist, kUnknownArtist)),
            _SuggestField(controller: album, label: 'Album', suggestions: _existing((x) => x.album, kUnknownAlbum)),
            _SuggestField(
              controller: genre,
              label: 'Genere',
              suggestions: {..._existing((x) => x.genre, kUnknownGenre), ...kCommonGenres}.toList(),
            ),
            if (t.title.contains(' - '))
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text('Dividi il titolo "Artista - Titolo"'),
                  onPressed: () {
                    final i = title.text.indexOf(' - ');
                    if (i < 0) return;
                    artist.text = title.text.substring(0, i).trim();
                    title.text = title.text.substring(i + 3).trim();
                  },
                ),
              ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salva')),
      ],
    ),
  );
  if (ok != true) return;
  String v(TextEditingController c, String unknown) => c.text.trim().isEmpty ? unknown : c.text.trim();
  await app.library.updateTracks([
    t.copyWith(
      title: title.text.trim().isEmpty ? t.title : title.text.trim(),
      artist: v(artist, kUnknownArtist),
      album: v(album, kUnknownAlbum),
      genre: v(genre, kUnknownGenre),
    ),
  ]);
  if (context.mounted) toast(context, 'Informazioni salvate');
}

enum _Split { none, artistFirst, titleFirst }

/// Cataloga più brani insieme: scegli i brani e assegna artista, album o genere.
class CatalogScreen extends StatefulWidget {
  final List<Track>? only;
  final String title;
  const CatalogScreen({super.key, this.only, this.title = 'Cataloga i brani'});

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  final selected = <String>{};
  String query = '';
  bool onlyUnknown = false;

  List<Track> get _source {
    if (widget.only == null) return app.library.tracks;
    final paths = widget.only!.map((t) => t.path).toSet();
    return app.library.tracks.where((t) => paths.contains(t.path)).toList();
  }

  Future<void> _apply() async {
    final artist = TextEditingController();
    final album = TextEditingController();
    final genre = TextEditingController();
    var split = _Split.none;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('Modifica ${selected.length} brani'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Scrivi solo ciò che vuoi cambiare: i campi vuoti restano come sono.'),
                const SizedBox(height: 8),
                _SuggestField(
                  controller: genre,
                  label: 'Genere',
                  hint: 'Es. Rock',
                  suggestions: {..._existing((x) => x.genre, kUnknownGenre), ...kCommonGenres}.toList(),
                ),
                _SuggestField(controller: artist, label: 'Artista', suggestions: _existing((x) => x.artist, kUnknownArtist)),
                _SuggestField(controller: album, label: 'Album', suggestions: _existing((x) => x.album, kUnknownAlbum)),
                const SizedBox(height: 8),
                const Text('Artista preso dal titolo (per i brani scaricati da YouTube):',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                RadioListTile<_Split>(
                  value: _Split.none,
                  groupValue: split,
                  title: const Text('No'),
                  onChanged: (v) => setD(() => split = v!),
                ),
                RadioListTile<_Split>(
                  value: _Split.artistFirst,
                  groupValue: split,
                  title: const Text('"Artista - Titolo"'),
                  subtitle: const Text('Es. "a-ha - Take On Me"'),
                  onChanged: (v) => setD(() => split = v!),
                ),
                RadioListTile<_Split>(
                  value: _Split.titleFirst,
                  groupValue: split,
                  title: const Text('"Titolo - Artista"'),
                  subtitle: const Text('Es. "A Whiter Shade Of Pale - Procol Harum"'),
                  onChanged: (v) => setD(() => split = v!),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Applica')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final updated = <Track>[];
    for (final t in app.library.tracks.where((t) => selected.contains(t.path))) {
      var x = t;
      if (split != _Split.none) {
        final i = x.title.indexOf(' - ');
        if (i > 0) {
          final left = x.title.substring(0, i).trim();
          final right = x.title.substring(i + 3).trim();
          x = split == _Split.artistFirst
              ? x.copyWith(artist: left, title: right)
              : x.copyWith(artist: right, title: left);
        }
      }
      x = x.copyWith(
        artist: artist.text.trim().isEmpty ? null : artist.text.trim(),
        album: album.text.trim().isEmpty ? null : album.text.trim(),
        genre: genre.text.trim().isEmpty ? null : genre.text.trim(),
      );
      updated.add(x);
    }
    await app.library.updateTracks(updated);
    if (!mounted) return;
    setState(selected.clear);
    toast(context, 'Aggiornati ${updated.length} brani');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app.library,
      builder: (context, _) {
        final q = query.toLowerCase();
        final tracks = _source.where((t) {
          if (onlyUnknown && t.genre != kUnknownGenre && t.artist != kUnknownArtist && t.album != kUnknownAlbum) {
            return false;
          }
          if (q.isEmpty) return true;
          return t.title.toLowerCase().contains(q) ||
              t.artist.toLowerCase().contains(q) ||
              t.album.toLowerCase().contains(q) ||
              t.genre.toLowerCase().contains(q) ||
              t.path.toLowerCase().contains(q);
        }).toList();
        final allSel = tracks.isNotEmpty && tracks.every((t) => selected.contains(t.path));
        return Scaffold(
          appBar: AppBar(title: Text(selected.isEmpty ? widget.title : '${selected.length} selezionati')),
          body: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Cerca (es. il nome di un artista nel titolo)',
                ),
                onChanged: (v) => setState(() => query = v),
              ),
            ),
            SwitchListTile(
              value: onlyUnknown,
              title: const Text('Solo brani con informazioni mancanti'),
              onChanged: (v) => setState(() => onlyUnknown = v),
            ),
            CheckboxListTile(
              value: allSel,
              title: Text('Seleziona tutti (${tracks.length})'),
              onChanged: (v) => setState(() {
                for (final t in tracks) {
                  v == true ? selected.add(t.path) : selected.remove(t.path);
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
                    subtitle: Text('${t.artist}  •  ${t.album}  •  ${t.genre}',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    secondary: IconButton(
                      tooltip: 'Modifica questo brano',
                      icon: const Icon(Icons.edit),
                      onPressed: () => editTrackDialog(context, t),
                    ),
                    onChanged: (v) => setState(() => v == true ? selected.add(t.path) : selected.remove(t.path)),
                  );
                },
              ),
            ),
          ]),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                onPressed: selected.isEmpty ? null : _apply,
                icon: const Icon(Icons.label),
                label: Text('Assegna artista / album / genere a ${selected.length} brani'),
              ),
            ),
          ),
        );
      },
    );
  }
}
