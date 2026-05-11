// FAZA 5.1.4 — SlotLab MUSIC > GEN panel widget tests.
//
// The panel itself is pure-Dart; the only non-test seam is the FFI generator.
// We inject a stub `GenerateFn` so we don't need `librf_bridge.dylib` loaded
// in the test process. Tests verify:
//   - panel pumps without throwing and shows the GENERATE call-to-action
//   - tapping GENERATE forwards prompt / duration / arc / stage hint to the
//     injected generator
//   - successful result populates the provenance / waveform area
//   - failed result surfaces the error message banner
//   - empty prompt short-circuits with a validation error (no FFI call)

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/services/generative_audio_service.dart';
import 'package:fluxforge_ui/widgets/slot_lab/lower_zone/slotlab_music_gen_panel.dart';

GenerationResult _fakeResult({
  String backend = 'mock',
  String model = 'mock-additive-v1',
  int? seed = 42,
  int frames = 480,
}) {
  // Build a deterministic ramp so the sparkline painter has real data and
  // peak detection is non-zero.
  final pcm = Float32List(frames);
  for (var i = 0; i < frames; i++) {
    pcm[i] = (i / frames) * 0.8 - 0.4;
  }
  return GenerationResult(
    pcm: pcm,
    sampleRateHz: 48000,
    channels: 1,
    latencyMs: 7,
    metadata: GenerationMetadata(
      backendId: backend,
      modelId: model,
      seed: seed,
      generatedAtUtc: '2026-05-11T12:00:00Z',
      durationSeconds: frames / 48000,
      frameCount: frames,
    ),
  );
}

void main() {
  group('SlotLabMusicGenPanel', () {
    testWidgets('renders GENERATE button and empty output placeholder',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 600));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SlotLabMusicGenPanel(
              generator: (_) async => _fakeResult(),
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('gen_panel_generate_button')),
          findsOneWidget);
      expect(find.textContaining('No clip yet'), findsOneWidget);
    });

    testWidgets('forwards prompt / duration / arc / stage hint to generator',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 600));
      GenerationRequest? captured;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SlotLabMusicGenPanel(
              initialPrompt: 'bright bonus trigger',
              initialDurationSeconds: 4.0,
              initialStageHint: SlotStageHint.bonusTrigger,
              generator: (req) async {
                captured = req;
                return _fakeResult();
              },
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('gen_panel_generate_button')));
      await tester.pump(); // start
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(captured!.prompt, 'bright bonus trigger');
      expect(captured!.durationSeconds, 4.0);
      expect(captured!.style.stageHint, SlotStageHint.bonusTrigger);
      // Arc defaults to the editor's normalized flat preset (two endpoints).
      expect(captured!.style.emotionalArc, isNotNull);
      expect(captured!.style.emotionalArc!.points.length, greaterThanOrEqualTo(2));
    });

    testWidgets('successful generation shows provenance fields', (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 600));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SlotLabMusicGenPanel(
              generator: (_) async => _fakeResult(
                backend: 'mock',
                model: 'mock-additive-v1',
                seed: 1337,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('gen_panel_generate_button')));
      await tester.pumpAndSettle();

      expect(find.text('PROVENANCE'), findsOneWidget);
      expect(find.text('mock'), findsOneWidget);
      expect(find.text('mock-additive-v1'), findsOneWidget);
      expect(find.text('1337'), findsOneWidget);
      // PEAK overlay rendered on waveform card.
      expect(find.textContaining('PEAK'), findsOneWidget);
    });

    testWidgets('failed generation surfaces error banner', (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 600));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SlotLabMusicGenPanel(
              generator: (_) async {
                throw GenerationException('arc not monotonic');
              },
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('gen_panel_generate_button')));
      await tester.pumpAndSettle();

      expect(find.textContaining('arc not monotonic'), findsOneWidget);
      // Output still shows the empty placeholder because no result landed.
      expect(find.textContaining('No clip yet'), findsOneWidget);
    });

    testWidgets('empty prompt short-circuits with validation error',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 600));
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SlotLabMusicGenPanel(
              initialPrompt: '',
              generator: (_) async {
                calls++;
                return _fakeResult();
              },
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('gen_panel_generate_button')));
      await tester.pumpAndSettle();

      expect(calls, 0);
      expect(find.text('Prompt is required'), findsOneWidget);
    });

    testWidgets('seed text field is parsed when provided', (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 600));
      GenerationRequest? captured;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SlotLabMusicGenPanel(
              generator: (req) async {
                captured = req;
                return _fakeResult();
              },
            ),
          ),
        ),
      );

      // Type a seed.
      await tester.enterText(
          find.byKey(const Key('gen_panel_seed_field')), '9001');
      await tester.tap(find.byKey(const Key('gen_panel_generate_button')));
      await tester.pumpAndSettle();

      expect(captured?.seed, 9001);
    });
  });

  group('SlotLabMusicGenPanel narrow layout', () {
    testWidgets('stacks vertically below 720px width', (tester) async {
      await tester.binding.setSurfaceSize(const Size(500, 1000));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SlotLabMusicGenPanel(
              generator: (_) async => _fakeResult(),
            ),
          ),
        ),
      );

      // Both cards still rendered, just stacked.
      expect(find.byKey(const Key('gen_panel_generate_button')),
          findsOneWidget);
      expect(find.text('OUTPUT'), findsOneWidget);
    });
  });
}
