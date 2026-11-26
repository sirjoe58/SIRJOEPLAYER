import 'dart:io';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../bluetooth.dart';
import '../models.dart';
import '../settings.dart';
import 'common.dart';
import 'import_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = app.settings;
    return ListenableBuilder(
      listenable: Listenable.merge([s, app.bt, app.player, app.library]),
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.only(bottom: 40),
          children: [
            const _Header('Bluetooth', Icons.bluetooth),
            if (!app.bt.supported)
              const ListTile(title: Text('Bluetooth non gestito su questo sistema'))
            else ...[
              ListTile(
                leading: const Icon(Icons.speaker, size: 32),
                title: const Text('Dispositivo predefinito'),
                subtitle: Text(s.btDeviceName ?? 'Nessuno: tocca per sceglierlo'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => chooseBtDevice(context),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text('All\'avvio dell\'app:', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
              RadioListTile<BtStartMode>(
                value: BtStartMode.auto,
                groupValue: s.btMode,
                title: const Text('Collegati da solo'),
                subtitle: const Text('Si collega subito al dispositivo predefinito'),
                onChanged: (v) => s.update((x) => x.btMode = v!),
              ),
              RadioListTile<BtStartMode>(
                value: BtStartMode.ask,
                groupValue: s.btMode,
                title: const Text('Chiedimelo ogni volta'),
                onChanged: (v) => s.update((x) => x.btMode = v!),
              ),
              RadioListTile<BtStartMode>(
                value: BtStartMode.off,
                groupValue: s.btMode,
                title: const Text('Non fare nulla'),
                onChanged: (v) => s.update((x) => x.btMode = v!),
              ),
              SwitchListTile(
                value: s.btAutoEnable,
                title: const Text('Accendi il Bluetooth se è spento'),
                subtitle: Text(Platform.isAndroid
                    ? 'Android mostrerà una richiesta: basta toccare "Consenti"'
                    : Platform.isMacOS
                        ? 'Su Mac potrebbe servire accenderlo dalle Impostazioni di Sistema'
                        : 'Il Bluetooth viene acceso automaticamente'),
                onChanged: (v) => s.update((x) => x.btAutoEnable = v),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Wrap(spacing: 12, runSpacing: 8, children: [
                  FilledButton.icon(
                    onPressed: s.btDeviceId == null || app.bt.busy
                        ? null
                        : () async {
                            final r = await app.bt.connectTo(s.btDeviceId!, s.btDeviceName ?? '',
                                autoEnable: s.btAutoEnable);
                            if (context.mounted) toast(context, r.message);
                          },
                    icon: app.bt.busy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.bluetooth_connected),
                    label: const Text('Collega adesso'),
                  ),
                  OutlinedButton.icon(
                    onPressed: app.bt.openSettings,
                    icon: const Icon(Icons.settings_bluetooth),
                    label: const Text('Impostazioni Bluetooth del sistema'),
                  ),
                ]),
              ),
              if (app.bt.status.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text('Stato: ${app.bt.status}'),
                ),
            ],
            const _Header('Libreria musicale', Icons.library_music),
            for (final f in s.folders)
              ListTile(
                leading: const Icon(Icons.folder),
                title: Text(f),
                trailing: IconButton(
                  tooltip: 'Togli cartella',
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: () async {
                    s.folders = s.folders.where((x) => x != f).toList();
                    await s.save();
                    app.library.scan(s.folders);
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Wrap(spacing: 12, runSpacing: 8, children: [
                FilledButton.icon(
                  onPressed: app.library.scanning ? null : () => app.addFolder(),
                  icon: const Icon(Icons.create_new_folder),
                  label: const Text('Aggiungi cartella'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ImportScreen())),
                  icon: const Icon(Icons.download),
                  label: const Text('Importa brani'),
                ),
                OutlinedButton.icon(
                  onPressed: app.library.scanning ? null : () => app.library.scan(s.folders),
                  icon: const Icon(Icons.refresh),
                  label: Text(app.library.scanning ? 'Aggiornamento...' : 'Aggiorna libreria'),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('${app.library.tracks.length} brani nella libreria'),
            ),
            const _Header('Audio', Icons.tune),
            if (!Platform.isAndroid && app.player.audioDevices.length > 1)
              ListTile(
                leading: const Icon(Icons.headphones),
                title: const Text('Uscita audio'),
                subtitle: DropdownButton<String>(
                  isExpanded: true,
                  value: app.player.audioDevices.any((d) => d.name == app.player.audioDevice?.name)
                      ? app.player.audioDevice?.name
                      : null,
                  items: [
                    for (final d in app.player.audioDevices)
                      DropdownMenuItem(
                        value: d.name,
                        child: Text(d.description.isEmpty ? d.name : d.description,
                            overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) {
                    final d = app.player.audioDevices.where((x) => x.name == v).firstOrNull;
                    if (d != null) app.player.setAudioDevice(d);
                  },
                ),
              ),
            SwitchListTile(
              value: s.gapless,
              title: const Text('Senza pause tra i brani (gapless)'),
              subtitle: const Text('Ideale per album live e dischi mixati'),
              onChanged: (v) {
                s.gapless = v;
                app.player.applyAudioOptions();
                s.save();
              },
            ),
            SwitchListTile(
              value: s.replayGain,
              title: const Text('Volume uniforme (ReplayGain)'),
              subtitle: const Text('Evita brani troppo forti o troppo piano, se il file lo supporta'),
              onChanged: (v) {
                s.replayGain = v;
                app.player.applyAudioOptions();
                s.save();
              },
            ),
            SwitchListTile(
              value: s.resumeLast,
              title: const Text('Riprendi da dove avevo lasciato'),
              onChanged: (v) => s.update((x) => x.resumeLast = v),
            ),
            const _Header('Aspetto', Icons.text_fields),
            SwitchListTile(
              value: s.largeText,
              title: const Text('Testo grande'),
              onChanged: (v) => s.update((x) => x.largeText = v),
            ),
            const _Header('Informazioni', Icons.info_outline),
            const ListTile(
              title: Text('SirJoe Player 1.0.2'),
              subtitle: Text('Lettore musicale con playlist, equalizzatore e Bluetooth automatico'),
            ),
            ListTile(
              title: const Text('Formati supportati'),
              subtitle: Text((kAudioExtensions.toList()..sort()).map((e) => e.toUpperCase()).join(', ')),
            ),
          ],
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  final String text;
  final IconData icon;
  const _Header(this.text, this.icon);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
        child: Row(children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(text,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  )),
        ]),
      );
}

/// Elenco dei dispositivi associati per scegliere quello predefinito.
Future<void> chooseBtDevice(BuildContext context) async {
  final s = app.settings;
  final picked = await showModalBottomSheet<BtDevice>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => const _DevicePicker(),
  );
  if (picked == null || !context.mounted) return;
  s.btDeviceId = picked.id;
  s.btDeviceName = picked.name;
  if (s.btMode == BtStartMode.off) s.btMode = BtStartMode.auto;
  await s.save();
  if (!context.mounted) return;
  toast(context, '${picked.name} è ora il dispositivo predefinito');
  if (!picked.connected) {
    final r = await app.bt.connectTo(picked.id, picked.name, autoEnable: s.btAutoEnable);
    if (context.mounted) toast(context, r.message);
  }
}

class _DevicePicker extends StatefulWidget {
  const _DevicePicker();

  @override
  State<_DevicePicker> createState() => _DevicePickerState();
}

class _DevicePickerState extends State<_DevicePicker> {
  late Future<List<BtDevice>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<BtDevice>> _load() async {
    final b = app.bt.backend;
    if (b != null && await b.isOn() == false && app.settings.btAutoEnable) {
      await b.turnOn();
    }
    return app.bt.pairedDevices();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
              child: Row(children: [
                Expanded(
                  child: Text('Scegli il dispositivo Bluetooth', style: Theme.of(context).textTheme.titleLarge),
                ),
                IconButton(
                  tooltip: 'Aggiorna',
                  icon: const Icon(Icons.refresh),
                  onPressed: () => setState(() => _future = _load()),
                ),
              ]),
            ),
            Expanded(
              child: FutureBuilder<List<BtDevice>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final list = snap.data ?? [];
                  if (list.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(children: [
                        const Text(
                          'Nessun dispositivo associato trovato.\n\n'
                          'Associa prima cuffie o cassa dalle Impostazioni Bluetooth del sistema '
                          '(una volta sola), poi torna qui e premi Aggiorna.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: app.bt.openSettings,
                          icon: const Icon(Icons.settings_bluetooth),
                          label: const Text('Apri Impostazioni Bluetooth'),
                        ),
                      ]),
                    );
                  }
                  return ListView(
                    children: [
                      for (final d in list)
                        ListTile(
                          leading: Icon(d.isAudio ? Icons.headphones : Icons.bluetooth, size: 32),
                          title: Text(d.name),
                          subtitle: Text(d.connected ? 'Collegato' : 'Non collegato'),
                          trailing: d.id == app.settings.btDeviceId
                              ? const Icon(Icons.star, color: Colors.amber)
                              : null,
                          onTap: () => Navigator.pop(context, d),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
