// HELIX dock — SFX Pipeline panel (Sprint 15 Faza 4.C split #2).
//
// 6-step SFX wizard (Import/Scan → Trim/Clean → Loudness → Format →
// Naming/Assign → Export) sa preset config sliderima, progress tracking,
// file selection, stage mapping.
//
// Extracted from `helix_screen.dart` 2026-05-11 — part of monolith split
// from 14013 LOC.  Pattern mirrors `flow_panel.dart` (Faza 4.C split #1).
//
// Content:
//   • `_SfxPipelinePanel`  — StatelessWidget root
//   • `_StatRow`           — label/value helper
//   • `_SfxNavButton(State)` — wizard step nav button
//   • `_SfxPresetSlider`   — preset slider (gain, fade, threshold, etc.)
//   • `_SfxToggle`         — boolean preset toggle

part of '../../helix_screen.dart';

// ���─ 3.1 SFX Pipeline Wizard Panel ───────────────────────────────────────────

class _SfxPipelinePanel extends StatelessWidget {
  const _SfxPipelinePanel();

  @override
  Widget build(BuildContext context) {
    return Consumer<SfxPipelineProvider>(
      builder: (_, sfx, child) {
        final step = sfx.currentStep;
        final steps = SfxWizardStep.values;
        return Row(
          children: [
            // Left: Step navigation
            Flexible(
              flex: 2,
              child: _DockCard(
                accent: FluxForgeTheme.accentCyan,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DockLabel('SFX PIPELINE', color: FluxForgeTheme.accentCyan),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView(
                        children: steps.asMap().entries.map((e) {
                          final s = e.value;
                          final active = s == step;
                          final done = s.index < step.index;
                          return GestureDetector(
                            onTap: () => sfx.goToStep(s),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              margin: const EdgeInsets.only(bottom: 4),
                              decoration: BoxDecoration(
                                color: active ? FluxForgeTheme.accentCyan.withValues(alpha: 0.12)
                                    : done ? FluxForgeTheme.accentGreen.withValues(alpha: 0.06)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(6),
                                border: active ? Border.all(color: FluxForgeTheme.accentCyan.withValues(alpha: 0.4)) : null,
                              ),
                              child: Row(children: [
                                Icon(
                                  done ? Icons.check_circle_rounded : active ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                                  size: 14,
                                  color: done ? FluxForgeTheme.accentGreen : active ? FluxForgeTheme.accentCyan : FluxForgeTheme.textTertiary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(child: Text(
                                  '${e.key + 1}. ${s.title}',
                                  style: FluxForgeTheme.dockMono(size: 10,
                                    color: active ? FluxForgeTheme.accentCyan : FluxForgeTheme.textSecondary,
                                    weight: active ? FontWeight.w600 : FontWeight.normal),
                                )),
                              ]),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    // Navigation buttons
                    Row(children: [
                      if (sfx.canGoBack)
                        _SfxNavButton(label: '← BACK', onTap: sfx.previousStep),
                      const Spacer(),
                      if (!sfx.isLastStep && sfx.canGoNext)
                        _SfxNavButton(label: 'NEXT →', onTap: sfx.nextStep, primary: true)
                      else if (sfx.isLastStep)
                        _SfxNavButton(label: 'FINISH', onTap: sfx.setProcessing, primary: true),
                    ]),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Center: Step content
            Expanded(
              flex: 3,
              child: _DockCard(
                accent: FluxForgeTheme.accentCyan,
                child: _buildStepContent(sfx, step),
              ),
            ),
            const SizedBox(width: 12),
            // Right: Stats/Preview
            Flexible(
              flex: 2,
              child: _DockCard(
                accent: FluxForgeTheme.accentCyan,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DockLabel('STATS', color: FluxForgeTheme.accentCyan),
                    const SizedBox(height: 8),
                    _StatRow('Scanned', '${sfx.totalScanned}'),
                    _StatRow('Selected', '${sfx.selectedCount}'),
                    _StatRow('Stereo', '${sfx.stereoCount}'),
                    _StatRow('Mono', '${sfx.monoCount}'),
                    _StatRow('With Silence', '${sfx.filesWithSilence}'),
                    _StatRow('DC Offset', '${sfx.filesWithDcOffset}'),
                    const SizedBox(height: 12),
                    _DockLabel('LOUDNESS', color: FluxForgeTheme.accentCyan),
                    const SizedBox(height: 6),
                    _StatRow('Loudest', '${sfx.loudestLufs.toStringAsFixed(1)} LUFS'),
                    _StatRow('Quietest', '${sfx.quietestLufs.toStringAsFixed(1)} LUFS'),
                    _StatRow('Average', '${sfx.avgLufs.toStringAsFixed(1)} LUFS'),
                    const Spacer(),
                    if (sfx.isProcessing) ...[
                      LinearProgressIndicator(
                        value: sfx.progress.overallProgress,
                        backgroundColor: FluxForgeTheme.bgSurface,
                        valueColor: const AlwaysStoppedAnimation(FluxForgeTheme.accentCyan),
                      ),
                      const SizedBox(height: 6),
                      Text('${sfx.progress.currentFilename ?? ''}',
                        style: FluxForgeTheme.dockMono(size: 8,
                          color: FluxForgeTheme.textTertiary),
                        overflow: TextOverflow.ellipsis),
                    ],
                    if (sfx.isCompleted)
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: FluxForgeTheme.accentGreen.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(children: [
                          const Icon(Icons.check_circle, size: 14, color: FluxForgeTheme.accentGreen),
                          const SizedBox(width: 6),
                          Text('COMPLETE', style: FluxForgeTheme.dockMono(size: 10,
                            color: FluxForgeTheme.accentGreen, weight: FontWeight.w600)),
                        ]),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStepContent(SfxPipelineProvider sfx, SfxWizardStep step) {
    return switch (step) {
      SfxWizardStep.importScan => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DockLabel('IMPORT & SCAN', color: FluxForgeTheme.accentCyan),
          const SizedBox(height: 8),
          Text('Drop WAV/FLAC files or select a folder to scan.',
            style: FluxForgeTheme.dockMono(size: 10, color: FluxForgeTheme.textSecondary)),
          const SizedBox(height: 12),
          Expanded(
            child: sfx.scanResults.isEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.folder_open_rounded, size: 48, color: FluxForgeTheme.accentCyan.withValues(alpha: 0.15)),
                  const SizedBox(height: 12),
                  Text('No files scanned yet', style: FluxForgeTheme.dockMono(size: 11, color: FluxForgeTheme.textTertiary)),
                  const SizedBox(height: 4),
                  Text('Drop WAV/FLAC files here to begin',
                    style: FluxForgeTheme.dockMono(size: 9, color: FluxForgeTheme.textTertiary.withValues(alpha: 0.6))),
                ]))
              : ListView.builder(
                  itemCount: sfx.scanResults.length,
                  itemBuilder: (_, i) {
                    final r = sfx.scanResults[i];
                    final selected = sfx.selectedFiles.contains(r);
                    return ListTile(
                      dense: true,
                      leading: Icon(selected ? Icons.check_box : Icons.check_box_outline_blank,
                        size: 16, color: selected ? FluxForgeTheme.accentCyan : FluxForgeTheme.textTertiary),
                      title: Text(r.filename, style: FluxForgeTheme.dockMono(size: 10, color: FluxForgeTheme.textPrimary)),
                      subtitle: Text('${r.sampleRate}Hz ${r.channels}ch ${r.durationSeconds.toStringAsFixed(1)}ms',
                        style: FluxForgeTheme.dockMono(size: 8, color: FluxForgeTheme.textTertiary)),
                      onTap: () => sfx.toggleFileSelection(i),
                    );
                  },
                ),
          ),
          Row(children: [
            _SfxNavButton(label: 'SELECT ALL', onTap: sfx.selectAllFiles, primary: true),
            const SizedBox(width: 6),
            _SfxNavButton(label: 'DESELECT ALL', onTap: sfx.deselectAllFiles),
            const SizedBox(width: 6),
            _SfxNavButton(label: 'INVERT', onTap: sfx.invertSelection),
          ]),
        ],
      ),
      SfxWizardStep.trimClean => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DockLabel('TRIM & CLEAN', color: FluxForgeTheme.accentCyan),
          const SizedBox(height: 8),
          _SfxPresetSlider(label: 'Silence Threshold', value: sfx.preset.thresholdDb,
            min: -80, max: -20, suffix: 'dB',
            onChanged: (v) => sfx.updatePreset((p) => p.copyWith(thresholdDb: v))),
          _SfxPresetSlider(label: 'Fade In', value: sfx.preset.fadeInMs,
            min: 0, max: 50, suffix: 'ms',
            onChanged: (v) => sfx.updatePreset((p) => p.copyWith(fadeInMs: v))),
          _SfxPresetSlider(label: 'Fade Out', value: sfx.preset.fadeOutMs,
            min: 0, max: 100, suffix: 'ms',
            onChanged: (v) => sfx.updatePreset((p) => p.copyWith(fadeOutMs: v))),
          const Spacer(),
          Row(children: [
            Icon(Icons.content_cut_rounded, size: 14, color: FluxForgeTheme.accentCyan.withValues(alpha: 0.6)),
            const SizedBox(width: 6),
            Flexible(child: Text('Auto-trim silence + apply fades to ${sfx.selectedCount} files',
              overflow: TextOverflow.ellipsis,
              style: FluxForgeTheme.dockMono(size: 9, color: FluxForgeTheme.textTertiary))),
          ]),
        ],
      ),
      SfxWizardStep.loudnessLevel => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DockLabel('LOUDNESS & LEVEL', color: FluxForgeTheme.accentCyan),
          const SizedBox(height: 8),
          _SfxPresetSlider(label: 'Target LUFS', value: sfx.preset.targetLufs,
            min: -30, max: -6, suffix: 'LUFS',
            onChanged: (v) => sfx.updatePreset((p) => p.copyWith(targetLufs: v))),
          _SfxPresetSlider(label: 'True Peak Limit', value: sfx.preset.truePeakCeiling,
            min: -3, max: 0, suffix: 'dBTP',
            onChanged: (v) => sfx.updatePreset((p) => p.copyWith(truePeakCeiling: v))),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: FluxForgeTheme.accentPurple.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(6)),
            child: Row(children: [
              const Icon(Icons.info_outline, size: 14, color: FluxForgeTheme.accentPurple),
              const SizedBox(width: 8),
              Expanded(child: Text('Slot standard: -14 LUFS / -1.0 dBTP. Matches casino floor playback.',
                style: FluxForgeTheme.dockMono(size: 9, color: FluxForgeTheme.textSecondary))),
            ]),
          ),
        ],
      ),
      SfxWizardStep.formatChannel => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DockLabel('FORMAT & CHANNELS', color: FluxForgeTheme.accentCyan),
          const SizedBox(height: 8),
          _SfxPresetSlider(label: 'Sample Rate', value: sfx.preset.sampleRate.toDouble(),
            min: 22050, max: 96000, suffix: 'Hz',
            onChanged: (v) => sfx.updatePreset((p) => p.copyWith(sampleRate: v.round()))),
          Row(children: [
            SizedBox(width: 120, child: Text('Output Format',
              style: FluxForgeTheme.dockMono(size: 9, color: FluxForgeTheme.textSecondary))),
            Text(sfx.preset.outputFormat.name.toUpperCase(),
              style: FluxForgeTheme.dockMono(size: 10,
                color: FluxForgeTheme.accentCyan, weight: FontWeight.w600)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            _SfxToggle(label: 'DC Offset Remove', active: sfx.preset.removeDcOffset,
              onTap: () => sfx.updatePreset((p) => p.copyWith(removeDcOffset: !p.removeDcOffset))),
            const SizedBox(width: 12),
            _SfxToggle(label: 'Normalize Peak', active: sfx.preset.preNormalizePeak,
              onTap: () => sfx.updatePreset((p) => p.copyWith(preNormalizePeak: !p.preNormalizePeak))),
          ]),
        ],
      ),
      SfxWizardStep.namingAssign => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DockLabel('NAMING & ASSIGN', color: FluxForgeTheme.accentCyan),
          const SizedBox(height: 8),
          Text('Map processed files to game stages for auto-assignment.',
            style: FluxForgeTheme.dockMono(size: 10, color: FluxForgeTheme.textSecondary)),
          const SizedBox(height: 8),
          _StatRow('Matched', '${sfx.matchedCount} / ${sfx.stageMappings.length}'),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: sfx.stageMappings.length,
              itemBuilder: (_, i) {
                final m = sfx.stageMappings[i];
                final matched = m.stageId != null && m.stageId!.isNotEmpty;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  margin: const EdgeInsets.only(bottom: 4),
                  decoration: BoxDecoration(
                    color: matched ? FluxForgeTheme.accentGreen.withValues(alpha: 0.06) : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(children: [
                    Icon(matched ? Icons.link : Icons.link_off, size: 12,
                      color: matched ? FluxForgeTheme.accentGreen : FluxForgeTheme.textTertiary),
                    const SizedBox(width: 8),
                    Expanded(child: Text(m.sourceFilename, overflow: TextOverflow.ellipsis,
                      style: FluxForgeTheme.dockMono(size: 9, color: FluxForgeTheme.textPrimary))),
                    const SizedBox(width: 8),
                    Text(m.stageId ?? 'unassigned',
                      style: FluxForgeTheme.dockMono(size: 9,
                        color: matched ? FluxForgeTheme.accentCyan : FluxForgeTheme.textTertiary)),
                  ]),
                );
              },
            ),
          ),
        ],
      ),
      SfxWizardStep.exportFinish => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DockLabel('EXPORT & FINISH', color: FluxForgeTheme.accentCyan),
          const SizedBox(height: 8),
          if (sfx.isCompleted && sfx.result != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: FluxForgeTheme.accentGreen.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: FluxForgeTheme.accentGreen.withValues(alpha: 0.3)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.check_circle, size: 18, color: FluxForgeTheme.accentGreen),
                  const SizedBox(width: 8),
                  Text('PIPELINE COMPLETE', style: FluxForgeTheme.dockMono(size: 12,
                    color: FluxForgeTheme.accentGreen, weight: FontWeight.w700)),
                ]),
                const SizedBox(height: 8),
                Text('${sfx.result!.files.length} files processed | ${sfx.result!.outputDirectory}',
                  style: FluxForgeTheme.dockMono(size: 9, color: FluxForgeTheme.textSecondary)),
              ]),
            ),
          ] else if (sfx.isProcessing) ...[
            const Center(child: CircularProgressIndicator(color: FluxForgeTheme.accentCyan)),
          ] else ...[
            Text('Ready to process. Click FINISH to start the pipeline.',
              style: FluxForgeTheme.dockMono(size: 10, color: FluxForgeTheme.textSecondary)),
            const Spacer(),
            _SfxNavButton(label: 'RESET PIPELINE', onTap: sfx.reset),
          ],
        ],
      ),
    };
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  const _StatRow(this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(children: [
      SizedBox(width: 80, child: Text(label,
        style: FluxForgeTheme.dockMono(size: 9, color: FluxForgeTheme.textTertiary))),
      Expanded(child: Text(value,
        style: FluxForgeTheme.dockMono(size: 9, color: FluxForgeTheme.textSecondary),
        textAlign: TextAlign.right)),
    ]),
  );
}

class _SfxNavButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final bool primary;
  const _SfxNavButton({required this.label, required this.onTap, this.primary = false});
  @override
  State<_SfxNavButton> createState() => _SfxNavButtonState();
}

class _SfxNavButtonState extends State<_SfxNavButton> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    final accent = FluxForgeTheme.accentCyan;
    final isActive = widget.primary;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: FluxMotion.quick,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: isActive
              ? accent.withValues(alpha: _hovered ? 0.22 : 0.15)
              : _hovered
                ? FluxForgeTheme.bgSurface.withValues(alpha: 0.8)
                : FluxForgeTheme.bgSurface,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isActive
                ? accent.withValues(alpha: _hovered ? 0.6 : 0.4)
                : _hovered
                  ? FluxForgeTheme.borderSubtle.withValues(alpha: 0.8)
                  : FluxForgeTheme.borderSubtle,
            ),
          ),
          child: Text(widget.label, style: FluxForgeTheme.dockMono(
            size: 9,
            color: isActive ? accent : (_hovered ? FluxForgeTheme.textPrimary : FluxForgeTheme.textSecondary),
            weight: FontWeight.w600)),
        ),
      ),
    );
  }
}

class _SfxPresetSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final String suffix;
  final ValueChanged<double> onChanged;
  final Color? color;
  const _SfxPresetSlider({required this.label, required this.value,
    required this.min, required this.max, required this.suffix,
    required this.onChanged, this.color});
  @override
  Widget build(BuildContext context) {
    final c = color ?? FluxForgeTheme.accentCyan;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        SizedBox(width: 120, child: Text(label,
          style: FluxForgeTheme.dockMono(size: 9, color: FluxForgeTheme.textSecondary))),
        Expanded(child: SliderTheme(
          data: SliderThemeData(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: SliderComponentShape.noOverlay,
            activeTrackColor: c,
            inactiveTrackColor: FluxForgeTheme.bgSurface,
            thumbColor: c,
            overlayColor: c.withValues(alpha: 0.1),
          ),
          child: Slider(value: value.clamp(min, max), min: min, max: max, onChanged: onChanged),
        )),
        SizedBox(width: 70, child: Text('${value.toStringAsFixed(1)} $suffix',
          style: FluxForgeTheme.dockMono(size: 9, color: c),
          textAlign: TextAlign.right)),
      ]),
    );
  }
}

class _SfxToggle extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _SfxToggle({required this.label, required this.active, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Row(children: [
      Icon(active ? Icons.check_box : Icons.check_box_outline_blank,
        size: 16, color: active ? FluxForgeTheme.accentCyan : FluxForgeTheme.textTertiary),
      const SizedBox(width: 6),
      Text(label, style: FluxForgeTheme.dockMono(size: 10,
        color: active ? FluxForgeTheme.accentCyan : FluxForgeTheme.textSecondary)),
    ]),
  );
}

