import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart' hide Track;

import 'app_state.dart';
import 'importer.dart';
import 'audio_handler.dart';
import 'settings.dart';
import 'ui/common.dart';
import 'ui/import_screen.dart';
import 'ui/library_screen.dart';
import 'ui/now_playing.dart';
import 'ui/playlists_screen.dart';
import 'ui/settings_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await app.settings.load();
  await app.library.load();
  await app.playlists.load();
  await app.player.init();
  if (!Platform.isAndroid) app.bt.onConnected = app.player.reloadAudioOutput;
  if (Platform.isAndroid) {
    try {
      await AudioService.init(
        builder: () => SirJoeAudioHandler(app.player),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.sirjoe.player.audio',
          androidNotificationChannelName: 'SirJoe Player',
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: true,
        ),
      );
    } catch (_) {}
  }
  runApp(const SirJoeApp());
}

class SirJoeApp extends StatelessWidget {
  const SirJoeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app.settings,
      builder: (context, _) => MaterialApp(
        title: 'SirJoe Player',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.dark,
        darkTheme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorSchemeSeed: const Color(0xFFFF8C1A),
          visualDensity: VisualDensity.comfortable,
        ),
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFFFF8C1A)),
        builder: (context, child) {
          final mq = MediaQuery.of(context);
          return MediaQuery(
            data: mq.copyWith(textScaler: TextScaler.linear(app.settings.largeText ? 1.15 : 1.0)),
            child: child!,
          );
        },
        home: const HomeScreen(),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    app.player.notice.addListener(_showNotice);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await app.firstRunSetup();
      await _startupBluetooth();
      // Lascia leggere il messaggio del Bluetooth prima di avvisare dei brani ricevuti.
      await Future.delayed(const Duration(seconds: 6));
      await _checkBluetoothReceived();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    app.player.notice.removeListener(_showNotice);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      app.player.saveState();
    }
    if (state == AppLifecycleState.resumed) {
      app.bt.refresh(app.settings.btDeviceId);
      _checkBluetoothReceived();
    }
  }

  void _showNotice() {
    final msg = app.player.notice.value;
    if (msg != null && mounted) toast(context, msg);
  }

  /// Gestione del Bluetooth all'apertura dell'app.
  Future<void> _startupBluetooth() async {
    final s = app.settings;
    final bt = app.bt;
    if (!bt.supported || s.btMode == BtStartMode.off) return;

    if (s.btDeviceId == null) {
      toast(
        context,
        'Scegli le cuffie o la cassa Bluetooth da collegare in automatico',
        action: SnackBarAction(label: 'Scegli', onPressed: () => chooseBtDevice(context)),
      );
      return;
    }

    if (s.btMode == BtStartMode.ask) {
      var remember = false;
      final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setD) => AlertDialog(
            icon: const Icon(Icons.bluetooth, size: 40),
            title: Text('Collegare ${s.btDeviceName}?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Vuoi ascoltare la musica sul dispositivo Bluetooth predefinito?'),
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: remember,
                  title: const Text('Ricorda la mia scelta'),
                  subtitle: const Text('Potrai cambiarla nelle Impostazioni'),
                  onChanged: (v) => setD(() => remember = v ?? false),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sì, collega')),
            ],
          ),
        ),
      );
      if (yes == null) return;
      if (remember) {
        s.btMode = yes ? BtStartMode.auto : BtStartMode.off;
        await s.save();
      }
      if (!yes) return;
    }

    final r = await bt.connectTo(s.btDeviceId!, s.btDeviceName ?? '', autoEnable: s.btAutoEnable);
    if (!mounted) return;
    toast(
      context,
      r.message,
      action: r.ok
          ? null
          : SnackBarAction(
              label: Platform.isMacOS ? 'Impostazioni' : 'Riprova',
              onPressed: () {
                if (Platform.isMacOS) {
                  bt.openSettings();
                } else {
                  _startupBluetoothRetry();
                }
              },
            ),
    );
  }

  /// Android: avvisa se sono arrivati brani via Bluetooth dal PC.
  int _lastBtReceivedCount = 0;
  Future<void> _checkBluetoothReceived() async {
    if (!Platform.isAndroid) return;
    final files = await Importer.bluetoothReceived(app.settings.btImported);
    if (!mounted || files.isEmpty || files.length == _lastBtReceivedCount) return;
    _lastBtReceivedCount = files.length;
    toast(
      context,
      'Hai ricevuto ${files.length} brani via Bluetooth',
      action: SnackBarAction(
        label: 'Importa',
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ImportFilesScreen(
            title: 'Ricevuti via Bluetooth',
            files: files,
            fromBluetooth: true,
            playlistName: 'Ricevuti via Bluetooth',
          ),
        )),
      ),
    );
  }

  Future<void> _startupBluetoothRetry() async {
    final s = app.settings;
    if (s.btDeviceId == null) return;
    final r = await app.bt.connectTo(s.btDeviceId!, s.btDeviceName ?? '', autoEnable: true);
    if (mounted) toast(context, r.message);
  }

  Widget _btButton() {
    return ListenableBuilder(
      listenable: Listenable.merge([app.bt, app.settings]),
      builder: (context, _) {
        final bt = app.bt;
        if (!bt.supported) return const SizedBox.shrink();
        final icon = bt.busy
            ? Icons.bluetooth_searching
            : bt.deviceConnected
                ? Icons.bluetooth_connected
                : bt.radioOn == false
                    ? Icons.bluetooth_disabled
                    : Icons.bluetooth;
        return TextButton.icon(
          onPressed: () async {
            final s = app.settings;
            if (s.btDeviceId == null) {
              chooseBtDevice(context);
              return;
            }
            final r = await bt.connectTo(s.btDeviceId!, s.btDeviceName ?? '', autoEnable: true);
            if (context.mounted) toast(context, r.message);
          },
          onLongPress: () => chooseBtDevice(context),
          icon: Icon(icon, color: bt.deviceConnected ? Colors.lightBlueAccent : null),
          label: Text(
            app.settings.btDeviceName == null
                ? 'Bluetooth'
                : bt.deviceConnected
                    ? app.settings.btDeviceName!
                    : 'Collega',
            overflow: TextOverflow.ellipsis,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final ps = app.player;
    final pages = const [
      LibraryScreen(),
      PlaylistsScreen(),
      NowPlayingScreen(),
      SettingsScreen(),
    ];
    final titles = ['Libreria', 'Playlist', 'In ascolto', 'Impostazioni'];

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space): ps.playPause,
        const SingleActivator(LogicalKeyboardKey.mediaPlayPause): ps.playPause,
        const SingleActivator(LogicalKeyboardKey.mediaTrackNext): ps.next,
        const SingleActivator(LogicalKeyboardKey.mediaTrackPrevious): ps.previous,
        const SingleActivator(LogicalKeyboardKey.arrowRight, control: true): ps.next,
        const SingleActivator(LogicalKeyboardKey.arrowLeft, control: true): ps.previous,
        const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true): () => ps.skipBy(10),
        const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): () => ps.skipBy(-10),
        const SingleActivator(LogicalKeyboardKey.arrowUp, control: true): () => ps.setVolume(app.settings.volume + 5),
        const SingleActivator(LogicalKeyboardKey.arrowDown, control: true): () => ps.setVolume(app.settings.volume - 5),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            title: Row(children: [
              const Icon(Icons.headphones),
              const SizedBox(width: 8),
              Flexible(child: Text('SirJoe Player · ${titles[tab]}', overflow: TextOverflow.ellipsis)),
            ]),
            actions: [
              IconButton(
                tooltip: 'Importa brani',
                icon: const Icon(Icons.download),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ImportScreen())),
              ),
              ConstrainedBox(constraints: const BoxConstraints(maxWidth: 220), child: _btButton()),
              const SizedBox(width: 8),
            ],
          ),
          body: IndexedStack(index: tab, children: pages),
          bottomNavigationBar: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (tab != 2) MiniPlayer(onOpen: () => setState(() => tab = 2)),
              NavigationBar(
                selectedIndex: tab,
                onDestinationSelected: (i) => setState(() => tab = i),
                destinations: const [
                  NavigationDestination(icon: Icon(Icons.library_music), label: 'Libreria'),
                  NavigationDestination(icon: Icon(Icons.queue_music), label: 'Playlist'),
                  NavigationDestination(icon: Icon(Icons.play_circle), label: 'In ascolto'),
                  NavigationDestination(icon: Icon(Icons.settings), label: 'Impostazioni'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
