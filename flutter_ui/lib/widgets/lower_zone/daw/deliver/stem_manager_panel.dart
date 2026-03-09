/// Stem Manager Panel — FabFilter-style DAW Lower Zone DELIVER tab
///
/// Save/recall solo/mute configurations for stem rendering.
/// Batch render all configurations with multi-format output.
///
/// Features:
/// - Named stem configs (save current solo/mute state as preset)
/// - Recall config → applies solo/mute to mixer
/// - Render queue visualization with progress
/// - Multi-format toggle (WAV+OGG simultaneous)
/// - Sample rate + normalization settings
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../providers/mixer_provider.dart';
import '../../../../services/stem_manager_service.dart';
import '../../../../services/export_service.dart';
import '../../../fabfilter/fabfilter_theme.dart';
import '../../../fabfilter/fabfilter_widgets.dart';

class StemManagerPanel extends StatefulWidget {
  final void Function(String action, Map<String, dynamic>? params)? onAction;

  const StemManagerPanel({
    super.key,
    this.onAction,
  });

  @override
  State<StemManagerPanel> createState() => _StemManagerPanelState();
}

class _StemManagerPanelState extends State<StemManagerPanel> {
  final _service = StemManagerService.instance;
  late TextEditingController _nameController;
  late FocusNode _nameFocus;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _nameFocus = FocusNode();
    _service.addListener(_onServiceChanged);
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceChanged);
    _nameController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  /// Get current track states from MixerProvider
  List<MixerChannel> _getMixerChannels() {
    final mixer = context.read<MixerProvider>();
    return mixer.channels;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: FabFilterColors.bgDeep),
      child: Column(
        children: [
          _buildHeader(),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HEADER
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildHeader() {
    final stats = _service.queueStats;
    final hasQueue = _service.renderQueue.isNotEmpty;

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: FabFilterColors.bgDeep,
        border: Border(
            bottom: BorderSide(
                color: FabFilterColors.cyan.withValues(alpha: 0.3))),
      ),
      child: Row(
        children: [
          Text('STEM MANAGER',
              style: FabFilterText.sectionHeader.copyWith(
                color: FabFilterColors.cyan,
                fontSize: 10,
                letterSpacing: 1.2,
              )),
          const SizedBox(width: 8),
          // Config count badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: FabFilterColors.bgMid,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: FabFilterColors.border),
            ),
            child: Text(
              '${_service.configs.length} configs',
              style: FabFilterText.paramValue(FabFilterColors.textSecondary)
                  .copyWith(fontSize: 8),
            ),
          ),
          if (hasQueue) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: _service.isRendering
                    ? FabFilterColors.orange.withValues(alpha: 0.2)
                    : FabFilterColors.bgMid,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: _service.isRendering
                      ? FabFilterColors.orange
                      : FabFilterColors.border,
                ),
              ),
              child: Text(
                _service.isRendering
                    ? 'RENDERING ${stats.complete}/${stats.total}'
                    : 'Queue: ${stats.total}',
                style: FabFilterText.paramValue(
                  _service.isRendering
                      ? FabFilterColors.orange
                      : FabFilterColors.textSecondary,
                ).copyWith(fontSize: 8),
              ),
            ),
          ],
          const Spacer(),
          GestureDetector(
            onTap: () => widget.onAction?.call('close', null),
            child: const Icon(Icons.close,
                size: 14, color: FabFilterColors.textTertiary),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CONTENT
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildContent() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left: Stem config list
          SizedBox(
            width: 200,
            child: _buildConfigList(),
          ),
          const SizedBox(width: 8),
          // Middle: Config detail / track states
          Expanded(child: _buildConfigDetail()),
          const SizedBox(width: 8),
          // Right: Render settings + queue
          SizedBox(
            width: 180,
            child: _buildRenderPanel(),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LEFT — STEM CONFIG LIST
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildConfigList() {
    return Container(
      decoration: FabFilterDecorations.display(),
      child: Column(
        children: [
          // Header with add button
          Container(
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: FabFilterColors.bgMid,
              border:
                  Border(bottom: BorderSide(color: FabFilterColors.border)),
            ),
            child: Row(
              children: [
                Text('CONFIGURATIONS',
                    style: FabFilterText.paramLabel
                        .copyWith(fontSize: 7, letterSpacing: 0.8)),
                const Spacer(),
                GestureDetector(
                  onTap: _saveCurrentState,
                  child: Icon(Icons.add,
                      size: 14, color: FabFilterColors.green),
                ),
              ],
            ),
          ),
          // Config list
          Expanded(
            child: _service.configs.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        'No stem configs.\nSet solo/mute on tracks,\nthen press + to save.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 9,
                          color: FabFilterColors.textDisabled,
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: _service.configs.length,
                    itemBuilder: (context, index) {
                      final config = _service.configs[index];
                      final isSelected =
                          index == _service.selectedConfigIndex;

                      return GestureDetector(
                        onTap: () => _service.selectConfig(index),
                        child: Container(
                          height: 32,
                          padding:
                              const EdgeInsets.symmetric(horizontal: 6),
                          color: isSelected
                              ? FabFilterColors.cyan
                                  .withValues(alpha: 0.12)
                              : null,
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  mainAxisAlignment:
                                      MainAxisAlignment.center,
                                  children: [
                                    Text(config.name,
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: isSelected
                                              ? FabFilterColors.cyan
                                              : FabFilterColors
                                                  .textPrimary,
                                        ),
                                        overflow: TextOverflow.ellipsis),
                                    Text(config.summary,
                                        style: TextStyle(
                                          fontSize: 7,
                                          color: FabFilterColors
                                              .textTertiary,
                                        )),
                                  ],
                                ),
                              ),
                              // Recall button
                              GestureDetector(
                                onTap: () => _recallConfig(index),
                                child: Padding(
                                  padding: const EdgeInsets.all(2),
                                  child: Icon(Icons.play_arrow,
                                      size: 12,
                                      color: FabFilterColors.green),
                                ),
                              ),
                              // Delete button
                              GestureDetector(
                                onTap: () => _service.removeConfig(index),
                                child: Padding(
                                  padding: const EdgeInsets.all(2),
                                  child: Icon(Icons.close,
                                      size: 10,
                                      color: FabFilterColors.textTertiary),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MIDDLE — CONFIG DETAIL (track solo/mute states)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildConfigDetail() {
    final config = _service.selectedConfig;

    if (config == null) {
      return Container(
        decoration: FabFilterDecorations.display(),
        child: Center(
          child: Text(
            'Select a configuration to view track states',
            style: TextStyle(
              fontSize: 9,
              color: FabFilterColors.textDisabled,
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: FabFilterDecorations.display(),
      child: Column(
        children: [
          // Header with config name
          Container(
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: FabFilterColors.bgMid,
              border: Border(
                  bottom: BorderSide(color: FabFilterColors.border)),
            ),
            child: Row(
              children: [
                Text(config.name.toUpperCase(),
                    style: FabFilterText.paramLabel.copyWith(
                      fontSize: 8,
                      letterSpacing: 0.8,
                      color: FabFilterColors.cyan,
                    )),
                const Spacer(),
                GestureDetector(
                  onTap: () => _service.duplicateConfig(
                      _service.selectedConfigIndex),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(Icons.copy,
                        size: 11, color: FabFilterColors.textTertiary),
                  ),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () => _updateSelectedConfig(),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(Icons.save,
                        size: 11, color: FabFilterColors.orange),
                  ),
                ),
              ],
            ),
          ),
          // Track states
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 2),
              itemCount: config.trackStates.length,
              itemBuilder: (context, index) {
                final entry =
                    config.trackStates.entries.elementAt(index);
                final state = entry.value;

                return Container(
                  height: 22,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(
                    children: [
                      // Solo indicator
                      Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: state.soloed
                              ? FabFilterColors.yellow
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(2),
                          border: Border.all(
                            color: state.soloed
                                ? FabFilterColors.yellow
                                : FabFilterColors.border,
                          ),
                        ),
                        child: Center(
                          child: Text('S',
                              style: TextStyle(
                                fontSize: 7,
                                fontWeight: FontWeight.bold,
                                color: state.soloed
                                    ? FabFilterColors.bgDeep
                                    : FabFilterColors.textTertiary,
                              )),
                        ),
                      ),
                      const SizedBox(width: 3),
                      // Mute indicator
                      Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: state.muted
                              ? FabFilterColors.red
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(2),
                          border: Border.all(
                            color: state.muted
                                ? FabFilterColors.red
                                : FabFilterColors.border,
                          ),
                        ),
                        child: Center(
                          child: Text('M',
                              style: TextStyle(
                                fontSize: 7,
                                fontWeight: FontWeight.bold,
                                color: state.muted
                                    ? FabFilterColors.bgDeep
                                    : FabFilterColors.textTertiary,
                              )),
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Track name
                      Expanded(
                        child: Text(state.trackName,
                            style: TextStyle(
                              fontSize: 9,
                              color: state.muted
                                  ? FabFilterColors.textDisabled
                                  : FabFilterColors.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RIGHT — RENDER SETTINGS + QUEUE
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildRenderPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Format toggles
        Text('OUTPUT FORMATS',
            style: FabFilterText.paramLabel
                .copyWith(fontSize: 7, letterSpacing: 0.8)),
        const SizedBox(height: 3),
        Wrap(
          spacing: 4,
          runSpacing: 3,
          children: ExportFormat.values.map((f) {
            final active = _service.outputFormats.contains(f);
            return FabCompactToggle(
              label: f.label,
              active: active,
              onToggle: () => _service.toggleOutputFormat(f),
              color: active ? FabFilterColors.cyan : FabFilterColors.textTertiary,
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        // Sample rate
        Text('SAMPLE RATE',
            style: FabFilterText.paramLabel
                .copyWith(fontSize: 7, letterSpacing: 0.8)),
        const SizedBox(height: 3),
        Wrap(
          spacing: 4,
          runSpacing: 3,
          children: [
            ExportSampleRate.rate44100,
            ExportSampleRate.rate48000,
            ExportSampleRate.rate96000,
          ].map((r) {
            final active = _service.sampleRate == r;
            return FabCompactToggle(
              label: r.label,
              active: active,
              onToggle: () => _service.setSampleRate(r),
              color: active ? FabFilterColors.cyan : FabFilterColors.textTertiary,
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        // Normalization
        Text('NORMALIZE',
            style: FabFilterText.paramLabel
                .copyWith(fontSize: 7, letterSpacing: 0.8)),
        const SizedBox(height: 3),
        Wrap(
          spacing: 4,
          children: NormalizationMode.values.map((m) {
            final active = _service.normalization == m;
            return FabCompactToggle(
              label: m.label,
              active: active,
              onToggle: () => _service.setNormalization(m),
              color: active ? FabFilterColors.cyan : FabFilterColors.textTertiary,
            );
          }).toList(),
        ),
        const SizedBox(height: 10),
        // Render queue preview
        if (_service.renderQueue.isNotEmpty) ...[
          Text('RENDER QUEUE',
              style: FabFilterText.paramLabel
                  .copyWith(fontSize: 7, letterSpacing: 0.8)),
          const SizedBox(height: 3),
          Expanded(
            child: Container(
              decoration: FabFilterDecorations.display(),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 2),
                itemCount: _service.renderQueue.length,
                itemBuilder: (context, index) {
                  final job = _service.renderQueue[index];
                  return _buildRenderJobRow(job);
                },
              ),
            ),
          ),
        ] else
          const Spacer(),
        const SizedBox(height: 6),
        // Action buttons
        _buildRenderActions(),
      ],
    );
  }

  Widget _buildRenderJobRow(RenderJob job) {
    final Color statusColor = switch (job.status) {
      RenderJobStatus.pending => FabFilterColors.textTertiary,
      RenderJobStatus.rendering => FabFilterColors.orange,
      RenderJobStatus.complete => FabFilterColors.green,
      RenderJobStatus.failed => FabFilterColors.red,
      RenderJobStatus.cancelled => FabFilterColors.textDisabled,
    };

    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          // Status icon
          Icon(
            switch (job.status) {
              RenderJobStatus.pending => Icons.schedule,
              RenderJobStatus.rendering => Icons.sync,
              RenderJobStatus.complete => Icons.check_circle,
              RenderJobStatus.failed => Icons.error,
              RenderJobStatus.cancelled => Icons.cancel,
            },
            size: 10,
            color: statusColor,
          ),
          const SizedBox(width: 4),
          // Job name
          Expanded(
            child: Text(job.displayName,
                style: TextStyle(fontSize: 8, color: statusColor),
                overflow: TextOverflow.ellipsis),
          ),
          // Progress/status
          Text(job.statusLabel,
              style: TextStyle(
                fontSize: 7,
                fontWeight: FontWeight.bold,
                color: statusColor,
              )),
        ],
      ),
    );
  }

  Widget _buildRenderActions() {
    return Row(
      children: [
        // Build queue
        Expanded(
          child: _buildActionButton(
            label: 'BUILD QUEUE',
            icon: Icons.queue,
            color: FabFilterColors.orange,
            onTap: _service.configs.isNotEmpty && !_service.isRendering
                ? () => _service.buildRenderQueue()
                : null,
          ),
        ),
        const SizedBox(width: 4),
        // Render all
        Expanded(
          child: _buildActionButton(
            label: _service.isRendering ? 'CANCEL' : 'RENDER ALL',
            icon: _service.isRendering ? Icons.stop : Icons.play_arrow,
            color: _service.isRendering
                ? FabFilterColors.red
                : FabFilterColors.green,
            filled: true,
            onTap: _service.isRendering
                ? () => _service.cancelBatchRender()
                : _service.renderQueue.isNotEmpty
                    ? _startBatchRender
                    : null,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required Color color,
    bool filled = false,
    VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    final effectiveColor = enabled ? color : FabFilterColors.textDisabled;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 26,
        decoration: BoxDecoration(
          color: filled && enabled
              ? color.withValues(alpha: 0.25)
              : FabFilterColors.bgSurface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: enabled
                ? (filled
                    ? color.withValues(alpha: 0.6)
                    : FabFilterColors.borderMedium)
                : FabFilterColors.border,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 11, color: effectiveColor),
            const SizedBox(width: 3),
            Text(label,
                style: FabFilterText.button.copyWith(
                  fontSize: 8,
                  color: effectiveColor,
                )),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTIONS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Save current mixer solo/mute state as a new stem config
  void _saveCurrentState() {
    final channels = _getMixerChannels();
    if (channels.isEmpty) return;

    final trackStates = <String, StemTrackState>{};
    for (final ch in channels) {
      trackStates[ch.id] = StemTrackState(
        trackId: ch.id,
        trackName: ch.name,
        muted: ch.muted,
        soloed: ch.soloed,
      );
    }

    // Generate default name based on soloed/muted tracks
    final soloedNames = channels
        .where((ch) => ch.soloed)
        .map((ch) => ch.name)
        .toList();
    final mutedNames = channels
        .where((ch) => ch.muted)
        .map((ch) => ch.name)
        .toList();

    String defaultName;
    if (soloedNames.isNotEmpty) {
      defaultName = soloedNames.length <= 2
          ? soloedNames.join(' + ')
          : '${soloedNames.length} Soloed';
    } else if (mutedNames.isNotEmpty) {
      defaultName = 'No ${mutedNames.length <= 2 ? mutedNames.join('/') : '${mutedNames.length} tracks'}';
    } else {
      defaultName = 'Stem ${_service.configs.length + 1}';
    }

    _service.addConfig(defaultName, trackStates);
  }

  /// Recall a stem config — apply its solo/mute to the mixer
  void _recallConfig(int index) {
    final config = _service.configs[index];
    _service.selectConfig(index);

    widget.onAction?.call('stemRecall', {
      'trackStates': config.trackStates.map(
        (k, v) => MapEntry(k, {'muted': v.muted, 'soloed': v.soloed}),
      ),
    });
  }

  /// Update selected config with current track states
  void _updateSelectedConfig() {
    if (_service.selectedConfigIndex < 0) return;
    final channels = _getMixerChannels();
    if (channels.isEmpty) return;

    final trackStates = <String, StemTrackState>{};
    for (final ch in channels) {
      trackStates[ch.id] = StemTrackState(
        trackId: ch.id,
        trackName: ch.name,
        muted: ch.muted,
        soloed: ch.soloed,
      );
    }

    _service.updateConfigTrackStates(
        _service.selectedConfigIndex, trackStates);
  }

  /// Start batch render
  void _startBatchRender() {
    widget.onAction?.call('stemBatchRender', {
      'queue': _service.renderQueue
          .map((j) => {
                'id': j.id,
                'configId': j.stemConfig.id,
                'format': j.format.code,
                'outputPath': j.outputPath,
              })
          .toList(),
    });
  }
}
