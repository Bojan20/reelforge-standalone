// HELIX dock — Audio DNA / brand-fingerprint panel (Sprint 15 Faza 4.C split #4).
//
// Brand identity editor: root key, mode, BPM range, instrument palette
// (14 instruments), audio profiles, win escalation, ambient layers,
// fingerprint display.
//
// Extracted from helix_screen.dart 2026-05-11.
//
// Content:
//   • _AudioDnaPanel(State)  — root widget + fingerprint editor state
//   • _DnaApplyButton(State) — apply-to-project button sa undo support
//   • _DnaField(State)       — labeled inline-edit text field

part of '../../helix_screen.dart';// ── 3.4 Audio DNA / Fingerprint Editor ──────────────────────────────────────

class _AudioDnaPanel extends StatefulWidget {
  const _AudioDnaPanel();
  @override
  State<_AudioDnaPanel> createState() => _AudioDnaPanelState();
}

class _AudioDnaPanelState extends State<_AudioDnaPanel> {
  // Audio DNA fields mirror the Rust AudioDna struct
  late String _brand;
  late double _bpmMin;
  late double _bpmMax;
  late String _rootKey;
  late String _mode;
  late List<String> _instruments;
  late String _baseProfile;
  late String _featureProfile;
  late double _winEscalation;
  late double _ambientLayerCount;

  late final SlotLabProjectProvider _proj;

  @override
  void initState() {
    super.initState();
    _proj = GetIt.instance<SlotLabProjectProvider>();
    _proj.addListener(_onProjectChanged);
    _loadFromProject();
  }

  @override
  void dispose() {
    _proj.removeListener(_onProjectChanged);
    super.dispose();
  }

  void _onProjectChanged() {
    if (!mounted) return;
    _loadFromProject();
    setState(() {});
  }

  void _loadFromProject() {
    final proj = _proj;
    _brand = proj.dnaBrand;
    _bpmMin = proj.dnaBpmMin;
    _bpmMax = proj.dnaBpmMax;
    _rootKey = proj.dnaRootKey;
    _mode = proj.dnaMode;
    _instruments = List.from(proj.dnaInstruments);
    _baseProfile = proj.dnaBaseProfile;
    _featureProfile = proj.dnaFeatureProfile;
    _winEscalation = proj.dnaWinEscalation;
    _ambientLayerCount = proj.dnaAmbientLayerCount;
  }

  static const _keys = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
  static const _modes = ['major', 'minor', 'dorian', 'mixolydian', 'pentatonic_major', 'pentatonic_minor', 'phrygian', 'lydian'];
  static const _allInstruments = ['piano', 'strings', 'brass', 'woodwinds', 'synth_pad', 'synth_lead',
    'ethnic_percussion', 'orchestral_percussion', 'choir', 'guitar', 'bass', 'harp', 'bells', 'mallets'];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Left: Identity
        Expanded(
          flex: 2,
          child: _DockCard(
            accent: FluxForgeTheme.accentPink,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DockLabel('BRAND IDENTITY', color: FluxForgeTheme.accentPink),
                const SizedBox(height: 8),
                _DnaField('Brand', _brand, (v) => setState(() => _brand = v)),
                const SizedBox(height: 8),
                Row(children: [
                  const SizedBox(width: 80, child: Text('Root Key',
                    style: TextStyle(fontFamily: 'monospace', fontSize: 9, color: FluxForgeTheme.textSecondary))),
                  Expanded(child: Wrap(spacing: 4, runSpacing: 4, children: _keys.map((k) =>
                    GestureDetector(
                      onTap: () => setState(() => _rootKey = k),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: _rootKey == k ? FluxForgeTheme.accentPink.withValues(alpha: 0.2) : Colors.transparent,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: _rootKey == k ? FluxForgeTheme.accentPink : FluxForgeTheme.borderSubtle),
                        ),
                        child: Text(k, style: TextStyle(fontFamily: 'monospace', fontSize: 9,
                          color: _rootKey == k ? FluxForgeTheme.accentPink : FluxForgeTheme.textTertiary)),
                      ),
                    )).toList())),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  const SizedBox(width: 80, child: Text('Mode',
                    style: TextStyle(fontFamily: 'monospace', fontSize: 9, color: FluxForgeTheme.textSecondary))),
                  Expanded(child: Wrap(spacing: 4, runSpacing: 4, children: _modes.map((m) =>
                    GestureDetector(
                      onTap: () => setState(() => _mode = m),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: _mode == m ? FluxForgeTheme.accentPurple.withValues(alpha: 0.2) : Colors.transparent,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: _mode == m ? FluxForgeTheme.accentPurple : FluxForgeTheme.borderSubtle),
                        ),
                        child: Text(m, style: TextStyle(fontFamily: 'monospace', fontSize: 8,
                          color: _mode == m ? FluxForgeTheme.accentPurple : FluxForgeTheme.textTertiary)),
                      ),
                    )).toList())),
                ]),
                const SizedBox(height: 12),
                _SfxPresetSlider(label: 'BPM Min', value: _bpmMin, min: 60, max: 200, suffix: '',
                  color: FluxForgeTheme.accentPink, onChanged: (v) => setState(() => _bpmMin = v)),
                _SfxPresetSlider(label: 'BPM Max', value: _bpmMax, min: 60, max: 200, suffix: '',
                  color: FluxForgeTheme.accentPink, onChanged: (v) => setState(() => _bpmMax = v)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Center: Instruments
        Expanded(
          flex: 2,
          child: _DockCard(
            accent: FluxForgeTheme.accentPink,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DockLabel('INSTRUMENT PALETTE', color: FluxForgeTheme.accentPink),
                const SizedBox(height: 8),
                Expanded(
                  child: Wrap(spacing: 6, runSpacing: 6, children: _allInstruments.map((inst) {
                    final active = _instruments.contains(inst);
                    return GestureDetector(
                      onTap: () => setState(() {
                        if (active) _instruments.remove(inst);
                        else _instruments.add(inst);
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: active ? FluxForgeTheme.accentCyan.withValues(alpha: 0.15) : FluxForgeTheme.bgSurface,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: active ? FluxForgeTheme.accentCyan.withValues(alpha: 0.5) : FluxForgeTheme.borderSubtle),
                        ),
                        child: Text(inst.replaceAll('_', ' '),
                          style: TextStyle(fontFamily: 'monospace', fontSize: 9,
                            color: active ? FluxForgeTheme.accentCyan : FluxForgeTheme.textTertiary,
                            fontWeight: active ? FontWeight.w600 : FontWeight.normal)),
                      ),
                    );
                  }).toList()),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Right: Profiles & Escalation
        Expanded(
          flex: 1,
          child: _DockCard(
            accent: FluxForgeTheme.accentPink,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DockLabel('AUDIO PROFILES', color: FluxForgeTheme.accentPink),
                const SizedBox(height: 8),
                _DnaField('Base', _baseProfile, (v) => setState(() => _baseProfile = v)),
                const SizedBox(height: 6),
                _DnaField('Feature', _featureProfile, (v) => setState(() => _featureProfile = v)),
                const SizedBox(height: 12),
                _DockLabel('ESCALATION', color: FluxForgeTheme.accentPink),
                const SizedBox(height: 6),
                _SfxPresetSlider(label: 'Win Scale', value: _winEscalation, min: 1, max: 3, suffix: 'x',
                  color: FluxForgeTheme.accentPink, onChanged: (v) => setState(() => _winEscalation = v)),
                _SfxPresetSlider(label: 'Ambient Layers', value: _ambientLayerCount, min: 1, max: 8, suffix: '',
                  color: FluxForgeTheme.accentPink, onChanged: (v) => setState(() => _ambientLayerCount = v)),
                const SizedBox(height: 6),
                // DNA fingerprint visual
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.accentPink.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: FluxForgeTheme.accentPink.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('FINGERPRINT', style: TextStyle(fontFamily: 'monospace', fontSize: 8,
                        color: FluxForgeTheme.accentPink, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Text('$_rootKey $_mode  ${_bpmMin.round()}-${_bpmMax.round()} BPM',
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: FluxForgeTheme.textPrimary)),
                      Text(_instruments.join(' · '),
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 8, color: FluxForgeTheme.textTertiary),
                        overflow: TextOverflow.ellipsis, maxLines: 2),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // Apply DNA to project
                _DnaApplyButton(
                  rootKey: _rootKey, mode: _mode,
                  bpmMin: _bpmMin, bpmMax: _bpmMax,
                  instruments: List.from(_instruments),
                  brand: _brand,
                  baseProfile: _baseProfile,
                  featureProfile: _featureProfile,
                  winEscalation: _winEscalation,
                  ambientLayerCount: _ambientLayerCount,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// Apply DNA fingerprint to project metadata via SlotLabProjectProvider
class _DnaApplyButton extends StatefulWidget {
  final String rootKey, mode, brand;
  final double bpmMin, bpmMax;
  final List<String> instruments;
  final String baseProfile, featureProfile;
  final double winEscalation, ambientLayerCount;
  const _DnaApplyButton({
    required this.rootKey, required this.mode, required this.brand,
    required this.bpmMin, required this.bpmMax, required this.instruments,
    this.baseProfile = 'ambient_dark', this.featureProfile = 'epic_orchestral',
    this.winEscalation = 1.5, this.ambientLayerCount = 3,
  });
  @override
  State<_DnaApplyButton> createState() => _DnaApplyButtonState();
}
class _DnaApplyButtonState extends State<_DnaApplyButton> {
  bool _applied = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      onTap: () {
        silentRun('dna.applyToProject', () {
          // 1. Apply BPM midpoint to engine transport
          final bpmMid = ((widget.bpmMin + widget.bpmMax) / 2).roundToDouble();
          GetIt.instance<EngineProvider>().setTempo(bpmMid);
          // 2. Persist all DNA fields to SlotLabProjectProvider
          GetIt.instance<SlotLabProjectProvider>().setAudioDna(
            brand: widget.brand,
            rootKey: widget.rootKey,
            mode: widget.mode,
            bpmMin: widget.bpmMin,
            bpmMax: widget.bpmMax,
            instruments: widget.instruments,
            baseProfile: widget.baseProfile,
            featureProfile: widget.featureProfile,
            winEscalation: widget.winEscalation,
            ambientLayerCount: widget.ambientLayerCount,
          );
        });
        setState(() => _applied = true);
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => _applied = false);
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: _applied
            ? FluxForgeTheme.accentGreen.withValues(alpha: 0.15)
            : FluxForgeTheme.accentPink.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: _applied
            ? FluxForgeTheme.accentGreen.withValues(alpha: 0.5)
            : FluxForgeTheme.accentPink.withValues(alpha: 0.4)),
        ),
        child: Center(child: Text(
          _applied ? '✓ DNA APPLIED' : 'APPLY DNA TO PROJECT',
          style: TextStyle(fontFamily: 'monospace', fontSize: 9, fontWeight: FontWeight.w700,
            color: _applied ? FluxForgeTheme.accentGreen : FluxForgeTheme.accentPink),
        )),
      ),
    ),
  );
}

class _DnaField extends StatefulWidget {
  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  const _DnaField(this.label, this.value, this.onChanged);
  @override
  State<_DnaField> createState() => _DnaFieldState();
}

class _DnaFieldState extends State<_DnaField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_DnaField old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && _ctrl.text != widget.value) {
      _ctrl.text = widget.value;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(children: [
    SizedBox(width: 80, child: Text(widget.label,
      style: const TextStyle(fontFamily: 'monospace', fontSize: 9, color: FluxForgeTheme.textSecondary))),
    Expanded(child: SizedBox(
      height: 24,
      child: TextField(
        controller: _ctrl,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: FluxForgeTheme.textPrimary),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: FluxForgeTheme.borderSubtle)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: FluxForgeTheme.borderSubtle)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: FluxForgeTheme.accentPink)),
        ),
        onSubmitted: widget.onChanged,
      ),
    )),
  ]);
}
