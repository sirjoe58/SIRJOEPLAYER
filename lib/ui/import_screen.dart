import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../app_state.dart';
import '../importer.dart';
import 'common.dart';

/// Schermata principale "Importa brani".
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  late Future<List<Volume>> _volumes;
  Future<List<String>>? _btFiles;
  String _dest = '';

  @override
  void initState() {
    super.initState();
    _refresh();
    Importer.destinationDir().then((d) {
      if (mounted) setState(() => _dest = d);
    });
  }

  void _refresh() {
    setState(() {
      _volumes = _loadVolumes();
      if (Platform.isAndroid) {
        _btFiles = app.ensureMusicPermission().then((_) => Importer.bluetoothReceived(app.settings.btImported));
      }
    });
  }

  Future<List<Volume>> _loadVolumes() async {
    await app.ensureMusicPermission();
    return Importer.externalVolumes();
  }

  void _openFolder(String dir, String title) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ImportFilesScreen(title: title, sourceDir: dir),
    ));
  }

  Future<void> _chooseFolder() async {
    if (!await app.ensureMusicPermission()) return;
    final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Scegli la cartella da importare');
    if (dir != null && mounted) _openFolder(dir, p.basename(dir));
  }

  Future<void> _chooseFiles() async {
    if (!await app.ensureMusicPermission()) return;
    final res = await FilePicker.platform.pickFiles(
      dialogTitle: 'Scegli i brani da importare',
      allowMultiple: true,
      type: Platform.isAndroid ? FileType.audio : FileType.any,
    );
    final files = res?.paths.whereType<String>().toList() ?? [];
    if (files.isEmpty || !mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ImportFilesScreen(title: 'Brani scelti', files: files),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Importa brani'),
        actions: [
          IconButton(tooltip: 'Aggiorna', icon: const Icon(Icons.refresh), onPressed: _refresh),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          if (_dest.isNotEmpty)
            Card(
              margin: const EdgeInsets.all(16),
              child: ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('I brani importati vengono copiati in:'),
                subtitle: Text(_dest),
                trailing: Platform.isAndroid
                    ? null
                    : IconButton(
                        tooltip: 'Apri cartella',
                        icon: const Icon(Icons.folder_open),
                        onPressed: () => Importer.openFolder(_dest),
                      ),
              ),
            ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Wrap(spacing: 12, runSpacing: 12, children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18)),
                onPressed: _chooseFolder,
                icon: const Icon(Icons.folder_open),
                label: const Text('Scegli la cartella da importare'),
              ),
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18)),
                onPressed: _chooseFiles,
                icon: const Icon(Icons.audio_file),
                label: const Text('Scegli singoli brani'),
              ),
            ]),
          ),

          // ---- Chiavetta USB ----
          _Section(Platform.isAndroid ? 'Da chiavetta USB (OTG)' : 'Da chiavetta USB o disco esterno', Icons.usb),
          FutureBuilder<List<Volume>>(
            future: _volumes,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator());
              }
              final vols = snap.data ?? [];
              return Column(children: [
                if (vols.isEmpty)
                  ListTile(
                    leading: const Icon(Icons.usb_off),
                    title: const Text('Nessuna chiavetta trovata'),
                    subtitle: Text(Platform.isAndroid
                        ? 'Collega la chiavetta al telefono con l\'adattatore OTG, poi premi Aggiorna. '
                            'Se non compare, usa "Scegli una cartella" e seleziona la chiavetta.'
                        : 'Inserisci la chiavetta e premi Aggiorna.'),
                  ),
                for (final v in vols)
                  ListTile(
                    leading: Icon(v.removable ? Icons.usb : Icons.storage, size: 32),
                    title: Text(v.label),
                    subtitle: const Text('Tocca per vedere i brani e importarli'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openFolder(v.path, v.label),
                  ),
              ]);
            },
          ),

          // ---- Bluetooth ----
          _Section(Platform.isAndroid ? 'Dal PC via Bluetooth' : 'Bluetooth', Icons.bluetooth),
          if (Platform.isAndroid) ..._androidBluetooth() else ..._desktopBluetooth(),

          // ---- Cavo USB ----
          _Section(Platform.isAndroid ? 'Dal PC con cavo USB' : 'Al telefono con cavo USB', Icons.cable),
          if (Platform.isAndroid) ..._androidUsb() else ..._desktopUsb(),

          // ---- Altro ----
          const _Section('Altro', Icons.more_horiz),
          ListTile(
            leading: const Icon(Icons.folder_open, size: 32),
            title: const Text('Scegli una cartella'),
            subtitle: const Text('Importa tutti i brani di una cartella e delle sue sottocartelle'),
            onTap: _chooseFolder,
          ),
          ListTile(
            leading: const Icon(Icons.audio_file, size: 32),
            title: const Text('Scegli singoli brani'),
            onTap: _chooseFiles,
          ),
        ],
      ),
      bottomNavigationBar: MiniPlayer(onOpen: () => openNowPlaying(context)),
    );
  }

  List<Widget> _androidBluetooth() => [
        FutureBuilder<List<String>>(
          future: _btFiles,
          builder: (context, snap) {
            final files = snap.data ?? [];
            final loading = snap.connectionState != ConnectionState.done;
            return ListTile(
              leading: Badge(
                isLabelVisible: files.isNotEmpty,
                label: Text('${files.length}'),
                child: const Icon(Icons.bluetooth_audio, size: 32),
              ),
              title: Text(loading
                  ? 'Cerco i brani ricevuti...'
                  : files.isEmpty
                      ? 'Nessun brano nuovo ricevuto via Bluetooth'
                      : '${files.length} brani ricevuti da importare'),
              subtitle: const Text('Dalla cartella dove Android salva i file Bluetooth'),
              trailing: files.isEmpty ? null : const Icon(Icons.chevron_right),
              onTap: files.isEmpty
                  ? null
                  : () => Navigator.of(context)
                      .push(MaterialPageRoute(
                        builder: (_) => ImportFilesScreen(
                          title: 'Ricevuti via Bluetooth',
                          files: files,
                          fromBluetooth: true,
                          playlistName: 'Ricevuti via Bluetooth',
                        ),
                      ))
                      .then((_) => _refresh()),
            );
          },
        ),
        const _HowTo(
          title: 'Come inviare i brani dal PC al telefono via Bluetooth',
          steps: [
            'Sul telefono tieni attivo il Bluetooth (il PC deve essere già associato).',
            'Windows: sul PC fai clic destro sui brani → "Invia a" → "Dispositivo Bluetooth" e scegli il telefono. '
                'Oppure apri SirJoe Player sul PC → Importa brani → "Invia brani al telefono".',
            'Mac: apri "Scambio file Bluetooth" (Bluetooth File Exchange), scegli i brani e il telefono.',
            'Sul telefono accetta il trasferimento.',
            'Torna qui e premi Aggiorna: i brani ricevuti compaiono sopra, pronti da importare.',
          ],
        ),
      ];

  List<Widget> _desktopBluetooth() => [
        ListTile(
          leading: const Icon(Icons.send_to_mobile, size: 32),
          title: const Text('Invia brani al telefono'),
          subtitle: Text(Platform.isWindows
              ? 'Apre la procedura di Windows: scegli il telefono e i brani'
              : 'Apre "Scambio file Bluetooth": scegli i brani e il telefono'),
          onTap: () async {
            final ok = await Importer.bluetoothSendWizard();
            if (!ok && context.mounted) toast(context, 'Non riesco ad aprire la procedura Bluetooth del sistema');
          },
        ),
        ListTile(
          leading: const Icon(Icons.call_received, size: 32),
          title: const Text('Ricevi brani via Bluetooth'),
          subtitle: const Text('Prepara il computer a ricevere brani da un telefono o da un altro PC'),
          onTap: () async {
            final ok = await Importer.bluetoothReceiveWizard();
            if (!context.mounted) return;
            if (!ok) {
              toast(context, 'Non riesco ad aprire la procedura Bluetooth del sistema');
            } else {
              toast(context, 'Quando il trasferimento è finito, usa "Importa i brani ricevuti" qui sotto');
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.download_done, size: 32),
          title: const Text('Importa i brani ricevuti'),
          subtitle: Text(Importer.desktopReceivedFolder() ?? 'Scegli la cartella dove sono stati salvati'),
          onTap: () {
            final dir = Importer.desktopReceivedFolder();
            if (dir == null) {
              _chooseFolder();
            } else {
              _openFolder(dir, 'Brani ricevuti');
            }
          },
        ),
      ];

  List<Widget> _androidUsb() => [
        ListTile(
          leading: const Icon(Icons.refresh, size: 32),
          title: const Text('Ho copiato i brani: aggiorna la libreria'),
          subtitle: const Text('Cerca i brani nuovi nelle cartelle della libreria'),
          onTap: () async {
            await app.ensureImportFolderInLibrary();
            await app.library.scan(app.settings.folders);
            if (context.mounted) toast(context, 'Libreria aggiornata: ${app.library.tracks.length} brani');
          },
        ),
        const _HowTo(
          title: 'Come copiare i brani dal PC con il cavo',
          steps: [
            'Collega il telefono al PC con il cavo USB.',
            'Sul telefono tocca la notifica "USB" e scegli "Trasferimento file".',
            'Sul PC apri il telefono (in Windows: "Questo PC"; su Mac serve il programma gratuito "OpenMTP").',
            'Entra in Music → SirJoe Player (o crea la cartella) e trascina lì i brani.',
            'Torna qui e premi "Aggiorna la libreria".',
          ],
        ),
      ];

  List<Widget> _desktopUsb() => [
        ListTile(
          leading: const Icon(Icons.phone_android, size: 32),
          title: const Text('Copia i brani sul telefono'),
          subtitle: Text(Platform.isWindows
              ? 'Apre "Questo PC" e la cartella dei brani: trascina i brani nel telefono'
              : 'Apre la cartella dei brani: trascinali nel telefono con OpenMTP'),
          onTap: () async {
            if (_dest.isNotEmpty) await Importer.openFolder(_dest);
            if (Platform.isWindows) {
              await Process.run('explorer.exe', ['shell:MyComputerFolder']);
            }
          },
        ),
        const _HowTo(
          title: 'Come copiare i brani sul telefono con il cavo',
          steps: [
            'Collega il telefono al computer con il cavo USB.',
            'Sul telefono tocca la notifica "USB" e scegli "Trasferimento file".',
            'Apri il telefono sul computer (Windows: "Questo PC"; Mac: programma gratuito "OpenMTP").',
            'Trascina i brani nella cartella Music → SirJoe Player del telefono.',
            'Sul telefono apri SirJoe Player → Importa brani → "Aggiorna la libreria".',
          ],
        ),
      ];
}

class _Section extends StatelessWidget {
  final String text;
  final IconData icon;
  const _Section(this.text, this.icon);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Row(children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    )),
          ),
        ]),
      );
}

class _HowTo extends StatelessWidget {
  final String title;
  final List<String> steps;
  const _HowTo({required this.title, required this.steps});

  @override
  Widget build(BuildContext context) => ExpansionTile(
        leading: const Icon(Icons.help_outline),
        title: Text(title),
        childrenPadding: const EdgeInsets.fromLTRB(24, 0, 16, 12),
        children: [
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                CircleAvatar(radius: 12, child: Text('${i + 1}', style: const TextStyle(fontSize: 12))),
                const SizedBox(width: 12),
                Expanded(child: Text(steps[i])),
              ]),
            ),
        ],
      );
}

/// Elenco dei brani da importare, con caselle di spunta.
class ImportFilesScreen extends StatefulWidget {
  final String title;
  final String? sourceDir;
  final List<String>? files;
  final bool fromBluetooth;
  final String? playlistName;

  const ImportFilesScreen({
    super.key,
    required this.title,
    this.sourceDir,
    this.files,
    this.fromBluetooth = false,
    this.playlistName,
  });

  @override
  State<ImportFilesScreen> createState() => _ImportFilesScreenState();
}

class _ImportFilesScreenState extends State<ImportFilesScreen> {
  List<String>? files;
  final selected = <String>{};
  bool makePlaylist = true;
  late final TextEditingController _plName =
      TextEditingController(text: widget.playlistName ?? widget.title);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = widget.files ??
        (widget.sourceDir == null ? <String>[] : await Importer.findAudio(widget.sourceDir!));
    if (!mounted) return;
    setState(() {
      files = list;
      selected.addAll(list);
    });
  }

  String _label(String f) {
    if (widget.sourceDir != null && p.isWithin(widget.sourceDir!, f)) {
      return p.relative(f, from: widget.sourceDir!);
    }
    return p.basename(f);
  }

  Future<void> _import() async {
    final list = files!.where(selected.contains).toList();
    var cancelled = false;
    final progress = ValueNotifier<(int, int, String)>((0, list.length, ''));

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Importazione in corso'),
        content: ValueListenableBuilder<(int, int, String)>(
          valueListenable: progress,
          builder: (_, v, __) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LinearProgressIndicator(value: v.$2 == 0 ? null : v.$1 / v.$2, minHeight: 8),
              const SizedBox(height: 12),
              Text('${v.$1} di ${v.$2} brani'),
              Text(v.$3, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => cancelled = true,
            child: const Text('Annulla'),
          ),
        ],
      ),
    );

    ImportResult result = const ImportResult([], 0, 0, false);
    String? error;
    try {
      // Su chiavetta si conservano le sottocartelle sotto il nome della chiavetta/cartella.
      final sub = widget.sourceDir != null ? _safeName(widget.title) : (widget.fromBluetooth ? 'Bluetooth' : null);
      result = await Importer.copyFiles(
        list,
        baseDir: widget.sourceDir,
        subfolder: sub,
        onProgress: (d, t, c) => progress.value = (d, t, c),
        isCancelled: () => cancelled,
      );
      progress.value = (list.length, list.length, 'Aggiorno la libreria...');
      await app.ensureImportFolderInLibrary();
      await app.library.addFiles(result.copied);
      if (widget.fromBluetooth) {
        await app.settings.markBtImported(list.take(result.copied.length + result.failed));
      }
      if (makePlaylist && result.copied.isNotEmpty) {
        final name = _plName.text.trim().isEmpty ? widget.title : _plName.text.trim();
        final existing = app.playlists.items.where((x) => x.name == name).firstOrNull;
        if (existing != null) {
          app.playlists.addTracks(existing, result.copied);
        } else {
          app.playlists.create(name, result.copied);
        }
      }
    } catch (e) {
      error = '$e';
    }

    if (!mounted) return;
    Navigator.of(context).pop(); // chiude la finestra di avanzamento
    final newOnes = result.copied.length - result.skipped;
    final msg = StringBuffer(error != null
        ? 'Si è verificato un problema: $error\n\n'
        : result.cancelled
            ? 'Importazione interrotta. '
            : 'Importazione completata. ')
      ..write('$newOnes brani copiati');
    if (result.skipped > 0) msg.write(', ${result.skipped} erano già presenti');
    if (result.failed > 0) msg.write(', ${result.failed} non copiati');
    if (makePlaylist && result.copied.isNotEmpty) msg.write('. Playlist "${_plName.text}" creata');
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(result.failed == 0 && error == null ? Icons.check_circle : Icons.warning_amber, size: 48),
        title: Text(error == null ? 'Fatto' : 'Attenzione'),
        content: Text('$msg.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          if (result.copied.isNotEmpty)
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                app.player.playPaths(result.copied);
              },
              icon: const Icon(Icons.play_arrow),
              label: const Text('Ascolta ora'),
            ),
        ],
      ),
    );
    if (mounted) Navigator.of(context).pop();
  }

  static String _safeName(String s) =>
      s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '').trim().isEmpty ? 'Importati' : s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '').trim();

  @override
  Widget build(BuildContext context) {
    final list = files;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title), actions: [
        if (widget.sourceDir != null)
          TextButton.icon(
            onPressed: () async {
              final dir = await FilePicker.platform.getDirectoryPath(
                dialogTitle: 'Scegli la cartella da importare',
              );
              if (dir == null || !context.mounted) return;
              Navigator.of(context).pushReplacement(MaterialPageRoute(
                builder: (_) => ImportFilesScreen(title: p.basename(dir), sourceDir: dir),
              ));
            },
            icon: const Icon(Icons.folder_open),
            label: const Text('Scegli un\'altra cartella'),
          ),
      ]),
      body: list == null
          ? const Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                CircularProgressIndicator(),
                SizedBox(height: 12),
                Text('Cerco i brani...'),
              ]),
            )
          : list.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('Nessun brano musicale trovato qui.', textAlign: TextAlign.center),
                  ),
                )
              : Column(
                  children: [
                    CheckboxListTile(
                      value: selected.length == list.length,
                      title: Text('Seleziona tutti (${list.length} brani)'),
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          selected.addAll(list);
                        } else {
                          selected.clear();
                        }
                      }),
                    ),
                    SwitchListTile(
                      value: makePlaylist,
                      title: const Text('Crea anche una playlist con questi brani'),
                      onChanged: (v) => setState(() => makePlaylist = v),
                    ),
                    if (makePlaylist)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: TextField(
                          controller: _plName,
                          decoration: const InputDecoration(labelText: 'Nome della playlist'),
                        ),
                      ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView.builder(
                        itemCount: list.length,
                        itemBuilder: (context, i) {
                          final f = list[i];
                          return CheckboxListTile(
                            value: selected.contains(f),
                            secondary: const Icon(Icons.music_note),
                            title: Text(p.basenameWithoutExtension(f), maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(_label(f), maxLines: 1, overflow: TextOverflow.ellipsis),
                            onChanged: (v) => setState(() {
                              if (v == true) {
                                selected.add(f);
                              } else {
                                selected.remove(f);
                              }
                            }),
                          );
                        },
                      ),
                    ),
                  ],
                ),
      bottomNavigationBar: list == null || list.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                  onPressed: selected.isEmpty ? null : _import,
                  icon: const Icon(Icons.download),
                  label: Text('Importa ${selected.length} brani'),
                ),
              ),
            ),
    );
  }
}
