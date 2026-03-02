/// Loop Editor Panel — Wwise-grade Advanced Looping System UI
///
/// Full visual loop editor with:
/// - Waveform display with draggable loop in/out markers
/// - Crossfade curve visualization at loop boundary
/// - Per-iteration gain decay/crescendo controls
/// - Region properties, sync modes, wrap policies
/// - Playback controls & instance monitor with callbacks
///
/// Connected to selectedTrackId from Lower Zone for track context.

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../models/loop_asset_models.dart';
import '../../models/timeline_models.dart';
import '../../providers/loop_provider.dart';
import '../../theme/fluxforge_theme.dart';

class LoopEditorPanel extends StatefulWidget {
  final int? selectedTrackId;
  final List<TimelineClip> clips;
  final void Function(String action, Map<String, dynamic>? params)? onAction;

  const LoopEditorPanel({
    super.key,
    this.selectedTrackId,
    this.clips = const [],
    this.onAction,
  });

  @override
  State<LoopEditorPanel> createState() => _LoopEditorPanelState();
}

class _LoopEditorPanelState extends State<LoopEditorPanel> {
  late final LoopProvider _provider;
  String? _selectedClipId;
  String? _selectedAssetId;
  String? _selectedRegionName;

  @override
  void initState() {
    super.initState();
    _provider = GetIt.instance<LoopProvider>();
    _provider.addListener(_onProviderUpdate);
    if (!_provider.isInitialized) _provider.init();
  }

  @override
  void dispose() {
    _provider.removeListener(_onProviderUpdate);
    super.dispose();
  }

  @override
  void didUpdateWidget(LoopEditorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedTrackId != widget.selectedTrackId) {
      setState(() {
        _selectedClipId = null;
      });
    }
  }

  void _onProviderUpdate() {
    if (mounted) setState(() {});
  }

  List<TimelineClip> get _trackClips {
    if (widget.selectedTrackId == null) return [];
    final tid = widget.selectedTrackId.toString();
    return widget.clips.where((c) => c.trackId == tid).toList();
  }

  TimelineClip? get _selectedClip {
    if (_selectedClipId == null) return null;
    try {
      return _trackClips.firstWhere((c) => c.id == _selectedClipId);
    } catch (_) {
      return null;
    }
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
                SizedBox(width: 220, child: _buildLeftPanel()),
                Container(width: 1, color: FluxForgeTheme.borderSubtle),
                Expanded(flex: 3, child: _buildCenterPanel()),
                Container(width: 1, color: FluxForgeTheme.borderSubtle),
                SizedBox(width: 260, child: _buildRightPanel()),
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
        border: Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle)),
      ),
      child: Row(
        children: [
          Icon(Icons.loop, size: 16, color: FluxForgeTheme.accentBlue),
          const SizedBox(width: 8),
          Text('Loop Editor',
              style: TextStyle(
                  color: FluxForgeTheme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          const SizedBox(width: 12),
          if (widget.selectedTrackId != null) ...[
            _badge('Track ${widget.selectedTrackId}',
                FluxForgeTheme.accentBlue),
            const SizedBox(width: 8),
            Text('${_trackClips.length} clips',
                style: TextStyle(
                    color: FluxForgeTheme.textSecondary, fontSize: 11)),
          ] else
            Text('Select a track',
                style: TextStyle(
                    color: FluxForgeTheme.textTertiary, fontSize: 11)),
          const Spacer(),
          _badge(
            _provider.isInitialized ? 'ENGINE ACTIVE' : 'ENGINE OFFLINE',
            _provider.isInitialized ? Colors.green : Colors.red,
          ),
        ],
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(text,
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LEFT PANEL: Clip List + LoopAsset List
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildLeftPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader('TRACK CLIPS', Icons.audiotrack),
        Expanded(flex: 3, child: _buildClipList()),
        Container(height: 1, color: FluxForgeTheme.borderSubtle),
        _sectionHeader('LOOP ASSETS', Icons.audio_file),
        Expanded(flex: 2, child: _buildAssetList()),
      ],
    );
  }

  Widget _buildClipList() {
    if (widget.selectedTrackId == null) {
      return _placeholder(Icons.touch_app, 'Select a track');
    }
    final clips = _trackClips;
    if (clips.isEmpty) {
      return _placeholder(Icons.audiotrack, 'No clips on track');
    }
    return ListView.builder(
      itemCount: clips.length,
      padding: EdgeInsets.zero,
      itemBuilder: (_, i) {
        final clip = clips[i];
        final sel = clip.id == _selectedClipId;
        return InkWell(
          onTap: () => setState(() {
            _selectedClipId = clip.id;
            _selectedAssetId = null;
          }),
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            color: sel
                ? FluxForgeTheme.accentBlue.withValues(alpha: 0.15)
                : Colors.transparent,
            child: Row(
              children: [
                Icon(
                  clip.loopEnabled ? Icons.loop : Icons.trending_flat,
                  size: 14,
                  color: clip.loopEnabled
                      ? Colors.green
                      : FluxForgeTheme.textTertiary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(clip.name,
                      style: TextStyle(
                          color: sel
                              ? FluxForgeTheme.accentBlue
                              : FluxForgeTheme.textPrimary,
                          fontSize: 11,
                          fontWeight:
                              sel ? FontWeight.w600 : FontWeight.w400),
                      overflow: TextOverflow.ellipsis),
                ),
                Text(
                  '${clip.duration.toStringAsFixed(1)}s',
                  style: TextStyle(
                      color: FluxForgeTheme.textTertiary, fontSize: 9),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAssetList() {
    final assets = _provider.assets;
    if (assets.isEmpty) {
      return _placeholder(Icons.audio_file, 'No loop assets');
    }
    return ListView.builder(
      itemCount: assets.length,
      padding: EdgeInsets.zero,
      itemBuilder: (_, i) {
        final asset = assets.values.elementAt(i);
        final sel = asset.id == _selectedAssetId;
        return InkWell(
          onTap: () => setState(() {
            _selectedAssetId = asset.id;
            _selectedClipId = null;
            _selectedRegionName =
                asset.regions.isNotEmpty ? asset.regions.first.name : null;
          }),
          child: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            color: sel
                ? FluxForgeTheme.accentBlue.withValues(alpha: 0.15)
                : Colors.transparent,
            child: Row(
              children: [
                Expanded(
                  child: Text(asset.id,
                      style: TextStyle(
                          color: sel
                              ? FluxForgeTheme.accentBlue
                              : FluxForgeTheme.textPrimary,
                          fontSize: 11),
                      overflow: TextOverflow.ellipsis),
                ),
                Text('${asset.regions.length}R',
                    style: TextStyle(
                        color: FluxForgeTheme.textTertiary, fontSize: 9)),
              ],
            ),
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CENTER PANEL: Waveform + Loop Editor
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildCenterPanel() {
    final clip = _selectedClip;
    if (clip != null) return _buildClipLoopEditor(clip);

    final asset = _selectedAsset;
    final region = _selectedRegion;
    if (asset != null && region != null) {
      return _buildAdvancedRegionEditor(asset, region);
    }

    return _placeholder(Icons.loop, 'Select a clip or loop asset');
  }

  Widget _buildClipLoopEditor(TimelineClip clip) {
    return Column(
      children: [
        // Waveform with loop region markers
        Expanded(
          flex: 3,
          child: _WaveformLoopRegionEditor(
            waveform: clip.waveform,
            waveformRight: clip.waveformRight,
            channels: clip.channels,
            durationSec: clip.sourceDuration ?? clip.duration,
            loopEnabled: clip.loopEnabled,
            loopStartSamples: clip.loopStartSamples,
            loopEndSamples: clip.loopEndSamples,
            loopCrossfadeSec: clip.loopCrossfade,
            sampleRate: 44100, // Standard
            onLoopToggle: (v) => _updateClipLoop(clip, loopEnabled: v),
            onLoopStartChanged: (samples) =>
                _updateClipLoop(clip, loopStartSamples: samples),
            onLoopEndChanged: (samples) =>
                _updateClipLoop(clip, loopEndSamples: samples),
            onCrossfadeChanged: (sec) =>
                _updateClipLoop(clip, loopCrossfade: sec),
          ),
        ),
        Container(height: 1, color: FluxForgeTheme.borderSubtle),
        // Controls strip
        Expanded(
          flex: 2,
          child: _buildClipControlsStrip(clip),
        ),
      ],
    );
  }

  Widget _buildClipControlsStrip(TimelineClip clip) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Loop toggle + count + crossfade
          Row(
            children: [
              // Loop toggle
              _controlLabel('Loop'),
              Switch(
                value: clip.loopEnabled,
                onChanged: (v) => _updateClipLoop(clip, loopEnabled: v),
                activeColor: FluxForgeTheme.accentBlue,
              ),
              const SizedBox(width: 16),
              // Iterations
              _controlLabel('Iterations'),
              Text(
                clip.loopCount == 0 ? '∞' : '${clip.loopCount}',
                style: TextStyle(
                    color: FluxForgeTheme.textPrimary,
                    fontSize: 12,
                    fontFamily: 'monospace'),
              ),
              SizedBox(
                width: 120,
                child: Slider(
                  value: clip.loopCount.toDouble(),
                  min: 0,
                  max: 64,
                  divisions: 64,
                  activeColor: FluxForgeTheme.accentBlue,
                  inactiveColor: FluxForgeTheme.bgSurface,
                  onChangeEnd: (v) =>
                      _updateClipLoop(clip, loopCount: v.round()),
                  onChanged: (_) {},
                ),
              ),
              const SizedBox(width: 16),
              // Crossfade
              _controlLabel('Xfade'),
              Text(
                '${(clip.loopCrossfade * 1000).toStringAsFixed(0)}ms',
                style: TextStyle(
                    color: FluxForgeTheme.textPrimary,
                    fontSize: 12,
                    fontFamily: 'monospace'),
              ),
              SizedBox(
                width: 100,
                child: Slider(
                  value: clip.loopCrossfade,
                  min: 0,
                  max: 0.5,
                  activeColor: Colors.orange,
                  inactiveColor: FluxForgeTheme.bgSurface,
                  onChangeEnd: (v) =>
                      _updateClipLoop(clip, loopCrossfade: v),
                  onChanged: (_) {},
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Row 2: Per-iteration gain + random start
          Row(
            children: [
              _controlLabel('Iter. Gain'),
              Text(
                clip.iterationGain == 1.0
                    ? 'unity'
                    : '${clip.iterationGain.toStringAsFixed(3)} '
                        '(${clip.iterationGain < 1.0 ? "decay" : "crescendo"})',
                style: TextStyle(
                    color: FluxForgeTheme.textPrimary,
                    fontSize: 12,
                    fontFamily: 'monospace'),
              ),
              SizedBox(
                width: 140,
                child: Slider(
                  value: clip.iterationGain.clamp(0.5, 1.5),
                  min: 0.5,
                  max: 1.5,
                  activeColor: clip.iterationGain < 1.0
                      ? Colors.red
                      : (clip.iterationGain > 1.0
                          ? Colors.green
                          : FluxForgeTheme.accentBlue),
                  inactiveColor: FluxForgeTheme.bgSurface,
                  onChangeEnd: (v) {
                    final rounded = double.parse(v.toStringAsFixed(3));
                    _updateClipLoop(clip, iterationGain: rounded);
                  },
                  onChanged: (_) {},
                ),
              ),
              const SizedBox(width: 16),
              _controlLabel('Rnd Start'),
              Text(
                clip.loopRandomStart == 0
                    ? 'off'
                    : '${(clip.loopRandomStart * 1000).toStringAsFixed(0)}ms',
                style: TextStyle(
                    color: FluxForgeTheme.textPrimary,
                    fontSize: 12,
                    fontFamily: 'monospace'),
              ),
              SizedBox(
                width: 100,
                child: Slider(
                  value: clip.loopRandomStart,
                  min: 0,
                  max: 0.2,
                  activeColor: Colors.purple,
                  inactiveColor: FluxForgeTheme.bgSurface,
                  onChangeEnd: (v) =>
                      _updateClipLoop(clip, loopRandomStart: v),
                  onChanged: (_) {},
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Row 3: Loop region info
          Row(
            children: [
              _controlLabel('Region'),
              Text(
                clip.loopStartSamples > 0 || clip.loopEndSamples > 0
                    ? '${clip.loopStartSamples} → ${clip.loopEndSamples == 0 ? "end" : "${clip.loopEndSamples}"} smp'
                    : 'Full clip',
                style: TextStyle(
                    color: FluxForgeTheme.textPrimary,
                    fontSize: 11,
                    fontFamily: 'monospace'),
              ),
              const SizedBox(width: 8),
              if (clip.loopStartSamples > 0 || clip.loopEndSamples > 0)
                TextButton(
                  onPressed: () =>
                      _updateClipLoop(clip, loopStartSamples: 0, loopEndSamples: 0),
                  style: TextButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text('Reset',
                      style: TextStyle(
                          color: FluxForgeTheme.textSecondary, fontSize: 10)),
                ),
              const Spacer(),
              // Gain after N iterations preview
              if (clip.loopEnabled && clip.iterationGain != 1.0) ...[
                Text(
                  'After 5: ${(_gainAt(clip.iterationGain, 5) * 100).toStringAsFixed(0)}%  '
                  '10: ${(_gainAt(clip.iterationGain, 10) * 100).toStringAsFixed(0)}%  '
                  '20: ${(_gainAt(clip.iterationGain, 20) * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                      color: FluxForgeTheme.textTertiary,
                      fontSize: 9,
                      fontFamily: 'monospace'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  void _updateClipLoop(
    TimelineClip clip, {
    bool? loopEnabled,
    int? loopCount,
    double? loopCrossfade,
    int? loopStartSamples,
    int? loopEndSamples,
    double? iterationGain,
    double? loopRandomStart,
  }) {
    widget.onAction?.call('setClipLoop', {
      'clipId': clip.id,
      'loopEnabled': loopEnabled ?? clip.loopEnabled,
      'loopCount': loopCount ?? clip.loopCount,
      'loopCrossfade': loopCrossfade ?? clip.loopCrossfade,
      'loopStartSamples': loopStartSamples ?? clip.loopStartSamples,
      'loopEndSamples': loopEndSamples ?? clip.loopEndSamples,
      'iterationGain': iterationGain ?? clip.iterationGain,
      'loopRandomStart': loopRandomStart ?? clip.loopRandomStart,
    });
  }

  Widget _buildAdvancedRegionEditor(
      LoopAsset asset, AdvancedLoopRegion region) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Region list tabs
          Wrap(
            spacing: 4,
            children: asset.regions.map((r) {
              final sel = r.name == _selectedRegionName;
              return ChoiceChip(
                label: Text(r.name, style: const TextStyle(fontSize: 10)),
                selected: sel,
                selectedColor:
                    FluxForgeTheme.accentBlue.withValues(alpha: 0.3),
                backgroundColor: FluxForgeTheme.bgSurface,
                labelStyle: TextStyle(
                    color: sel
                        ? FluxForgeTheme.accentBlue
                        : FluxForgeTheme.textPrimary),
                onSelected: (_) =>
                    setState(() => _selectedRegionName = r.name),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          _propGroup('Region: ${region.name}', [
            _prop('In',
                '${region.inSamples} smp (${(region.inSamples / asset.timeline.sampleRate).toStringAsFixed(3)}s)'),
            _prop('Out',
                '${region.outSamples} smp (${(region.outSamples / asset.timeline.sampleRate).toStringAsFixed(3)}s)'),
            _prop('Duration',
                '${region.durationSeconds(asset.timeline.sampleRate).toStringAsFixed(3)}s'),
            _prop('Mode', _loopModeName(region.mode)),
            _prop('Wrap', _wrapPolicyName(region.wrapPolicy)),
            if (region.maxLoops != null) _prop('Max Loops', '${region.maxLoops}'),
          ]),
          const SizedBox(height: 10),
          _propGroup('Crossfade', [
            _prop('Seam', '${region.seamFadeMs.toStringAsFixed(1)}ms'),
            _prop('Crossfade', '${region.crossfadeMs.toStringAsFixed(1)}ms'),
            _prop('Curve', _curveName(region.crossfadeCurve)),
          ]),
          const SizedBox(height: 10),
          _propGroup('Per-Iteration Gain', [
            _prop(
                'Factor',
                region.iterationGainFactor != null
                    ? '${region.iterationGainFactor!.toStringAsFixed(3)}'
                    : 'Disabled'),
            if (region.iterationGainFactor != null) ...[
              _prop('After 5',
                  '${(_gainAt(region.iterationGainFactor!, 5) * 100).toStringAsFixed(1)}%'),
              _prop('After 10',
                  '${(_gainAt(region.iterationGainFactor!, 10) * 100).toStringAsFixed(1)}%'),
            ],
          ]),
          if (region.randomStartRange > 0) ...[
            const SizedBox(height: 10),
            _propGroup('Random Start', [
              _prop('Range',
                  '${region.randomStartRange} smp (${(region.randomStartRange / asset.timeline.sampleRate * 1000).toStringAsFixed(1)}ms)'),
            ]),
          ],
          if (asset.cues.isNotEmpty) ...[
            const SizedBox(height: 10),
            _propGroup('Cues (${asset.cues.length})', [
              for (final cue in asset.cues)
                _prop(cue.name,
                    '${cue.atSeconds(asset.timeline.sampleRate).toStringAsFixed(3)}s  ${cue.cueType.name}'),
            ]),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RIGHT PANEL: Playback + Instances + Callbacks
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildRightPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader('PLAYBACK', Icons.play_circle),
        _buildPlaybackControls(),
        Container(height: 1, color: FluxForgeTheme.borderSubtle),
        _sectionHeader('INSTANCES', Icons.multitrack_audio),
        Expanded(child: _buildInstanceList()),
        Container(height: 1, color: FluxForgeTheme.borderSubtle),
        _sectionHeader('CALLBACKS', Icons.notifications),
        Expanded(child: _buildCallbackLog()),
      ],
    );
  }

  Widget _buildPlaybackControls() {
    final hasAsset = _selectedAsset != null && _selectedRegion != null;
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Row(
        children: [
          Expanded(
            child: _actionBtn('Play', Icons.play_arrow, Colors.green,
                hasAsset
                    ? () => _provider.play(
                        assetId: _selectedAssetId!,
                        region: _selectedRegionName!)
                    : null),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _actionBtn('Stop All', Icons.stop, Colors.red,
                _provider.activeInstances.isNotEmpty
                    ? () => _provider.stopAll()
                    : null),
          ),
        ],
      ),
    );
  }

  Widget _buildInstanceList() {
    final instances = _provider.instances.values.toList();
    if (instances.isEmpty) {
      return Center(
          child: Text('No instances',
              style: TextStyle(
                  color: FluxForgeTheme.textTertiary, fontSize: 10)));
    }
    return ListView.builder(
      itemCount: instances.length,
      padding: EdgeInsets.zero,
      itemBuilder: (_, i) {
        final inst = instances[i];
        return Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            border: Border(
                bottom: BorderSide(
                    color: FluxForgeTheme.borderSubtle.withValues(alpha: 0.5))),
          ),
          child: Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                    color: _stateColor(inst.state), shape: BoxShape.circle),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                    '#${inst.instanceId} ${inst.currentRegion} ×${inst.loopCount}',
                    style: TextStyle(
                        color: FluxForgeTheme.textPrimary, fontSize: 9),
                    overflow: TextOverflow.ellipsis),
              ),
              if (inst.state != LoopPlaybackState.stopped)
                InkWell(
                  onTap: () => _provider.stop(instanceId: inst.instanceId),
                  child:
                      Icon(Icons.stop, size: 14, color: Colors.red.shade300),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCallbackLog() {
    final cbs = _provider.recentCallbacks;
    if (cbs.isEmpty) {
      return Center(
          child: Text('No callbacks',
              style: TextStyle(
                  color: FluxForgeTheme.textTertiary, fontSize: 10)));
    }
    return ListView.builder(
      itemCount: cbs.length,
      reverse: true,
      padding: EdgeInsets.zero,
      itemBuilder: (_, i) {
        final cb = cbs[cbs.length - 1 - i];
        return Container(
          height: 18,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(_cbSummary(cb),
              style: TextStyle(
                  color: cb.isError
                      ? Colors.red.shade300
                      : FluxForgeTheme.textTertiary,
                  fontSize: 8,
                  fontFamily: 'monospace'),
              overflow: TextOverflow.ellipsis),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SHARED WIDGETS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _sectionHeader(String title, IconData icon) {
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: FluxForgeTheme.bgSurface,
      child: Row(
        children: [
          Icon(icon, size: 13, color: FluxForgeTheme.textSecondary),
          const SizedBox(width: 5),
          Text(title,
              style: TextStyle(
                  color: FluxForgeTheme.textSecondary,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1)),
        ],
      ),
    );
  }

  Widget _placeholder(IconData icon, String text) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 28,
              color: FluxForgeTheme.textTertiary.withValues(alpha: 0.3)),
          const SizedBox(height: 6),
          Text(text,
              style: TextStyle(
                  color: FluxForgeTheme.textTertiary, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _controlLabel(String text) {
    return SizedBox(
      width: 70,
      child: Text(text,
          style: TextStyle(
              color: FluxForgeTheme.textSecondary, fontSize: 10)),
    );
  }

  Widget _propGroup(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: TextStyle(
                color: FluxForgeTheme.accentBlue,
                fontSize: 11,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        ...children,
      ],
    );
  }

  Widget _prop(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          SizedBox(
              width: 100,
              child: Text(label,
                  style: TextStyle(
                      color: FluxForgeTheme.textSecondary, fontSize: 10))),
          Expanded(
              child: Text(value,
                  style: TextStyle(
                      color: FluxForgeTheme.textPrimary,
                      fontSize: 10,
                      fontFamily: 'monospace'))),
        ],
      ),
    );
  }

  Widget _actionBtn(
      String label, IconData icon, Color color, VoidCallback? onPressed) {
    return SizedBox(
      height: 26,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 13),
        label: Text(label, style: const TextStyle(fontSize: 10)),
        style: ElevatedButton.styleFrom(
          backgroundColor: onPressed != null
              ? color.withValues(alpha: 0.2)
              : FluxForgeTheme.bgSurface,
          foregroundColor:
              onPressed != null ? color : FluxForgeTheme.textTertiary,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  Color _stateColor(LoopPlaybackState s) => switch (s) {
        LoopPlaybackState.intro => Colors.amber,
        LoopPlaybackState.looping => Colors.green,
        LoopPlaybackState.exiting => Colors.orange,
        LoopPlaybackState.stopped => FluxForgeTheme.textTertiary,
      };

  String _loopModeName(LoopMode m) => switch (m) {
        LoopMode.hard => 'Hard',
        LoopMode.crossfade => 'Crossfade',
        LoopMode.dualVoice => 'Dual Voice',
      };

  String _wrapPolicyName(WrapPolicy p) => switch (p) {
        WrapPolicy.playOnceThenLoop => 'Play Once Then Loop',
        WrapPolicy.skipIntro => 'Skip Intro',
        WrapPolicy.includeInLoop => 'Include In Loop',
        WrapPolicy.introOnly => 'Intro Only',
      };

  String _curveName(LoopCrossfadeCurve c) => switch (c) {
        LoopCrossfadeCurve.equalPower => 'Equal Power',
        LoopCrossfadeCurve.linear => 'Linear',
        LoopCrossfadeCurve.sCurve => 'S-Curve',
        LoopCrossfadeCurve.logarithmic => 'Logarithmic',
        LoopCrossfadeCurve.exponential => 'Exponential',
        LoopCrossfadeCurve.cosineHalf => 'Cosine Half',
        LoopCrossfadeCurve.squareRoot => 'Square Root',
        LoopCrossfadeCurve.sine => 'Sine',
        LoopCrossfadeCurve.fastAttack => 'Fast Attack',
        LoopCrossfadeCurve.slowAttack => 'Slow Attack',
      };

  double _gainAt(double factor, int n) {
    double g = 1.0;
    for (int i = 0; i < n; i++) g *= factor;
    return g;
  }

  String _cbSummary(LoopCallback cb) {
    if (cb.isStarted) return 'START #${cb.instanceId}';
    if (cb.isWrap) return 'WRAP #${cb.instanceId} ×${cb.loopCount}';
    if (cb.isRegionSwitched) return 'REGION ${cb.fromRegion}→${cb.toRegion}';
    if (cb.isStopped) return 'STOP #${cb.instanceId}';
    if (cb.isError) return 'ERR: ${cb.message}';
    return cb.type;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// WAVEFORM LOOP REGION EDITOR (CustomPainter)
// ═══════════════════════════════════════════════════════════════════════════════

/// Visual waveform display with draggable loop in/out markers.
/// Draws: waveform, loop region highlight, in/out handles, crossfade zone.
class _WaveformLoopRegionEditor extends StatefulWidget {
  final Float32List? waveform;
  final Float32List? waveformRight;
  final int channels;
  final double durationSec;
  final bool loopEnabled;
  final int loopStartSamples;
  final int loopEndSamples;
  final double loopCrossfadeSec;
  final int sampleRate;
  final ValueChanged<bool>? onLoopToggle;
  final ValueChanged<int>? onLoopStartChanged;
  final ValueChanged<int>? onLoopEndChanged;
  final ValueChanged<double>? onCrossfadeChanged;

  const _WaveformLoopRegionEditor({
    this.waveform,
    this.waveformRight,
    this.channels = 2,
    required this.durationSec,
    required this.loopEnabled,
    required this.loopStartSamples,
    required this.loopEndSamples,
    required this.loopCrossfadeSec,
    required this.sampleRate,
    this.onLoopToggle,
    this.onLoopStartChanged,
    this.onLoopEndChanged,
    this.onCrossfadeChanged,
  });

  @override
  State<_WaveformLoopRegionEditor> createState() =>
      _WaveformLoopRegionEditorState();
}

enum _DragHandle { none, loopIn, loopOut }

class _WaveformLoopRegionEditorState
    extends State<_WaveformLoopRegionEditor> {
  _DragHandle _dragging = _DragHandle.none;
  _DragHandle _hovering = _DragHandle.none;

  double get _totalSamples => widget.durationSec * widget.sampleRate;
  double get _loopStartFrac =>
      _totalSamples > 0 ? widget.loopStartSamples / _totalSamples : 0;
  double get _loopEndFrac => _totalSamples > 0
      ? (widget.loopEndSamples == 0
          ? 1.0
          : widget.loopEndSamples / _totalSamples)
      : 1.0;

  int _xToSamples(double x, double width) {
    final frac = (x / width).clamp(0.0, 1.0);
    return (frac * _totalSamples).round();
  }

  _DragHandle _hitTest(Offset pos, Size size) {
    const hitW = 12.0;
    final loopInX = _loopStartFrac * size.width;
    final loopOutX = _loopEndFrac * size.width;
    if ((pos.dx - loopInX).abs() < hitW) return _DragHandle.loopIn;
    if ((pos.dx - loopOutX).abs() < hitW) return _DragHandle.loopOut;
    return _DragHandle.none;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      return MouseRegion(
        cursor: _hovering != _DragHandle.none
            ? SystemMouseCursors.resizeColumn
            : SystemMouseCursors.basic,
        onHover: (e) {
          final hit = _hitTest(e.localPosition, constraints.biggest);
          if (hit != _hovering) setState(() => _hovering = hit);
        },
        onExit: (_) {
          if (_hovering != _DragHandle.none) {
            setState(() => _hovering = _DragHandle.none);
          }
        },
        child: GestureDetector(
          onHorizontalDragStart: (d) {
            final hit =
                _hitTest(d.localPosition, constraints.biggest);
            if (hit != _DragHandle.none) {
              setState(() => _dragging = hit);
            }
          },
          onHorizontalDragUpdate: (d) {
            if (_dragging == _DragHandle.none) return;
            final samples =
                _xToSamples(d.localPosition.dx, constraints.maxWidth);
            if (_dragging == _DragHandle.loopIn) {
              widget.onLoopStartChanged?.call(samples);
            } else if (_dragging == _DragHandle.loopOut) {
              widget.onLoopEndChanged?.call(samples);
            }
          },
          onHorizontalDragEnd: (_) {
            setState(() => _dragging = _DragHandle.none);
          },
          child: CustomPaint(
            size: Size(constraints.maxWidth, constraints.maxHeight),
            painter: _LoopWaveformPainter(
              waveform: widget.waveform,
              waveformRight: widget.waveformRight,
              channels: widget.channels,
              loopEnabled: widget.loopEnabled,
              loopStartFrac: _loopStartFrac,
              loopEndFrac: _loopEndFrac,
              crossfadeFrac: widget.durationSec > 0
                  ? widget.loopCrossfadeSec / widget.durationSec
                  : 0,
              hovering: _hovering,
              dragging: _dragging,
            ),
          ),
        ),
      );
    });
  }
}

/// CustomPainter for waveform + loop region overlay
class _LoopWaveformPainter extends CustomPainter {
  final Float32List? waveform;
  final Float32List? waveformRight;
  final int channels;
  final bool loopEnabled;
  final double loopStartFrac;
  final double loopEndFrac;
  final double crossfadeFrac;
  final _DragHandle hovering;
  final _DragHandle dragging;

  _LoopWaveformPainter({
    this.waveform,
    this.waveformRight,
    required this.channels,
    required this.loopEnabled,
    required this.loopStartFrac,
    required this.loopEndFrac,
    required this.crossfadeFrac,
    required this.hovering,
    required this.dragging,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = const Color(0xFF1A1A2E);
    canvas.drawRect(Offset.zero & size, bgPaint);

    // Draw waveform
    _drawWaveform(canvas, size);

    if (!loopEnabled) {
      // Draw "LOOP OFF" label
      final tp = TextPainter(
        text: TextSpan(
          text: 'LOOP OFF — enable loop to set region',
          style: TextStyle(color: Colors.white38, fontSize: 11),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
          canvas, Offset(size.width / 2 - tp.width / 2, size.height / 2 - 6));
      return;
    }

    // Draw dimmed areas outside loop region
    final loopInX = loopStartFrac * size.width;
    final loopOutX = loopEndFrac * size.width;
    final dimPaint = Paint()..color = Colors.black.withValues(alpha: 0.55);
    if (loopInX > 0) {
      canvas.drawRect(Rect.fromLTWH(0, 0, loopInX, size.height), dimPaint);
    }
    if (loopOutX < size.width) {
      canvas.drawRect(
          Rect.fromLTWH(loopOutX, 0, size.width - loopOutX, size.height),
          dimPaint);
    }

    // Draw loop region border
    final regionPaint = Paint()
      ..color = Colors.cyan.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;
    canvas.drawRect(
        Rect.fromLTRB(loopInX, 0, loopOutX, size.height), regionPaint);

    // Draw crossfade zone
    if (crossfadeFrac > 0) {
      final xfadeW = crossfadeFrac * size.width;
      final xfadePaint = Paint()
        ..color = Colors.orange.withValues(alpha: 0.2)
        ..style = PaintingStyle.fill;
      // Crossfade at loop boundary (end → start)
      canvas.drawRect(
          Rect.fromLTWH(loopOutX - xfadeW, 0, xfadeW, size.height),
          xfadePaint);
      // Draw crossfade curve hint
      final curvePaint = Paint()
        ..color = Colors.orange.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      final path = Path();
      path.moveTo(loopOutX - xfadeW, size.height * 0.8);
      path.quadraticBezierTo(
          loopOutX - xfadeW / 2, size.height * 0.2, loopOutX, size.height * 0.2);
      canvas.drawPath(path, curvePaint);
    }

    // Draw loop handles
    _drawHandle(canvas, size, loopInX, Colors.green,
        hovering == _DragHandle.loopIn || dragging == _DragHandle.loopIn,
        'IN');
    _drawHandle(canvas, size, loopOutX, Colors.red,
        hovering == _DragHandle.loopOut || dragging == _DragHandle.loopOut,
        'OUT');

    // Draw ruler
    _drawRuler(canvas, size);
  }

  void _drawWaveform(Canvas canvas, Size size) {
    final data = waveform;
    if (data == null || data.isEmpty) {
      // No waveform data — draw center line
      final linePaint = Paint()
        ..color = Colors.white12
        ..strokeWidth = 1;
      canvas.drawLine(Offset(0, size.height / 2),
          Offset(size.width, size.height / 2), linePaint);
      final tp = TextPainter(
        text: TextSpan(
          text: 'No waveform data',
          style: TextStyle(color: Colors.white24, fontSize: 9),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas,
          Offset(size.width / 2 - tp.width / 2, size.height / 2 + 8));
      return;
    }

    final wavePaint = Paint()
      ..color = const Color(0xFF4FC3F7)
      ..style = PaintingStyle.fill;

    final centerY = size.height / 2;
    final halfH = size.height * 0.4;
    final step = data.length / size.width;

    for (double x = 0; x < size.width; x += 1) {
      final idx = (x * step).toInt().clamp(0, data.length - 1);
      final val = data[idx].abs().clamp(0.0, 1.0);
      final h = val * halfH;
      canvas.drawRect(
          Rect.fromCenter(center: Offset(x, centerY), width: 1, height: h * 2),
          wavePaint);
    }
  }

  void _drawHandle(Canvas canvas, Size size, double x, Color color,
      bool active, String label) {
    final handleW = active ? 4.0 : 2.0;
    final paint = Paint()
      ..color = active ? color : color.withValues(alpha: 0.7)
      ..strokeWidth = handleW;
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);

    // Handle grip at top
    final gripPaint = Paint()
      ..color = active ? color : color.withValues(alpha: 0.8)
      ..style = PaintingStyle.fill;
    final gripRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(x, 10), width: 20, height: 16),
      const Radius.circular(3),
    );
    canvas.drawRRect(gripRect, gripPaint);

    // Label
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
            color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(x - tp.width / 2, 10 - tp.height / 2));
  }

  void _drawRuler(Canvas canvas, Size size) {
    final rulerPaint = Paint()
      ..color = Colors.white12
      ..strokeWidth = 0.5;
    final textStyle = TextStyle(color: Colors.white24, fontSize: 7);
    for (int i = 0; i <= 10; i++) {
      final x = size.width * i / 10;
      canvas.drawLine(
          Offset(x, size.height - 12), Offset(x, size.height), rulerPaint);
      if (i % 2 == 0) {
        final tp = TextPainter(
          text: TextSpan(text: '${i * 10}%', style: textStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x - tp.width / 2, size.height - 12));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LoopWaveformPainter old) =>
      waveform != old.waveform ||
      loopEnabled != old.loopEnabled ||
      loopStartFrac != old.loopStartFrac ||
      loopEndFrac != old.loopEndFrac ||
      crossfadeFrac != old.crossfadeFrac ||
      hovering != old.hovering ||
      dragging != old.dragging;
}
