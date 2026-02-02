import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:fluxforge_ui/widgets/dsp/plugin_delay_report_panel.dart';
import 'package:fluxforge_ui/providers/mixer_provider.dart';
import 'package:fluxforge_ui/src/rust/native_ffi.dart';

void main() {
  group('PdcEntry', () {
    test('creates entry with correct values', () {
      const entry = PdcEntry(
        trackName: 'Track 1',
        trackId: 'track_1',
        pluginName: 'Pro-L 2',
        slotIndex: 0,
        pdcSamples: 512,
        pdcMs: 10.67,
      );

      expect(entry.trackName, 'Track 1');
      expect(entry.pdcSamples, 512);
      expect(entry.pdcMs, closeTo(10.67, 0.01));
    });

    test('multiple entries can be sorted by pdc', () {
      final entries = [
        const PdcEntry(
          trackName: 'Track 1',
          trackId: 'track_1',
          pluginName: 'Plugin A',
          slotIndex: 0,
          pdcSamples: 256,
          pdcMs: 5.33,
        ),
        const PdcEntry(
          trackName: 'Track 2',
          trackId: 'track_2',
          pluginName: 'Plugin B',
          slotIndex: 0,
          pdcSamples: 1024,
          pdcMs: 21.33,
        ),
        const PdcEntry(
          trackName: 'Track 3',
          trackId: 'track_3',
          pluginName: 'Plugin C',
          slotIndex: 1,
          pdcSamples: 512,
          pdcMs: 10.67,
        ),
      ];

      // Sort descending by PDC
      final sorted = List<PdcEntry>.from(entries)
        ..sort((a, b) => b.pdcSamples.compareTo(a.pdcSamples));

      expect(sorted[0].pluginName, 'Plugin B'); // 1024 samples
      expect(sorted[1].pluginName, 'Plugin C'); // 512 samples
      expect(sorted[2].pluginName, 'Plugin A'); // 256 samples
    });

    test('total PDC calculation', () {
      final entries = [
        const PdcEntry(
          trackName: 'Track 1',
          trackId: 'track_1',
          pluginName: 'Plugin A',
          slotIndex: 0,
          pdcSamples: 256,
          pdcMs: 5.33,
        ),
        const PdcEntry(
          trackName: 'Track 2',
          trackId: 'track_2',
          pluginName: 'Plugin B',
          slotIndex: 0,
          pdcSamples: 512,
          pdcMs: 10.67,
        ),
      ];

      final total = entries.fold<int>(0, (sum, e) => sum + e.pdcSamples);
      expect(total, 768);
    });
  });

  group('PluginDelayReportPanel', () {
    testWidgets('renders correctly', (tester) async {
      final ffi = NativeFFI.instance;
      final mixer = MixerProvider(ffi);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<MixerProvider>.value(value: mixer),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 400,
                height: 300,
                child: PluginDelayReportPanel(
                  sampleRate: 48000.0,
                ),
              ),
            ),
          ),
        ),
      );

      // Widget should render (won't have data without MixerProvider)
      expect(find.byType(PluginDelayReportPanel), findsOneWidget);
    });
  });
}
