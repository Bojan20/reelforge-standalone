/// Loop Editor Panel — Advanced Looping System UI
///
/// Wwise-grade loop editor with:
/// - Asset selector & region list
/// - Cue point display
/// - Region properties (mode, wrap, crossfade, iteration gain)
/// - Playback controls & instance monitor
/// - Marker import

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../models/loop_asset_models.dart';
import '../../providers/loop_provider.dart';
import '../../theme/fluxforge_theme.dart';

class LoopEditorPanel extends StatefulWidget {
  const LoopEditorPanel({super.key});

  @override
  State<LoopEditorPanel> createState() => _LoopEditorPanelState();
}

class _LoopEditorPanelState extends State<LoopEditorPanel> {
  late final LoopProvider _provider;
  String? _selectedAssetId;
  String? _selectedRegionName;

  @override
  void initState() {
    super.initState();
    _provider = GetIt.instance<LoopProvider>();
    _provider.addListener(_onProviderUpdate);

    // Auto-init if not initialized
    if (!_provider.isInitialized) {
      _provider.init();
    }
  }

  @override
  void dispose() {
    _provider.removeListener(_onProviderUpdate);
    super.dispose();
  }

  void _onProviderUpdate() {
    if (mounted) setState(() {});
  }

  LoopAsset? get _selectedAsset =>
      _selectedAssetId != null ? _provider.getAsset(_selectedAssetId!) : null;

  AdvancedLoopRegion? get _selectedRegion {
    final asset = _selectedAsset;
    if (asset == null || _selectedRegionName == null) return null;
    return asset.regionByName(_selectedRegionName!);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: FluxForgeTheme.bgDeep,
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: Row(
              children: [
                // Left: Asset list + Region list
                SizedBox(
                  width: 240,
                  child: _buildAssetPanel(),
                ),
                Container(width: 1, color: FluxForgeTheme.borderSubtle),
                // Center: Region properties
                Expanded(
                  flex: 2,
                  child: _buildRegionProperties(),
                ),
                Container(width: 1, color: FluxForgeTheme.borderSubtle),
                // Right: Instance monitor + playback controls
                SizedBox(
                  width: 280,
                  child: _buildInstancePanel(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HEADER
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildHeader() {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        border: Border(
          bottom: BorderSide(color: FluxForgeTheme.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.loop, size: 16, color: FluxForgeTheme.accentBlue),
          const SizedBox(width: 8),
          Text(
            'Loop Editor',
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 16),
          // Init status
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: _provider.isInitialized
                  ? Colors.green.withValues(alpha: 0.2)
                  : Colors.red.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              _provider.isInitialized ? 'ACTIVE' : 'OFFLINE',
              style: TextStyle(
                color: _provider.isInitialized ? Colors.green : Colors.red,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Spacer(),
          // Active instances count
          Text(
            '${_provider.activeInstances.length} instances',
            style: TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ASSET & REGION LIST (LEFT)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildAssetPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Asset section header
        _buildSectionHeader('ASSETS', Icons.audio_file),
        Expanded(
          flex: 1,
          child: _buildAssetList(),
        ),
        Container(height: 1, color: FluxForgeTheme.borderSubtle),
        // Region section header
        _buildSectionHeader('REGIONS', Icons.crop_free),
        Expanded(
          flex: 1,
          child: _buildRegionList(),
        ),
        Container(height: 1, color: FluxForgeTheme.borderSubtle),
        // Cue section
        _buildSectionHeader('CUES', Icons.flag),
        Expanded(
          flex: 1,
          child: _buildCueList(),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: FluxForgeTheme.bgSurface,
      child: Row(
        children: [
          Icon(icon, size: 14, color: FluxForgeTheme.textSecondary),
          const SizedBox(width: 6),
          Text(
            title,
            style: TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssetList() {
    final assets = _provider.assets;
    if (assets.isEmpty) {
      return Center(
        child: Text(
          'No loop assets',
          style: TextStyle(
            color: FluxForgeTheme.textTertiary,
            fontSize: 11,
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: assets.length,
      padding: EdgeInsets.zero,
      itemBuilder: (context, index) {
        final asset = assets.values.elementAt(index);
        final selected = asset.id == _selectedAssetId;
        return _buildListItem(
          asset.id,
          '${asset.regions.length} regions',
          selected,
          () => setState(() {
            _selectedAssetId = asset.id;
            _selectedRegionName = asset.regions.isNotEmpty
                ? asset.regions.first.name
                : null;
          }),
        );
      },
    );
  }

  Widget _buildRegionList() {
    final asset = _selectedAsset;
    if (asset == null) {
      return Center(
        child: Text(
          'Select an asset',
          style: TextStyle(
            color: FluxForgeTheme.textTertiary,
            fontSize: 11,
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: asset.regions.length,
      padding: EdgeInsets.zero,
      itemBuilder: (context, index) {
        final region = asset.regions[index];
        final selected = region.name == _selectedRegionName;
        final durMs = region.durationSeconds(asset.timeline.sampleRate) * 1000;
        return _buildListItem(
          region.name,
          '${durMs.toStringAsFixed(0)}ms  ${region.mode.name}',
          selected,
          () => setState(() => _selectedRegionName = region.name),
        );
      },
    );
  }

  Widget _buildCueList() {
    final asset = _selectedAsset;
    if (asset == null) {
      return Center(
        child: Text(
          'Select an asset',
          style: TextStyle(
            color: FluxForgeTheme.textTertiary,
            fontSize: 11,
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: asset.cues.length,
      padding: EdgeInsets.zero,
      itemBuilder: (context, index) {
        final cue = asset.cues[index];
        final timeSec = cue.atSeconds(asset.timeline.sampleRate);
        return _buildListItem(
          cue.name,
          '${timeSec.toStringAsFixed(3)}s  ${cue.cueType.name}',
          false,
          null,
          icon: _cueIcon(cue.cueType),
          iconColor: _cueColor(cue.cueType),
        );
      },
    );
  }

  Widget _buildListItem(
    String title,
    String subtitle,
    bool selected,
    VoidCallback? onTap, {
    IconData? icon,
    Color? iconColor,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        color: selected
            ? FluxForgeTheme.accentBlue.withValues(alpha: 0.15)
            : Colors.transparent,
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: iconColor ?? FluxForgeTheme.textSecondary),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: selected
                      ? FluxForgeTheme.accentBlue
                      : FluxForgeTheme.textPrimary,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              subtitle,
              style: TextStyle(
                color: FluxForgeTheme.textTertiary,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _cueIcon(CueType type) {
    switch (type) {
      case CueType.entry:
        return Icons.play_arrow;
      case CueType.exit:
        return Icons.stop;
      case CueType.event:
        return Icons.flash_on;
      case CueType.sync:
        return Icons.sync;
      case CueType.custom:
        return Icons.flag;
    }
  }

  Color _cueColor(CueType type) {
    switch (type) {
      case CueType.entry:
        return Colors.green;
      case CueType.exit:
        return Colors.red;
      case CueType.event:
        return Colors.amber;
      case CueType.sync:
        return Colors.cyan;
      case CueType.custom:
        return FluxForgeTheme.textSecondary;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // REGION PROPERTIES (CENTER)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildRegionProperties() {
    final region = _selectedRegion;
    final asset = _selectedAsset;

    if (region == null || asset == null) {
      return Center(
        child: Text(
          'Select a region to view properties',
          style: TextStyle(
            color: FluxForgeTheme.textTertiary,
            fontSize: 12,
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Region name & timeline info
          _buildPropertyGroup('Region: ${region.name}', [
            _buildPropertyRow('In',
                '${region.inSamples} samples (${(region.inSamples / asset.timeline.sampleRate).toStringAsFixed(3)}s)'),
            _buildPropertyRow('Out',
                '${region.outSamples} samples (${(region.outSamples / asset.timeline.sampleRate).toStringAsFixed(3)}s)'),
            _buildPropertyRow('Duration',
                '${region.durationSeconds(asset.timeline.sampleRate).toStringAsFixed(3)}s'),
          ]),
          const SizedBox(height: 12),

          // Loop mode & wrap policy
          _buildPropertyGroup('Behavior', [
            _buildPropertyRow('Mode', _loopModeName(region.mode)),
            _buildPropertyRow('Wrap Policy', _wrapPolicyName(region.wrapPolicy)),
            if (region.maxLoops != null)
              _buildPropertyRow('Max Loops', '${region.maxLoops}'),
          ]),
          const SizedBox(height: 12),

          // Crossfade settings
          _buildPropertyGroup('Crossfade', [
            _buildPropertyRow('Seam Fade', '${region.seamFadeMs.toStringAsFixed(1)}ms'),
            _buildPropertyRow('Crossfade', '${region.crossfadeMs.toStringAsFixed(1)}ms'),
            _buildPropertyRow('Curve', _curveName(region.crossfadeCurve)),
          ]),
          const SizedBox(height: 12),

          // Per-iteration gain
          _buildPropertyGroup('Per-Iteration Gain', [
            _buildPropertyRow(
              'Factor',
              region.iterationGainFactor != null
                  ? '${region.iterationGainFactor!.toStringAsFixed(3)} (${_gainFactorDescription(region.iterationGainFactor!)})'
                  : 'Disabled',
            ),
            if (region.iterationGainFactor != null) ...[
              _buildPropertyRow(
                'After 5 loops',
                '${(_gainAtIteration(region.iterationGainFactor!, 5) * 100).toStringAsFixed(1)}%',
              ),
              _buildPropertyRow(
                'After 10 loops',
                '${(_gainAtIteration(region.iterationGainFactor!, 10) * 100).toStringAsFixed(1)}%',
              ),
            ],
          ]),
          const SizedBox(height: 12),

          // Random start offset
          _buildPropertyGroup('Random Start', [
            _buildPropertyRow(
              'Range',
              region.randomStartRange > 0
                  ? '${region.randomStartRange} samples (${(region.randomStartRange / asset.timeline.sampleRate * 1000).toStringAsFixed(1)}ms)'
                  : 'Disabled',
            ),
          ]),
          const SizedBox(height: 12),

          // Timeline info
          _buildPropertyGroup('Asset: ${asset.id}', [
            _buildPropertyRow('Sample Rate', '${asset.timeline.sampleRate} Hz'),
            _buildPropertyRow('Channels', '${asset.timeline.channels}'),
            _buildPropertyRow('Length', '${asset.timeline.lengthSamples} samples'),
            _buildPropertyRow('Duration', '${asset.timeline.durationSeconds.toStringAsFixed(3)}s'),
            if (asset.timeline.bpm != null)
              _buildPropertyRow('BPM', '${asset.timeline.bpm}'),
          ]),
        ],
      ),
    );
  }

  Widget _buildPropertyGroup(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: FluxForgeTheme.accentBlue,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        ...children,
      ],
    );
  }

  Widget _buildPropertyRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                color: FluxForgeTheme.textSecondary,
                fontSize: 11,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: FluxForgeTheme.textPrimary,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _loopModeName(LoopMode mode) {
    switch (mode) {
      case LoopMode.hard:
        return 'Hard (zero-crossing)';
      case LoopMode.crossfade:
        return 'Crossfade (single voice)';
      case LoopMode.dualVoice:
        return 'Dual Voice (web-safe)';
    }
  }

  String _wrapPolicyName(WrapPolicy policy) {
    switch (policy) {
      case WrapPolicy.playOnceThenLoop:
        return 'Play Once Then Loop';
      case WrapPolicy.skipIntro:
        return 'Skip Intro';
      case WrapPolicy.includeInLoop:
        return 'Include In Loop';
      case WrapPolicy.introOnly:
        return 'Intro Only (no repeat)';
    }
  }

  String _curveName(LoopCrossfadeCurve curve) {
    switch (curve) {
      case LoopCrossfadeCurve.equalPower:
        return 'Equal Power';
      case LoopCrossfadeCurve.linear:
        return 'Linear';
      case LoopCrossfadeCurve.sCurve:
        return 'S-Curve';
      case LoopCrossfadeCurve.logarithmic:
        return 'Logarithmic';
      case LoopCrossfadeCurve.exponential:
        return 'Exponential';
      case LoopCrossfadeCurve.cosineHalf:
        return 'Cosine Half';
      case LoopCrossfadeCurve.squareRoot:
        return 'Square Root';
      case LoopCrossfadeCurve.sine:
        return 'Sine';
      case LoopCrossfadeCurve.fastAttack:
        return 'Fast Attack';
      case LoopCrossfadeCurve.slowAttack:
        return 'Slow Attack';
    }
  }

  String _gainFactorDescription(double factor) {
    if (factor < 1.0) return 'decay';
    if (factor > 1.0) return 'crescendo';
    return 'unity';
  }

  double _gainAtIteration(double factor, int iteration) {
    double gain = 1.0;
    for (int i = 0; i < iteration; i++) {
      gain *= factor;
    }
    return gain;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INSTANCE MONITOR & PLAYBACK (RIGHT)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildInstancePanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionHeader('PLAYBACK', Icons.play_circle),
        _buildPlaybackControls(),
        Container(height: 1, color: FluxForgeTheme.borderSubtle),
        _buildSectionHeader('ACTIVE INSTANCES', Icons.multitrack_audio),
        Expanded(child: _buildInstanceList()),
        Container(height: 1, color: FluxForgeTheme.borderSubtle),
        _buildSectionHeader('CALLBACKS', Icons.notifications),
        Expanded(child: _buildCallbackLog()),
      ],
    );
  }

  Widget _buildPlaybackControls() {
    final hasAsset = _selectedAsset != null;
    final hasRegion = _selectedRegion != null;

    return Container(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          // Play button
          Row(
            children: [
              Expanded(
                child: _buildActionButton(
                  'Play',
                  Icons.play_arrow,
                  hasAsset && hasRegion
                      ? () {
                          _provider.play(
                            assetId: _selectedAssetId!,
                            region: _selectedRegionName!,
                          );
                        }
                      : null,
                  Colors.green,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _buildActionButton(
                  'Stop All',
                  Icons.stop,
                  _provider.activeInstances.isNotEmpty
                      ? () => _provider.stopAll()
                      : null,
                  Colors.red,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(
    String label,
    IconData icon,
    VoidCallback? onPressed,
    Color color,
  ) {
    return SizedBox(
      height: 28,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 14),
        label: Text(label, style: const TextStyle(fontSize: 11)),
        style: ElevatedButton.styleFrom(
          backgroundColor: onPressed != null
              ? color.withValues(alpha: 0.2)
              : FluxForgeTheme.bgSurface,
          foregroundColor: onPressed != null ? color : FluxForgeTheme.textTertiary,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
      ),
    );
  }

  Widget _buildInstanceList() {
    final instances = _provider.instances.values.toList();
    if (instances.isEmpty) {
      return Center(
        child: Text(
          'No active instances',
          style: TextStyle(
            color: FluxForgeTheme.textTertiary,
            fontSize: 11,
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: instances.length,
      padding: EdgeInsets.zero,
      itemBuilder: (context, index) {
        final inst = instances[index];
        return Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: FluxForgeTheme.borderSubtle.withValues(alpha: 0.5),
              ),
            ),
          ),
          child: Row(
            children: [
              // State indicator
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _stateColor(inst.state),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              // Instance info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '#${inst.instanceId} — ${inst.assetId}',
                      style: TextStyle(
                        color: FluxForgeTheme.textPrimary,
                        fontSize: 10,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${inst.currentRegion}  loops:${inst.loopCount}  ${inst.state.name}',
                      style: TextStyle(
                        color: FluxForgeTheme.textTertiary,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
              // Stop button
              if (inst.state != LoopPlaybackState.stopped)
                InkWell(
                  onTap: () => _provider.stop(instanceId: inst.instanceId),
                  child: Icon(Icons.stop, size: 16, color: Colors.red.shade300),
                ),
            ],
          ),
        );
      },
    );
  }

  Color _stateColor(LoopPlaybackState state) {
    switch (state) {
      case LoopPlaybackState.intro:
        return Colors.amber;
      case LoopPlaybackState.looping:
        return Colors.green;
      case LoopPlaybackState.exiting:
        return Colors.orange;
      case LoopPlaybackState.stopped:
        return FluxForgeTheme.textTertiary;
    }
  }

  Widget _buildCallbackLog() {
    final callbacks = _provider.recentCallbacks;
    if (callbacks.isEmpty) {
      return Center(
        child: Text(
          'No callbacks',
          style: TextStyle(
            color: FluxForgeTheme.textTertiary,
            fontSize: 11,
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: callbacks.length,
      reverse: true,
      padding: EdgeInsets.zero,
      itemBuilder: (context, index) {
        final cb = callbacks[callbacks.length - 1 - index];
        return Container(
          height: 20,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            _callbackSummary(cb),
            style: TextStyle(
              color: cb.isError
                  ? Colors.red.shade300
                  : FluxForgeTheme.textTertiary,
              fontSize: 9,
              fontFamily: 'monospace',
            ),
            overflow: TextOverflow.ellipsis,
          ),
        );
      },
    );
  }

  String _callbackSummary(LoopCallback cb) {
    if (cb.isStarted) return 'STARTED #${cb.instanceId} ${cb.assetId}';
    if (cb.isStateChanged) return 'STATE #${cb.instanceId} → ${cb.state?.name}';
    if (cb.isWrap) return 'WRAP #${cb.instanceId} loop=${cb.loopCount}';
    if (cb.isRegionSwitched) {
      return 'REGION #${cb.instanceId} ${cb.fromRegion}→${cb.toRegion}';
    }
    if (cb.isCueHit) return 'CUE #${cb.instanceId} ${cb.cueName}';
    if (cb.isStopped) return 'STOPPED #${cb.instanceId}';
    if (cb.isVoiceStealWarning) return 'VOICE_STEAL #${cb.instanceId}';
    if (cb.isError) return 'ERROR: ${cb.message}';
    return cb.type;
  }
}
