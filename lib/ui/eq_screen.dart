import 'package:flutter/material.dart';

import '../app_state.dart';
import '../settings.dart';

class EqScreen extends StatefulWidget {
  const EqScreen({super.key});

  @override
  State<EqScreen> createState() => _EqScreenState();
}

class _EqScreenState extends State<EqScreen> {
  final s = app.settings;

  void _apply() {
    app.player.applyEq();
    s.save();
    setState(() {});
  }

  String _label(int hz) => hz >= 1000 ? '${hz ~/ 1000}k' : '$hz';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Equalizzatore')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            title: const Text('Equalizzatore attivo', style: TextStyle(fontWeight: FontWeight.bold)),
            value: s.eqEnabled,
            onChanged: (v) {
              s.eqEnabled = v;
              _apply();
            },
          ),
          const SizedBox(height: 8),
          const Text('Impostazioni pronte:'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in kEqPresets.entries)
                ChoiceChip(
                  label: Text(e.key),
                  selected: s.eqPreset == e.key,
                  onSelected: (_) {
                    s.eqPreset = e.key;
                    s.eqGains = List.of(e.value);
                    s.eqEnabled = true;
                    _apply();
                  },
                ),
            ],
          ),
          const SizedBox(height: 24),
          Opacity(
            opacity: s.eqEnabled ? 1 : 0.4,
            child: SizedBox(
              height: 260,
              child: Row(
                children: [
                  for (var i = 0; i < kEqBands.length; i++)
                    Expanded(
                      child: Column(
                        children: [
                          Text('${s.eqGains[i] > 0 ? '+' : ''}${s.eqGains[i].round()}',
                              style: const TextStyle(fontSize: 12)),
                          Expanded(
                            child: RotatedBox(
                              quarterTurns: 3,
                              child: Slider(
                                value: s.eqGains[i],
                                min: -12,
                                max: 12,
                                divisions: 24,
                                onChanged: s.eqEnabled
                                    ? (v) {
                                        s.eqGains[i] = v;
                                        s.eqPreset = 'Personalizzato';
                                        setState(() {});
                                      }
                                    : null,
                                onChangeEnd: (_) => _apply(),
                              ),
                            ),
                          ),
                          Text(_label(kEqBands[i]), style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: OutlinedButton.icon(
              onPressed: () {
                s.eqGains = List.filled(10, 0);
                s.eqPreset = 'Piatto';
                _apply();
              },
              icon: const Icon(Icons.restart_alt),
              label: const Text('Azzera'),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Bassi a sinistra, acuti a destra. Il volume viene compensato da solo per evitare distorsioni.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13),
          ),
        ],
      ),
    );
  }
}
