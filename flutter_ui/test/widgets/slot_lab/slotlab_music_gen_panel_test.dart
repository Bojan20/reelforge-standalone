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
  ComplianceLevel complianceLevel = ComplianceLevel.pass,
  List<ComplianceFinding>? complianceFindings,
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
      compliance: ComplianceReport(
        level: complianceLevel,
        findings: complianceFindings ??
            const [
              ComplianceFinding(
                id: 'clean',
                level: ComplianceLevel.pass,
                message: 'All compliance checks passed',
              ),
            ],
        peakDbfs: -6.0,
        rmsDbfs: -12.0,
        dcOffset: 0.0,
        clipCount: 0,
        nanCount: 0,
        silenceRatio: 0.02,
        durationSeconds: frames / 48000,
      ),
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

  // ─── FAZA 5.1.8 compliance badge ────────────────────────────────────────
  group('SlotLabMusicGenPanel compliance badge', () {
    testWidgets('renders PASS badge after clean generation', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 700));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SlotLabMusicGenPanel(
              generator: (_) async => _fakeResult(),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('gen_panel_generate_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('gen_panel_compliance_badge')),
          findsOneWidget);
      expect(find.byKey(const Key('gen_panel_compliance_details')),
          findsOneWidget);
      // PASS label visible (badge text).
      expect(
        find.descendant(
          of: find.byKey(const Key('gen_panel_compliance_badge')),
          matching: find.text('PASS'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('FAIL badge shows when generator returns failing manifest',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 700));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SlotLabMusicGenPanel(
              generator: (_) async => _fakeResult(
                complianceLevel: ComplianceLevel.fail,
                complianceFindings: const [
                  ComplianceFinding(
                    id: 'clipping',
                    level: ComplianceLevel.fail,
                    message: '128 clipped samples',
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('gen_panel_generate_button')));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const Key('gen_panel_compliance_badge')),
          matching: find.text('FAIL'),
        ),
        findsOneWidget,
      );
      // Failing-finding message bubbles into the details strip.
      expect(find.text('128 clipped samples'), findsOneWidget);
    });

    testWidgets('WARN badge shows when generator returns warning manifest',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 700));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SlotLabMusicGenPanel(
              generator: (_) async => _fakeResult(
                complianceLevel: ComplianceLevel.warn,
                complianceFindings: const [
                  ComplianceFinding(
                    id: 'peak-too-hot',
                    level: ComplianceLevel.warn,
                    message: 'Peak -0.4 dBFS exceeds headroom',
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('gen_panel_generate_button')));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const Key('gen_panel_compliance_badge')),
          matching: find.text('WARN'),
        ),
        findsOneWidget,
      );
    });
  });

  // ─── FAZA 5.1.7 variations ──────────────────────────────────────────────
  group('SlotLabMusicGenPanel variations', () {
    testWidgets('× N button renders 5 variation cards on success',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 700));
      var batchCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SlotLabMusicGenPanel(
              generator: (_) async => _fakeResult(),
              variationsGenerator: (req, count) async {
                batchCount = count;
                return List.generate(
                  count,
                  (i) => _fakeResult(seed: 1000 + i),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('gen_panel_variations_button')));
      await tester.pumpAndSettle();

      expect(batchCount, 5);
      expect(find.byKey(const Key('gen_panel_variation_strip')),
          findsOneWidget);
      for (var i = 0; i < 5; i++) {
        expect(find.byKey(Key('gen_panel_variation_card_$i')),
            findsOneWidget);
      }
      // First variation is auto-selected, so provenance shows seed 1000.
      final seedText = tester.widget<Text>(
          find.byKey(const Key('gen_panel_provenance_seed_value')));
      expect(seedText.data, '1000');
    });

    testWidgets('tapping a variation card promotes it to main output',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 700));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SlotLabMusicGenPanel(
              generator: (_) async => _fakeResult(),
              variationsGenerator: (req, count) async {
                return List.generate(
                  count,
                  (i) => _fakeResult(seed: 2000 + i),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('gen_panel_variations_button')));
      await tester.pumpAndSettle();

      Text seedText() => tester.widget<Text>(
          find.byKey(const Key('gen_panel_provenance_seed_value')));

      // Initially #1 selected → seed 2000 in provenance.
      expect(seedText().data, '2000');

      // Tap #3 (index 2).
      await tester.tap(find.byKey(const Key('gen_panel_variation_card_2')));
      await tester.pumpAndSettle();

      expect(seedText().data, '2002');
    });

    testWidgets('plain GENERATE after variations clears the strip',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 700));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SlotLabMusicGenPanel(
              generator: (_) async => _fakeResult(seed: 999),
              variationsGenerator: (req, count) async {
                return List.generate(
                    count, (i) => _fakeResult(seed: 3000 + i));
              },
            ),
          ),
        ),
      );

      // First run variations.
      await tester.tap(find.byKey(const Key('gen_panel_variations_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('gen_panel_variation_strip')),
          findsOneWidget);

      // Now plain GENERATE — strip must disappear.
      await tester.tap(find.byKey(const Key('gen_panel_generate_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('gen_panel_variation_strip')),
          findsNothing);
      // Provenance now shows single-generate seed (999).
      final seedText = tester.widget<Text>(
          find.byKey(const Key('gen_panel_provenance_seed_value')));
      expect(seedText.data, '999');
    });

    testWidgets('failed variations call shows error banner', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 700));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SlotLabMusicGenPanel(
              generator: (_) async => _fakeResult(),
              variationsGenerator: (_, _) async {
                throw GenerationException('seed collision');
              },
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('gen_panel_variations_button')));
      await tester.pumpAndSettle();

      expect(find.textContaining('seed collision'), findsOneWidget);
      expect(find.byKey(const Key('gen_panel_variation_strip')),
          findsNothing);
    });

    testWidgets('empty prompt blocks variations call', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 700));
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SlotLabMusicGenPanel(
              initialPrompt: '',
              generator: (_) async => _fakeResult(),
              variationsGenerator: (_, _) async {
                calls++;
                return [_fakeResult()];
              },
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('gen_panel_variations_button')));
      await tester.pumpAndSettle();

      expect(calls, 0);
      expect(find.text('Prompt is required'), findsOneWidget);
    });
  });
}
