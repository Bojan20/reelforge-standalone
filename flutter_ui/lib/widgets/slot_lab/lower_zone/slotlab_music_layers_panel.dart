/// SlotLab Music Layers Panel — Dynamic win-driven music layer crossfade controller
///
/// Displays:
/// - Active layer indicator with visual bar
/// - Per-layer threshold config (winRatio boundaries)
/// - Revert spin count, crossfade duration, curve type
/// - Live event history during gameplay
/// - Enable/disable toggle
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';

import '../../../models/slot_lab_models.dart';
import '../../../services/audio_playback_service.dart';
import '../../../providers/slot_lab/slot_audio_provider.dart';
import '../../../providers/slot_lab/slot_lab_coordinator.dart';
import '../../../providers/slot_lab_project_provider.dart';

class SlotLabMusicLayersPanel extends StatefulWidget {
  const SlotLabMusicLayersPanel({super.key});

  @override
  State<SlotLabMusicLayersPanel> createState() => _SlotLabMusicLayersPanelState();
}

class _SlotLabMusicLayersPanelState extends State<SlotLabMusicLayersPanel> {
  late final SlotAudioProvider _audioProvider;
  late final SlotLabProjectProvider _projectProvider;
  final ValueNotifier<int> _revision = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    final sl = GetIt.instance;
    _audioProvider = sl<SlotLabCoordinator>().audioProvider;
    _projectProvider = sl<SlotLabProjectProvider>();
    _audioProvider.musicLayerController.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _audioProvider.musicLayerController.removeListener(_onControllerChanged);
    _revision.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    _revision.value++;
  }

  void _bumpRevision() {
    _revision.value++;
  }

  MusicLayerController get _controller => _audioProvider.musicLayerController;
  MusicLayerConfig get _config => _controller.config;

  void _updateConfig(MusicLayerConfig newConfig) {
    _audioProvider.updateMusicLayerConfig(newConfig);
    _projectProvider.setMusicLayerConfig(newConfig);
    _bumpRevision();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: _revision,
      builder: (context, _, _) => _buildContent(),
    );
  }

  Widget _buildContent() {
    final hasLayers = _config.thresholds.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ─── Header ────────────────────────────────────────
        _buildHeader(),
        const SizedBox(height: 8),

        // ─── Active Layer Indicator ────────────────────────
        if (hasLayers) ...[
          _buildActiveLayerBar(),
          const SizedBox(height: 8),
        ],

        // ─── Config Section ────────────────────────────────
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!hasLayers) _buildQuickSetup(),
                if (hasLayers) ...[
                  _buildAudioStatus(),
                  const SizedBox(height: 8),
                  _buildThresholdTable(),
                  const SizedBox(height: 12),
                  _buildGlobalSettings(),
                  const SizedBox(height: 12),
                  _buildHistory(),
                  const SizedBox(height: 12),
                  _buildLiveVolumeDebug(),
                  if (_controller.lastCrossfadeDiag.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A2E),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF333355)),
                      ),
                      child: SelectableText(
                        _controller.lastCrossfadeDiag,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 10,
                          color: Color(0xFF88AACC),
                        ),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HEADER
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.layers, size: 16, color: Color(0xFF40C8FF)),
          const SizedBox(width: 6),
          const Text(
            'DYNAMIC MUSIC LAYERS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFFE0E0E0),
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          if (_config.thresholds.isNotEmpty) ...[
            // Enable/Disable toggle
            SizedBox(
              height: 20,
              child: Switch(
                value: _config.enabled,
                onChanged: (v) => _updateConfig(_config.copyWith(enabled: v)),
                activeColor: const Color(0xFF40C8FF),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 8),
          ],
          // Preset buttons
          _buildPresetButton('3L', MusicLayerConfig.defaultThreeLayers),
          const SizedBox(width: 4),
          _buildPresetButton('5L', MusicLayerConfig.defaultFiveLayers),
          if (_config.thresholds.isNotEmpty) ...[
            const SizedBox(width: 4),
            _buildIconButton(Icons.delete_outline, 'Clear', () {
              _updateConfig(const MusicLayerConfig());
              _controller.reset();
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildPresetButton(String label, MusicLayerConfig Function() factory) {
    return Tooltip(
      message: '$label preset',
      child: InkWell(
        onTap: () => _updateConfig(factory()),
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF555555)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            style: const TextStyle(fontSize: 10, color: Color(0xFFAAAAAA)),
          ),
        ),
      ),
    );
  }

  Widget _buildIconButton(IconData icon, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(icon, size: 14, color: const Color(0xFF888888)),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTIVE LAYER BAR
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildActiveLayerBar() {
    final thresholds = _config.thresholds;
    final activeLayer = _controller.activeLayer;
    final isEscalated = _controller.isEscalated;
    final spinsLeft = isEscalated
        ? _config.revertSpinCount - _controller.spinsSinceEscalation
        : 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: _config.enabled ? const Color(0xFF40C8FF).withValues(alpha: 0.3) : const Color(0xFF333333),
          ),
        ),
        child: Column(
          children: [
            // Layer boxes row
            Row(
              children: [
                for (int i = 0; i < thresholds.length; i++) ...[
                  if (i > 0) const SizedBox(width: 4),
                  Expanded(child: _buildLayerBox(thresholds[i], activeLayer)),
                ],
              ],
            ),
            // Status line
            if (isEscalated && _config.enabled) ...[
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.timer_outlined, size: 12,
                    color: spinsLeft <= 2 ? const Color(0xFFFF6B6B) : const Color(0xFFFFAA33)),
                  const SizedBox(width: 4),
                  Text(
                    'Revert za $spinsLeft spin${spinsLeft == 1 ? '' : 'ova'}',
                    style: TextStyle(
                      fontSize: 10,
                      color: spinsLeft <= 2 ? const Color(0xFFFF6B6B) : const Color(0xFFFFAA33),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLayerBox(MusicLayerThreshold threshold, int activeLayer) {
    final isActive = threshold.layer == activeLayer;
    final color = _layerColor(threshold.layer);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
      decoration: BoxDecoration(
        color: isActive ? color.withValues(alpha: 0.25) : const Color(0xFF0D0D1A),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isActive ? color : const Color(0xFF333333),
          width: isActive ? 1.5 : 0.5,
        ),
      ),
      child: Column(
        children: [
          Text(
            'L${threshold.layer}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
              color: isActive ? color : const Color(0xFF666666),
            ),
          ),
          if (threshold.label.isNotEmpty)
            Text(
              threshold.label,
              style: TextStyle(
                fontSize: 9,
                color: isActive ? color.withValues(alpha: 0.8) : const Color(0xFF555555),
              ),
            ),
          Text(
            threshold.minWinRatio == 0 ? 'base' : '${threshold.minWinRatio}x',
            style: TextStyle(
              fontSize: 9,
              color: isActive ? const Color(0xFFAAAAAA) : const Color(0xFF444444),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // AUDIO STATUS — shows which layers have audio assigned
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildAudioStatus() {
    final thresholds = _config.thresholds;
    final missing = <int>[];

    for (final t in thresholds) {
      final path = _projectProvider.audioAssignments['MUSIC_BASE_L${t.layer}'];
      if (path == null || path.isEmpty) {
        missing.add(t.layer);
      }
    }

    if (missing.isEmpty) {
      return const SizedBox.shrink(); // All assigned — no warning needed
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF2A1A00),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFFFF9800).withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, size: 14, color: Color(0xFFFF9800)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Missing audio: ${missing.map((l) => 'MUSIC_BASE_L$l').join(', ')}. '
                'Assign in ASSIGN tab to enable crossfade.',
                style: const TextStyle(fontSize: 9, color: Color(0xFFFFCC80)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _layerColor(int layer) {
    return switch (layer) {
      1 => const Color(0xFF4CAF50),
      2 => const Color(0xFFFFAA33),
      3 => const Color(0xFFFF6B6B),
      4 => const Color(0xFFE040FB),
      5 => const Color(0xFFFF1744),
      _ => const Color(0xFF40C8FF),
    };
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // QUICK SETUP (no config yet)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildQuickSetup() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF333333)),
      ),
      child: Column(
        children: [
          const Icon(Icons.music_note, size: 32, color: Color(0xFF40C8FF)),
          const SizedBox(height: 8),
          const Text(
            'Dynamic Music Layers',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFFE0E0E0)),
          ),
          const SizedBox(height: 4),
          const Text(
            'Assign MUSIC_BASE_L1-L5 in Ultimate Audio Panel,\nthen pick a preset to auto-crossfade on wins.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10, color: Color(0xFF888888)),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: () => _updateConfig(MusicLayerConfig.defaultThreeLayers()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF40C8FF),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                ),
                child: const Text('3 Layers'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => _updateConfig(MusicLayerConfig.defaultFiveLayers()),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF40C8FF),
                  side: const BorderSide(color: Color(0xFF40C8FF)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                ),
                child: const Text('5 Layers'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // THRESHOLD TABLE
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildThresholdTable() {
    final thresholds = List<MusicLayerThreshold>.from(_config.thresholds);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'LAYER THRESHOLDS',
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF888888), letterSpacing: 1),
        ),
        const SizedBox(height: 4),
        // Header row
        const Row(
          children: [
            SizedBox(width: 40, child: Text('Layer', style: TextStyle(fontSize: 9, color: Color(0xFF666666)))),
            SizedBox(width: 70, child: Text('Label', style: TextStyle(fontSize: 9, color: Color(0xFF666666)))),
            Expanded(child: Text('Min Win Ratio', style: TextStyle(fontSize: 9, color: Color(0xFF666666)))),
          ],
        ),
        const Divider(height: 8, color: Color(0xFF333333)),
        for (int i = 0; i < thresholds.length; i++)
          _buildThresholdRow(i, thresholds[i]),
        const SizedBox(height: 8),
        // Add/Remove layer buttons
        Row(
          children: [
            if (thresholds.length < 5)
              _buildSmallButton(Icons.add, 'Add Layer', () {
                final next = thresholds.length + 1;
                final newThresholds = [
                  ...thresholds,
                  MusicLayerThreshold(
                    layer: next,
                    minWinRatio: thresholds.last.minWinRatio * 2,
                    label: 'L$next',
                  ),
                ];
                _updateConfig(_config.copyWith(thresholds: newThresholds));
              }),
            if (thresholds.length > 2) ...[
              const SizedBox(width: 8),
              _buildSmallButton(Icons.remove, 'Remove Last', () {
                final newThresholds = thresholds.sublist(0, thresholds.length - 1);
                _updateConfig(_config.copyWith(thresholds: newThresholds));
                if (_controller.activeLayer > newThresholds.length) {
                  _controller.reset();
                }
              }),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildThresholdRow(int index, MusicLayerThreshold threshold) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          // Layer number
          SizedBox(
            width: 40,
            child: Row(
              children: [
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    color: _layerColor(threshold.layer),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text('L${threshold.layer}',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Color(0xFFCCCCCC))),
              ],
            ),
          ),
          // Label
          SizedBox(
            width: 70,
            child: _InlineTextField(
              value: threshold.label,
              onChanged: (val) {
                final updated = List<MusicLayerThreshold>.from(_config.thresholds);
                updated[index] = MusicLayerThreshold(
                  layer: threshold.layer,
                  minWinRatio: threshold.minWinRatio,
                  label: val,
                );
                _updateConfig(_config.copyWith(thresholds: updated));
              },
            ),
          ),
          // Min Win Ratio
          Expanded(
            child: index == 0
                ? const Text('base (always)',
                    style: TextStyle(fontSize: 10, color: Color(0xFF666666), fontStyle: FontStyle.italic))
                : _InlineNumberField(
                    value: threshold.minWinRatio,
                    suffix: 'x bet',
                    onChanged: (val) {
                      final updated = List<MusicLayerThreshold>.from(_config.thresholds);
                      updated[index] = MusicLayerThreshold(
                        layer: threshold.layer,
                        minWinRatio: val,
                        label: threshold.label,
                      );
                      _updateConfig(_config.copyWith(thresholds: updated));
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSmallButton(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFF444444)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: const Color(0xFF888888)),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF888888))),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GLOBAL SETTINGS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildGlobalSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'SETTINGS',
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF888888), letterSpacing: 1),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            // Revert spin count
            _buildSettingField(
              'Revert after',
              '${_config.revertSpinCount}',
              'spins',
              onTap: () => _showSpinCountPicker(),
            ),
            const SizedBox(width: 16),
            // Crossfade duration
            _buildSettingField(
              'Crossfade',
              '${_config.crossfadeMs}',
              'ms',
              onTap: () => _showCrossfadePicker(),
            ),
            const SizedBox(width: 16),
            // Curve type
            _buildSettingField(
              'Curve',
              _config.crossfadeCurve,
              '',
              onTap: () => _cycleCurveType(),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSettingField(String label, String value, String suffix, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFF333333)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 9, color: Color(0xFF666666))),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFFCCCCCC))),
                if (suffix.isNotEmpty) ...[
                  const SizedBox(width: 2),
                  Text(suffix, style: const TextStyle(fontSize: 9, color: Color(0xFF666666))),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showSpinCountPicker() {
    final values = [3, 5, 7, 10, 15, 20];
    final current = _config.revertSpinCount;
    final nextIdx = (values.indexOf(current) + 1) % values.length;
    _updateConfig(_config.copyWith(revertSpinCount: values[nextIdx]));
  }

  void _showCrossfadePicker() {
    final values = [500, 1000, 1500, 2000, 3000, 5000];
    final current = _config.crossfadeMs;
    final idx = values.indexOf(current);
    final nextIdx = (idx + 1) % values.length;
    _updateConfig(_config.copyWith(crossfadeMs: values[nextIdx]));
  }

  void _cycleCurveType() {
    final curves = ['equalPower', 'linear', 'sCurve'];
    final idx = curves.indexOf(_config.crossfadeCurve);
    final nextIdx = (idx + 1) % curves.length;
    _updateConfig(_config.copyWith(crossfadeCurve: curves[nextIdx]));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HISTORY
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildLiveVolumeDebug() {
    final playback = AudioPlaybackService.instance;
    final voices = playback.activeVoices;
    final layerCount = _config.thresholds.length;

    return StatefulBuilder(
      builder: (context, setInnerState) {
        // Refresh every 200ms
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted) setInnerState(() {});
        });

        final lines = <String>[];
        for (int i = 1; i <= layerCount; i++) {
          final layerId = 'game_start_l$i';
          final matching = playback.activeVoices.where((v) => v.layerId == layerId).toList();
          final cacheVol = playback.layerVolumes[layerId]?.toStringAsFixed(2) ?? '?';
          if (matching.isNotEmpty) {
            for (final v in matching) {
              lines.add('L$i: v${v.voiceId} cache=$cacheVol');
            }
          } else {
            lines.add('L$i: — cache=$cacheVol');
          }
        }
        // Also show any standalone MUSIC_BASE voices still in engine
        final standaloneVoices = playback.activeVoices
            .where((v) => v.layerId != null && v.layerId!.contains('MUSIC_BASE'))
            .toList();
        for (final v in standaloneVoices) {
          lines.add('STANDALONE: ${v.layerId} v${v.voiceId}');
        }

        final activeLayer = _controller.activeLayer;
        final isEscalated = _controller.isEscalated;
        lines.insert(0, 'ACTIVE: L$activeLayer ${isEscalated ? "(escalated)" : ""} voices=${playback.activeVoices.length}');

        return Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF0D1117),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFF30363D)),
          ),
          child: Text(
            lines.join('\n'),
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: Color(0xFF58A6FF),
              height: 1.4,
            ),
          ),
        );
      },
    );
  }

  Widget _buildHistory() {
    final history = _controller.history;
    if (history.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF0D0D1A),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text(
          'No layer transitions yet. Start spinning!',
          style: TextStyle(fontSize: 10, color: Color(0xFF555555), fontStyle: FontStyle.italic),
        ),
      );
    }

    final recent = history.reversed.take(15).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'LAYER HISTORY',
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF888888), letterSpacing: 1),
        ),
        const SizedBox(height: 4),
        for (final event in recent)
          _buildHistoryRow(event),
      ],
    );
  }

  Widget _buildHistoryRow(MusicLayerEvent event) {
    final t = event.transition;
    final time = '${event.timestamp.hour.toString().padLeft(2, '0')}:${event.timestamp.minute.toString().padLeft(2, '0')}:${event.timestamp.second.toString().padLeft(2, '0')}';

    final (String icon, Color color, String text) = switch (t.reason) {
      MusicLayerTransitionReason.escalation => (
        '\u2191', const Color(0xFF4CAF50), 'L${t.fromLayer} \u2192 L${t.toLayer} (${t.winRatio.toStringAsFixed(1)}x)'),
      MusicLayerTransitionReason.revert => (
        '\u2193', const Color(0xFFFF6B6B), 'L${t.fromLayer} \u2192 L${t.toLayer} (revert)'),
      MusicLayerTransitionReason.sustained => (
        '\u2713', const Color(0xFF40C8FF), 'L${t.toLayer} sustained (${t.winRatio.toStringAsFixed(1)}x)'),
      MusicLayerTransitionReason.countdown => (
        '\u23F3', const Color(0xFFFFAA33), 'L${t.toLayer} countdown ${t.spinsRemaining ?? '?'}'),
      MusicLayerTransitionReason.idle => (
        '\u00B7', const Color(0xFF444444), 'L${t.toLayer} idle (${t.winRatio.toStringAsFixed(1)}x)'),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          Text(time, style: const TextStyle(fontSize: 9, color: Color(0xFF555555), fontFamily: 'monospace')),
          const SizedBox(width: 6),
          Text(icon, style: TextStyle(fontSize: 10, color: color)),
          const SizedBox(width: 4),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 10, color: color.withValues(alpha: 0.8))),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// INLINE EDIT WIDGETS
// ═══════════════════════════════════════════════════════════════════════════════

class _InlineTextField extends StatefulWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _InlineTextField({required this.value, required this.onChanged});

  @override
  State<_InlineTextField> createState() => _InlineTextFieldState();
}

class _InlineTextFieldState extends State<_InlineTextField> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_InlineTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && _controller.text != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 22,
      child: TextField(
        controller: _controller,
        style: const TextStyle(fontSize: 10, color: Color(0xFFCCCCCC)),
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          border: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF333333))),
          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF333333))),
          focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF40C8FF))),
        ),
        onSubmitted: widget.onChanged,
        onTapOutside: (_) => widget.onChanged(_controller.text),
      ),
    );
  }
}

class _InlineNumberField extends StatefulWidget {
  final double value;
  final String suffix;
  final ValueChanged<double> onChanged;

  const _InlineNumberField({required this.value, required this.suffix, required this.onChanged});

  @override
  State<_InlineNumberField> createState() => _InlineNumberFieldState();
}

class _InlineNumberFieldState extends State<_InlineNumberField> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value.toString());
  }

  @override
  void didUpdateWidget(_InlineNumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _controller.text = widget.value.toString();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final val = double.tryParse(_controller.text);
    if (val != null && val >= 0) {
      widget.onChanged(val);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 50,
          height: 22,
          child: TextField(
            controller: _controller,
            style: const TextStyle(fontSize: 10, color: Color(0xFFCCCCCC)),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              border: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF333333))),
              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF333333))),
              focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF40C8FF))),
            ),
            onSubmitted: (_) => _submit(),
            onTapOutside: (_) => _submit(),
          ),
        ),
        const SizedBox(width: 4),
        Text(widget.suffix, style: const TextStyle(fontSize: 9, color: Color(0xFF666666))),
      ],
    );
  }
}
