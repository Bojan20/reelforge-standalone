// HELIX dock — AUDIO panel (Sprint 15 Faza 4.C split #8).
//
// Master meters + fader (130 px left strip), OrbMixer + NeuralBindOrb
// (148 px middle), HelixEventNexus (expanded right) — pure-trigger
// event matrix sa 281 stages.  Sprint 13 redizajn.
//
// Extracted from helix_screen.dart 2026-05-11.
//
// Content:
//   • _AudioPanel(State) — root widget sa master fader + nexus container

part of '../../helix_screen.dart';// ── AUDIO Panel ──────────────────────────────────────────────────────────────

class _AudioPanel extends StatefulWidget {
  const _AudioPanel();

  @override
  State<_AudioPanel> createState() => _AudioPanelState();
}

class _AudioPanelState extends State<_AudioPanel> {
  double _masterFader = 1.0; // A6: master output fader — synced from engine

  @override
  void initState() {
    super.initState();
    try {
      _masterFader = NativeFFI.instance.getMasterVolume();
    } catch (_) {
      _masterFader = 1.0; // engine not ready yet, default to unity gain
    }
  }

  void _showAutoBindDialog(BuildContext context) async {
    final result = await showDialog<AutoBindV2Result>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AutoBindDialogV2(),
    );
    if (result == null || !mounted) return;

    if (result.analysis.matchedCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No matching sound files found in folder'),
          backgroundColor: Color(0xFF442222),
        ),
      );
      return;
    }

    // Trigger reload (syncs assignments → composite events → EventRegistry)
    SlotLabScreen.triggerAutoBindReload(result.folderPath);

    if (mounted) {
      final renamed = result.didRename ? ' (renamed to FFNC)' : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Auto-Bind: ${result.analysis.uniqueStageCount} stages bound$renamed'),
          backgroundColor: FluxForgeTheme.bgMid,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Reactivity: rebuild when MiddlewareProvider or NeuroAudioProvider change
    try {
      return ListenableBuilder(
        listenable: Listenable.merge([
          GetIt.instance<MiddlewareProvider>(),
          GetIt.instance<NeuroAudioProvider>(),
        ]),
        builder: (context, _) {
          try {
            return _buildContent(context);
          } catch (e) {
            return _renderHelixErrorFallback('AUDIO BUILD', e);
          }
        },
      );
    } catch (e) {
      return _renderHelixErrorFallback('AUDIO INIT', e);
    }
  }

  Widget _buildContent(BuildContext context) {
    final neuro = GetIt.instance<NeuroAudioProvider>();
    final out = neuro.output;

    // Derive master levels from neuro audio adaptation output × master fader
    final masterL = (out.arousal * 0.6 + out.engagement * 0.4).clamp(0.0, 1.0) * _masterFader;
    final masterR = (out.arousal * 0.55 + out.engagement * 0.45).clamp(0.0, 1.0) * _masterFader;
    final peak = math.max(masterL, masterR);
    final peakDb = peak > 0.001 ? (20 * math.log(peak) / 2.302585) : -60.0;

    // 2026-05-10 — EVENT NEXUS replaces the legacy 8-channel preview.  The
    // master fader, master meters and OrbMixer remain as a compact left
    // strip; auto-bind drop target (NeuralBindOrb) lives next to the orb.
    // The expanded right column hosts the full pure-trigger event matrix
    // covering EVERY stage, EVERY parameter — Boki direktiva 2026-05-10:
    // "event samo trigeruje zvuk, niko ne odlučuje koliko traje".
    return Row(
      children: [
        // ── LEFT STRIP: master meters + fader (compact, 130px) ────────────
        SizedBox(
          width: 130,
          child: _DockCard(
            accent: FluxForgeTheme.accentCyan,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DockLabel('MASTER', color: FluxForgeTheme.accentCyan),
                const SizedBox(height: 6),
                _MeterRow(label: 'L', value: masterL),
                const SizedBox(height: 4),
                _MeterRow(label: 'R', value: masterR),
                const SizedBox(height: 8),
                Row(children: [
                  _DockLabel('FADER', color: FluxForgeTheme.accentCyan),
                  const SizedBox(width: 4),
                  Expanded(
                    child: LayoutBuilder(builder: (_, c) => GestureDetector(
                      onTapDown: (d) {
                        final v = (d.localPosition.dx / c.maxWidth).clamp(0.0, 1.0);
                        setState(() => _masterFader = v);
                        silentRun('fader.setMasterVolume', () { NativeFFI.instance.setMasterVolume(v); });
                      },
                      onHorizontalDragUpdate: (d) {
                        final v = (d.localPosition.dx / c.maxWidth).clamp(0.0, 1.0);
                        setState(() => _masterFader = v);
                        silentRun('fader.setMasterVolume', () { NativeFFI.instance.setMasterVolume(v); });
                      },
                      child: Container(
                        height: 8,
                        decoration: BoxDecoration(
                          color: FluxForgeTheme.bgElevated,
                          borderRadius: BorderRadius.circular(3)),
                        child: Stack(children: [
                          FractionallySizedBox(
                            widthFactor: _masterFader,
                            alignment: Alignment.centerLeft,
                            child: Container(decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [
                                FluxForgeTheme.accentGreen, FluxForgeTheme.accentCyan]),
                              borderRadius: BorderRadius.circular(3))),
                          ),
                        ]),
                      ),
                    )),
                  ),
                ]),
                const SizedBox(height: 4),
                Text('${(_masterFader * 100).toStringAsFixed(0)}%  ·  ${peakDb.toStringAsFixed(1)} dB',
                  style: TextStyle(fontFamily: 'monospace', fontSize: 8,
                    color: peakDb > -6 ? FluxForgeTheme.accentOrange : FluxForgeTheme.accentCyan)),
                const Spacer(),
                Row(children: [
                  _DockLabel('VOL', color: FluxForgeTheme.accentCyan),
                  const SizedBox(width: 2),
                  Flexible(child: Text('${(out.volumeEnvelopeScale * 100).toStringAsFixed(0)}%',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 9, color: FluxForgeTheme.accentCyan))),
                  const Spacer(),
                  _DockLabel('CMP', color: FluxForgeTheme.accentPurple),
                  const SizedBox(width: 2),
                  Flexible(child: Text('${(out.compressionModifier * 100).toStringAsFixed(0)}%',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 9, color: FluxForgeTheme.accentPurple))),
                ]),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        // ── ORB + BIND (148px) ─────────────────────────────────────────────
        SizedBox(
          width: 148,
          child: _DockCard(
            accent: FluxForgeTheme.accentPurple,
            child: Column(
              children: [
                Builder(builder: (ctx) {
                  try {
                    return OrbMixer(
                      dsp: GetIt.instance<MixerDSPProvider>(),
                      size: 100,
                    );
                  } catch (e) {
                    return _renderHelixErrorFallback('ORB', e, fontSize: 8);
                  }
                }),
                const SizedBox(height: 6),
                _DockLabel('AUTO-BIND', color: FluxForgeTheme.accentPurple),
                const SizedBox(height: 4),
                // Neural Bind Orb — instant drag & drop audio binding (RAW mode)
                Builder(builder: (ctx) {
                  try {
                    return NeuralBindOrb.large(
                      onBindComplete: (analysis, path) {
                        SlotLabScreen.triggerAutoBindReload(path);
                      },
                    );
                  } catch (e) {
                    return _renderHelixErrorFallback('BIND', e, fontSize: 8);
                  }
                }),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        // ── EVENT NEXUS (expanded) ─────────────────────────────────────────
        const Expanded(child: HelixEventNexus()),
      ],
    );
  }
}
