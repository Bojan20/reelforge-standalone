// AI Composer panel — the user-facing pipeline UI for HELIX AI tab.
//
// One screen, three sections stacked top-to-bottom:
//   1. Provider header (which provider is active + healthy?)
//   2. Composer input (description + jurisdictions + run)
//   3. Output (asset map + brief + voice direction + grade)

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../models/ai_composer.dart';
import '../../services/ai_composer_service.dart';
import '../../theme/flux_forge_theme.dart';
import 'ai_provider_settings_dialog.dart';
import 'ai_audio_settings_dialog.dart';
import 'ai_audio_progress_dialog.dart';

class AiComposerPanel extends StatefulWidget {
  const AiComposerPanel({super.key});

  @override
  State<AiComposerPanel> createState() => _AiComposerPanelState();
}

class _AiComposerPanelState extends State<AiComposerPanel> {
  late final AiComposerService _service;
  late final TextEditingController _descCtrl;

  final Set<String> _selectedJurisdictions = {'UKGC', 'MGA'};
  bool _includeBrief = true;
  bool _includeVo = true;
  bool _includeGrade = true;

  static const List<String> _allJurisdictions = [
    'UKGC',
    'MGA',
    'AGCO',
    'SE',
    'DK',
    'NL',
    'AU',
  ];

  @override
  void initState() {
    super.initState();
    _service = GetIt.instance<AiComposerService>();
    _service.addListener(_onChanged);
    _descCtrl = TextEditingController();
    // Bootstrap selection + credentials presence; describe is on-demand (slow).
    _service.refreshSelection();
    _service.refreshCredentialsPresence();
  }

  @override
  void dispose() {
    _service.removeListener(_onChanged);
    _descCtrl.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _openSettings() async {
    await showDialog<void>(
      context: context,
      builder: (_) => AiProviderSettingsDialog(service: _service),
    );
  }

  Future<void> _openAudioSettings() async {
    await showDialog<void>(
      context: context,
      builder: (_) => AiAudioSettingsDialog(service: _service),
    );
  }

  Future<void> _generateAllAudio() async {
    final out = _service.lastOutput;
    if (out == null) return;

    // Ask user for output directory.
    final dir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose folder for generated audio',
    );
    if (dir == null || dir.isEmpty) return;

    // Add a project subfolder named after the theme so multiple compositions
    // don't collide.
    final themeFolder = out.assetMap.theme.replaceAll(RegExp(r'[^a-z0-9_]'), '_');
    final projectDir = Directory('$dir${Platform.pathSeparator}$themeFolder');
    if (!await projectDir.exists()) {
      await projectDir.create(recursive: true);
    }

    final ok = await _service.startAudioBatch(
      outDir: projectDir.path,
      composerOutput: out,
    );
    if (!ok || !mounted) return;

    // Open progress dialog (it will close itself when batch completes).
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AiAudioProgressDialog(service: _service),
    );
  }

  Future<void> _runCompose() async {
    final desc = _descCtrl.text.trim();
    if (desc.isEmpty) return;
    final job = ComposerJob(
      description: desc,
      jurisdictions: _selectedJurisdictions.toList(),
      includeBrief: _includeBrief,
      includeVoiceDirection: _includeVo,
      includeQualityGrade: _includeGrade,
    );
    await _service.run(job);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF06060A),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          const SizedBox(height: 12),
          _buildInputSection(),
          const SizedBox(height: 12),
          Expanded(child: _buildOutputSection()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final sel = _service.selection;
    final healthy = _service.activeInfo?.healthy ?? false;
    final dotColor = healthy ? const Color(0xFF44DD66) : const Color(0xFF777777);
    final providerLabel = sel.provider.displayLabel;
    final modelText = switch (sel.provider) {
      AiProviderId.ollama => sel.ollama.model,
      AiProviderId.anthropic => sel.anthropic.model,
      AiProviderId.azureOpenai => sel.azure.deployment.isEmpty
          ? '(deployment not configured)'
          : sel.azure.deployment,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI COMPOSER · $providerLabel',
                  style: FluxForgeTheme.dockSans(
                    color: Colors.white,
                    size: 13,
                    weight: FontWeight.w600,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  modelText,
                  style: FluxForgeTheme.dockSans(color: Colors.white60, size: 11),
                ),
              ],
            ),
          ),
          TextButton.icon(
            icon: const Icon(Icons.health_and_safety, size: 16),
            label: Text(_service.isBusy ? '…' : 'Health Check'),
            onPressed: _service.isBusy ? null : _service.refreshActiveInfo,
            style: TextButton.styleFrom(foregroundColor: Colors.white70),
          ),
          const SizedBox(width: 4),
          TextButton.icon(
            icon: const Icon(Icons.settings, size: 16),
            label: const Text('Provider'),
            onPressed: _openSettings,
            style: TextButton.styleFrom(foregroundColor: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _buildInputSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _descCtrl,
            maxLines: 4,
            style: FluxForgeTheme.dockSans(color: Colors.white, size: 13),
            decoration: InputDecoration(
              hintText:
                  'Describe the slot. e.g. "Egyptian temple, 96% RTP, medium volatility, brass-driven, 2x bonus rounds"',
              hintStyle: FluxForgeTheme.dockSans(color: Colors.white38, size: 12),
              border: OutlineInputBorder(),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF44DD66)),
              ),
              contentPadding: EdgeInsets.all(10),
            ),
          ),
          const SizedBox(height: 10),
          // Jurisdictions
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _allJurisdictions.map((j) {
              final selected = _selectedJurisdictions.contains(j);
              return FilterChip(
                label: Text(j, style: FluxForgeTheme.dockSans(size: 11)),
                selected: selected,
                onSelected: (v) {
                  setState(() {
                    if (v) {
                      _selectedJurisdictions.add(j);
                    } else {
                      _selectedJurisdictions.remove(j);
                    }
                  });
                },
                selectedColor: const Color(0xFF44DD66).withValues(alpha: 0.25),
                backgroundColor: const Color(0xFF1A1A28),
                labelStyle: FluxForgeTheme.dockSans(
                  color: selected ? const Color(0xFF44DD66) : Colors.white60,
                ),
                visualDensity: VisualDensity.compact,
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          // Toggles
          Row(
            children: [
              _toggle('Audio Brief', _includeBrief,
                  (v) => setState(() => _includeBrief = v)),
              const SizedBox(width: 12),
              _toggle('Voice Direction', _includeVo,
                  (v) => setState(() => _includeVo = v)),
              const SizedBox(width: 12),
              _toggle('Quality Grade', _includeGrade,
                  (v) => setState(() => _includeGrade = v)),
              const Spacer(),
              ElevatedButton.icon(
                icon: _service.isBusy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.auto_awesome, size: 16),
                label: Text(_service.isBusy ? 'COMPOSING…' : 'COMPOSE'),
                onPressed: _service.isBusy ||
                        _descCtrl.text.trim().isEmpty ||
                        _selectedJurisdictions.isEmpty
                    ? null
                    : _runCompose,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF44DD66),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: const Color(0xFF44DD66),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        const SizedBox(width: 4),
        Text(label, style: FluxForgeTheme.dockSans(color: Colors.white70, size: 11)),
      ],
    );
  }

  Widget _buildOutputSection() {
    if (_service.lastError != null && _service.lastError!.isNotEmpty &&
        _service.lastOutput == null) {
      return _errorBox(_service.lastError!);
    }
    final out = _service.lastOutput;
    if (out == null) {
      return Center(
        child: Text(
          _service.isBusy
              ? 'Calling provider… (multi-pass pipeline)'
              : 'Type a description above and press COMPOSE.',
          style: FluxForgeTheme.dockSans(color: Colors.white38, size: 12),
        ),
      );
    }
    return _resultView(out);
  }

  Widget _errorBox(String msg) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF2A1010),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFF4444), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFFF4444), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              msg,
              style: FluxForgeTheme.dockSans(color: const Color(0xFFFF8888), size: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultView(ComposerOutput out) {
    final map = out.assetMap;
    return DefaultTabController(
      length: 4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _resultStats(out),
          const SizedBox(height: 8),
          TabBar(
            isScrollable: true,
            indicatorColor: const Color(0xFF44DD66),
            labelColor: const Color(0xFF44DD66),
            unselectedLabelColor: Colors.white60,
            labelStyle: FluxForgeTheme.dockSans(size: 11, weight: FontWeight.w600),
            tabs: const [
              Tab(text: 'STAGE MAP'),
              Tab(text: 'BRIEF'),
              Tab(text: 'VOICE DIR'),
              Tab(text: 'COMPLIANCE'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _stageMapView(map),
                _markdownView(out.audioBriefMarkdown ?? '_(brief disabled)_'),
                _markdownView(
                    out.voiceDirectionMarkdown ?? '_(no VO assets in map)_'),
                _complianceView(map),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultStats(ComposerOutput out) {
    return Row(
      children: [
        _statChip('Job', out.jobId.substring(0, 8)),
        _statChip('Quality', '${out.assetMap.selfQualityScore}/100'),
        _statChip('Repairs', '${out.repairAttempts}'),
        _statChip('Tokens',
            '${out.totalTokensInput + out.totalTokensOutput}'),
        _statChip('Time',
            '${(out.totalElapsedMs / 1000).toStringAsFixed(1)}s'),
        const Spacer(),
        TextButton.icon(
          icon: const Icon(Icons.tune, size: 14),
          label: Text('Audio Settings', style: FluxForgeTheme.dockSans(size: 11)),
          onPressed: _openAudioSettings,
          style: TextButton.styleFrom(foregroundColor: Colors.white60),
        ),
        const SizedBox(width: 6),
        ElevatedButton.icon(
          icon: const Icon(Icons.audiotrack, size: 14),
          label: Text('GENERATE ALL AUDIO',
              style: FluxForgeTheme.dockSans(size: 11, weight: FontWeight.w700)),
          onPressed: _service.audioProgress.active ? null : _generateAllAudio,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFFAA33),
            foregroundColor: Colors.black,
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          ),
        ),
      ],
    );
  }

  Widget _statChip(String label, String value) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A28),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ',
              style: FluxForgeTheme.dockSans(color: Colors.white38, size: 10)),
          Text(value,
              style: FluxForgeTheme.dockMono(
                color: const Color(0xFF44DD66),
                size: 10,
                weight: FontWeight.w600,
              )),
        ],
      ),
    );
  }

  Widget _stageMapView(StageAssetMap map) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: map.stages.length,
      itemBuilder: (_, i) {
        final stage = map.stages[i];
        return ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 8),
          title: Text(stage.stageId,
              style: FluxForgeTheme.dockSans(
                color: const Color(0xFF44DD66),
                weight: FontWeight.w600,
                size: 12,
              )),
          subtitle: Text('${stage.assets.length} asset(s)',
              style: FluxForgeTheme.dockSans(color: Colors.white54, size: 10)),
          collapsedIconColor: Colors.white54,
          iconColor: Colors.white,
          children: stage.assets.map((a) {
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF15151E),
                borderRadius: BorderRadius.circular(4),
                border: Border(
                    left: BorderSide(
                        color: _busColor(a.bus), width: 3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('${a.kind.toUpperCase()} · ${a.bus}',
                          style: FluxForgeTheme.dockSans(
                            color: _busColor(a.bus),
                            size: 10,
                            weight: FontWeight.w700,
                          )),
                      const SizedBox(width: 8),
                      Text('${a.dynamicLevel}%',
                          style: FluxForgeTheme.dockMono(
                              color: Colors.white60, size: 10)),
                      if (a.lengthMs != null) ...[
                        const SizedBox(width: 8),
                        Text('${a.lengthMs}ms',
                            style: FluxForgeTheme.dockMono(
                                color: Colors.white60, size: 10)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(a.suggestedName,
                      style: FluxForgeTheme.dockSans(
                          color: Colors.white, size: 12)),
                  const SizedBox(height: 2),
                  Text('mood: ${a.mood}',
                      style: FluxForgeTheme.dockSans(
                          color: Colors.white60, size: 11)),
                  const SizedBox(height: 4),
                  Text(a.generationPrompt,
                      style: FluxForgeTheme.dockSans(
                          color: Colors.white70, size: 11)),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Color _busColor(String bus) => switch (bus) {
        'music' => const Color(0xFF66AAFF),
        'sfx' => const Color(0xFFFFAA33),
        'voice' => const Color(0xFFFF77AA),
        'ambience' => const Color(0xFF99CC66),
        'aux' => const Color(0xFFCC99FF),
        _ => Colors.white60,
      };

  Widget _markdownView(String md) {
    // Simple monospace presentation — full markdown rendering would need a
    // package import; the brief is plain text and reads fine as-is.
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: SelectableText(
        md,
        style: FluxForgeTheme.dockMono(
            color: Colors.white,
            size: 11).copyWith(height: 1.5),
      ),
    );
  }

  Widget _complianceView(StageAssetMap map) {
    final h = map.complianceHints;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Target jurisdictions: ${h.targetJurisdictions.join(", ")}',
              style: FluxForgeTheme.dockSans(color: Colors.white, size: 12)),
          const SizedBox(height: 12),
          _complianceRow('LDW audio suppressed', h.ldwAudioSuppressed),
          _complianceRow('Proportional celebrations', h.proportionalCelebrations),
          _complianceRow('Near-miss neutralised', h.nearMissNeutralized),
          const SizedBox(height: 16),
          if (h.reviewerNotes.isNotEmpty) ...[
            Text('Reviewer notes',
                style: FluxForgeTheme.dockSans(
                    color: Colors.white60,
                    size: 11,
                    weight: FontWeight.w600)),
            const SizedBox(height: 4),
            SelectableText(h.reviewerNotes,
                style: FluxForgeTheme.dockSans(color: Colors.white, size: 12)),
            const SizedBox(height: 16),
          ],
          if (map.selfCritique.isNotEmpty) ...[
            Text('AI self-critique',
                style: FluxForgeTheme.dockSans(
                    color: Colors.white60,
                    size: 11,
                    weight: FontWeight.w600)),
            const SizedBox(height: 4),
            SelectableText(map.selfCritique,
                style: FluxForgeTheme.dockSans(color: Colors.white70, size: 12)),
          ],
        ],
      ),
    );
  }

  Widget _complianceRow(String label, bool ok) {
    final color = ok ? const Color(0xFF44DD66) : const Color(0xFFFF4444);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(ok ? Icons.check_circle : Icons.cancel, color: color, size: 16),
          const SizedBox(width: 8),
          Text(label,
              style: FluxForgeTheme.dockSans(
                  color: color, size: 12, weight: FontWeight.w500)),
        ],
      ),
    );
  }
}
