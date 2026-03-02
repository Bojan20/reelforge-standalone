/// Loop Editor Panel — Advanced Looping System UI
///
/// Wwise-grade loop editor with track-aware clip integration:
/// - Left: Track clips (loop status) + registered LoopAssets
/// - Center: Clip loop properties editor / LoopAsset region properties
/// - Right: Active instances, playback controls, callback log
///
/// Connected to selectedTrackId from Lower Zone for track context.

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

  // Editing state
  bool _editingLoop = false;
  int _editLoopCount = 0;
  double _editCrossfade = 0.0;

  @override
  void initState() {
    super.initState();
    _provider = GetIt.instance<LoopProvider>();
    _provider.addListener(_onProviderUpdate);
    if (!_provider.isInitialized) {
      _provider.init();
    }
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
        _editingLoop = false;
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
                // Left: Track clips + LoopAssets
                SizedBox(width: 260, child: _buildLeftPanel()),
                Container(width: 1, color: FluxForgeTheme.borderSubtle),
                // Center: Properties editor
                Expanded(flex: 2, child: _buildCenterPanel()),
                Container(width: 1, color: FluxForgeTheme.borderSubtle),
                // Right: Instances + playback + callbacks
                SizedBox(width: 280, child: _buildInstancePanel()),
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
          // Track indicator
          if (widget.selectedTrackId != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: FluxForgeTheme.accentBlue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text('Track ${widget.selectedTrackId}',
                  style: TextStyle(
                      color: FluxForgeTheme.accentBlue,
                      fontSize: 10,
                      fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 8),
            Text('${_trackClips.length} clips',
                style: TextStyle(
                    color: FluxForgeTheme.textSecondary, fontSize: 11)),
          ] else
            Text('No track selected',
                style: TextStyle(
                    color: FluxForgeTheme.textTertiary, fontSize: 11)),
          const Spacer(),
          // Engine status
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
                  fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          Text('${_provider.activeInstances.length} instances',
              style: TextStyle(
                  color: FluxForgeTheme.textSecondary, fontSize: 11)),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LEFT PANEL: Track Clips + LoopAssets
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildLeftPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionHeader('TRACK CLIPS', Icons.audiotrack),
        Expanded(flex: 2, child: _buildTrackClipList()),
        Container(height: 1, color: FluxForgeTheme.borderSubtle),
        _buildSectionHeader('LOOP ASSETS', Icons.audio_file),
        Expanded(flex: 1, child: _buildAssetList()),
        if (_selectedAssetId != null) ...[
          Container(height: 1, color: FluxForgeTheme.borderSubtle),
          _buildSectionHeader('REGIONS', Icons.crop_free),
          Expanded(flex: 1, child: _buildRegionList()),
        ],
      ],
    );
  }

  Widget _buildTrackClipList() {
    if (widget.selectedTrackId == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.touch_app, size: 32, color: FluxForgeTheme.textTertiary),
            const SizedBox(height: 8),
            Text('Select a track in the timeline',
                style: TextStyle(
                    color: FluxForgeTheme.textTertiary, fontSize: 12)),
            const SizedBox(height: 4),
            Text('to view and edit clip loops',
                style: TextStyle(
                    color: FluxForgeTheme.textTertiary, fontSize: 11)),
          ],
        ),
      );
    }

    final clips = _trackClips;
    if (clips.isEmpty) {
      return Center(
        child: Text('No clips on this track',
            style:
                TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 11)),
      );
    }

    return ListView.builder(
      itemCount: clips.length,
      padding: EdgeInsets.zero,
      itemBuilder: (context, index) {
        final clip = clips[index];
        final selected = clip.id == _selectedClipId;
        return InkWell(
          onTap: () => setState(() {
            _selectedClipId = clip.id;
            _selectedAssetId = null;
            _editingLoop = false;
            _editLoopCount = clip.loopCount;
            _editCrossfade = clip.loopCrossfade;
          }),
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            color: selected
                ? FluxForgeTheme.accentBlue.withValues(alpha: 0.15)
                : Colors.transparent,
            child: Row(
              children: [
                // Loop indicator
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: clip.loopEnabled
                        ? Colors.green.withValues(alpha: 0.2)
                        : FluxForgeTheme.bgSurface,
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                      color: clip.loopEnabled
                          ? Colors.green
                          : FluxForgeTheme.borderSubtle,
                    ),
                  ),
                  child: Icon(
                    clip.loopEnabled ? Icons.loop : Icons.trending_flat,
                    size: 12,
                    color: clip.loopEnabled
                        ? Colors.green
                        : FluxForgeTheme.textTertiary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(clip.name,
                          style: TextStyle(
                              color: selected
                                  ? FluxForgeTheme.accentBlue
                                  : FluxForgeTheme.textPrimary,
                              fontSize: 11,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.w400),
                          overflow: TextOverflow.ellipsis),
                      Text(
                        '${clip.duration.toStringAsFixed(2)}s  '
                        '${clip.loopEnabled ? "loop×${clip.loopCount == 0 ? "∞" : clip.loopCount}" : "one-shot"}',
                        style: TextStyle(
                            color: FluxForgeTheme.textTertiary, fontSize: 9),
                      ),
                    ],
                  ),
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
      return Center(
        child: Text('No advanced loop assets',
            style:
                TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 11)),
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
            _selectedClipId = null;
            _selectedRegionName =
                asset.regions.isNotEmpty ? asset.regions.first.name : null;
          }),
        );
      },
    );
  }

  Widget _buildRegionList() {
    final asset = _selectedAsset;
    if (asset == null) return const SizedBox.shrink();

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

  // ═══════════════════════════════════════════════════════════════════════════
  // CENTER PANEL: Properties Editor
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildCenterPanel() {
    final clip = _selectedClip;
    final asset = _selectedAsset;

    // Clip selected — show clip loop editor
    if (clip != null) return _buildClipLoopEditor(clip);

    // LoopAsset region selected — show region properties
    if (asset != null && _selectedRegion != null) {
      return _buildRegionProperties(asset, _selectedRegion!);
    }

    // Nothing selected
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.loop, size: 48,
              color: FluxForgeTheme.textTertiary.withValues(alpha: 0.3)),
          const SizedBox(height: 12),
          Text('Select a clip or loop asset',
              style: TextStyle(
                  color: FluxForgeTheme.textTertiary, fontSize: 13)),
          const SizedBox(height: 4),
          Text('to view and edit loop properties',
              style: TextStyle(
                  color: FluxForgeTheme.textTertiary, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildClipLoopEditor(TimelineClip clip) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Clip info header
          _buildPropertyGroup('Clip: ${clip.name}', [
            _buildPropertyRow('Duration', '${clip.duration.toStringAsFixed(3)}s'),
            _buildPropertyRow('Start', '${clip.startTime.toStringAsFixed(3)}s'),
            _buildPropertyRow('Source', clip.sourceFile ?? 'none'),
            _buildPropertyRow('Channels', '${clip.channels}'),
            _buildPropertyRow('Gain', '${(clip.gain * 100).toStringAsFixed(0)}%'),
          ]),
          const SizedBox(height: 16),

          // Loop toggle
          _buildPropertyGroup('Loop Settings', [
            // Enable/disable loop
            Row(
              children: [
                SizedBox(
                  width: 120,
                  child: Text('Loop Enabled',
                      style: TextStyle(
                          color: FluxForgeTheme.textSecondary, fontSize: 11)),
                ),
                Switch(
                  value: clip.loopEnabled,
                  onChanged: (v) {
                    widget.onAction?.call('setClipLoop', {
                      'clipId': clip.id,
                      'loopEnabled': v,
                      'loopCount': clip.loopCount,
                      'loopCrossfade': clip.loopCrossfade,
                    });
                  },
                  activeColor: FluxForgeTheme.accentBlue,
                ),
              ],
            ),

            if (clip.loopEnabled) ...[
              const SizedBox(height: 8),
              // Loop count
              Row(
                children: [
                  SizedBox(
                    width: 120,
                    child: Text('Iterations',
                        style: TextStyle(
                            color: FluxForgeTheme.textSecondary,
                            fontSize: 11)),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        Text(
                          _editLoopCount == 0 ? '∞ infinite' : '×$_editLoopCount',
                          style: TextStyle(
                              color: FluxForgeTheme.textPrimary,
                              fontSize: 12,
                              fontFamily: 'monospace'),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 150,
                          child: Slider(
                            value: _editLoopCount.toDouble(),
                            min: 0,
                            max: 64,
                            divisions: 64,
                            activeColor: FluxForgeTheme.accentBlue,
                            inactiveColor:
                                FluxForgeTheme.bgSurface,
                            onChanged: (v) =>
                                setState(() => _editLoopCount = v.round()),
                            onChangeEnd: (v) {
                              widget.onAction?.call('setClipLoop', {
                                'clipId': clip.id,
                                'loopEnabled': true,
                                'loopCount': v.round(),
                                'loopCrossfade': clip.loopCrossfade,
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // Loop crossfade
              Row(
                children: [
                  SizedBox(
                    width: 120,
                    child: Text('Crossfade',
                        style: TextStyle(
                            color: FluxForgeTheme.textSecondary,
                            fontSize: 11)),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        Text(
                          '${(_editCrossfade * 1000).toStringAsFixed(0)}ms',
                          style: TextStyle(
                              color: FluxForgeTheme.textPrimary,
                              fontSize: 12,
                              fontFamily: 'monospace'),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 150,
                          child: Slider(
                            value: _editCrossfade,
                            min: 0,
                            max: 0.5,
                            activeColor: FluxForgeTheme.accentBlue,
                            inactiveColor:
                                FluxForgeTheme.bgSurface,
                            onChanged: (v) =>
                                setState(() => _editCrossfade = v),
                            onChangeEnd: (v) {
                              widget.onAction?.call('setClipLoop', {
                                'clipId': clip.id,
                                'loopEnabled': true,
                                'loopCount': clip.loopCount,
                                'loopCrossfade': v,
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),
              // Quick info
              _buildPropertyRow('Total Duration',
                  clip.loopCount == 0
                      ? '∞ (infinite loop)'
                      : '${(clip.duration * clip.loopCount).toStringAsFixed(2)}s'),
              _buildPropertyRow('Fade In', '${(clip.fadeIn * 1000).toStringAsFixed(0)}ms'),
              _buildPropertyRow('Fade Out', '${(clip.fadeOut * 1000).toStringAsFixed(0)}ms'),
            ],
          ]),

          if (clip.loopEnabled) ...[
            const SizedBox(height: 16),
            // Promote to Advanced LoopAsset
            _buildPropertyGroup('Advanced', [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'For Wwise-grade features (regions, cues, per-iteration gain, '
                  'sync modes, dual-voice crossfade), register this clip as a '
                  'LoopAsset in the assets panel below.',
                  style: TextStyle(
                      color: FluxForgeTheme.textTertiary, fontSize: 10),
                ),
              ),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _buildRegionProperties(LoopAsset asset, AdvancedLoopRegion region) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPropertyGroup('Region: ${region.name}', [
            _buildPropertyRow('In',
                '${region.inSamples} smp (${(region.inSamples / asset.timeline.sampleRate).toStringAsFixed(3)}s)'),
            _buildPropertyRow('Out',
                '${region.outSamples} smp (${(region.outSamples / asset.timeline.sampleRate).toStringAsFixed(3)}s)'),
            _buildPropertyRow('Duration',
                '${region.durationSeconds(asset.timeline.sampleRate).toStringAsFixed(3)}s'),
          ]),
          const SizedBox(height: 12),
          _buildPropertyGroup('Behavior', [
            _buildPropertyRow('Mode', _loopModeName(region.mode)),
            _buildPropertyRow(
                'Wrap Policy', _wrapPolicyName(region.wrapPolicy)),
            if (region.maxLoops != null)
              _buildPropertyRow('Max Loops', '${region.maxLoops}'),
          ]),
          const SizedBox(height: 12),
          _buildPropertyGroup('Crossfade', [
            _buildPropertyRow(
                'Seam Fade', '${region.seamFadeMs.toStringAsFixed(1)}ms'),
            _buildPropertyRow(
                'Crossfade', '${region.crossfadeMs.toStringAsFixed(1)}ms'),
            _buildPropertyRow('Curve', _curveName(region.crossfadeCurve)),
          ]),
          const SizedBox(height: 12),
          _buildPropertyGroup('Per-Iteration Gain', [
            _buildPropertyRow(
              'Factor',
              region.iterationGainFactor != null
                  ? '${region.iterationGainFactor!.toStringAsFixed(3)} (${_gainDesc(region.iterationGainFactor!)})'
                  : 'Disabled',
            ),
            if (region.iterationGainFactor != null) ...[
              _buildPropertyRow('After 5 loops',
                  '${(_gainAt(region.iterationGainFactor!, 5) * 100).toStringAsFixed(1)}%'),
              _buildPropertyRow('After 10 loops',
                  '${(_gainAt(region.iterationGainFactor!, 10) * 100).toStringAsFixed(1)}%'),
            ],
          ]),
          const SizedBox(height: 12),
          _buildPropertyGroup('Random Start', [
            _buildPropertyRow(
              'Range',
              region.randomStartRange > 0
                  ? '${region.randomStartRange} smp (${(region.randomStartRange / asset.timeline.sampleRate * 1000).toStringAsFixed(1)}ms)'
                  : 'Disabled',
            ),
          ]),
          const SizedBox(height: 12),
          _buildPropertyGroup('Asset: ${asset.id}', [
            _buildPropertyRow(
                'Sample Rate', '${asset.timeline.sampleRate} Hz'),
            _buildPropertyRow('Channels', '${asset.timeline.channels}'),
            _buildPropertyRow(
                'Length', '${asset.timeline.lengthSamples} smp'),
            _buildPropertyRow('Duration',
                '${asset.timeline.durationSeconds.toStringAsFixed(3)}s'),
            if (asset.timeline.bpm != null)
              _buildPropertyRow('BPM', '${asset.timeline.bpm}'),
          ]),
          if (asset.cues.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildPropertyGroup('Cues (${asset.cues.length})', [
              for (final cue in asset.cues)
                _buildPropertyRow(
                  '${_cueIcon(cue.cueType) == Icons.play_arrow ? "▶" : _cueIcon(cue.cueType) == Icons.stop ? "■" : "◆"} ${cue.name}',
                  '${cue.atSeconds(asset.timeline.sampleRate).toStringAsFixed(3)}s  ${cue.cueType.name}',
                ),
            ]),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RIGHT PANEL: Instances + Playback + Callbacks
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
      child: Row(
        children: [
          Expanded(
            child: _buildActionButton(
              'Play',
              Icons.play_arrow,
              hasAsset && hasRegion
                  ? () => _provider.play(
                        assetId: _selectedAssetId!,
                        region: _selectedRegionName!,
                      )
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
    );
  }

  Widget _buildInstanceList() {
    final instances = _provider.instances.values.toList();
    if (instances.isEmpty) {
      return Center(
        child: Text('No active instances',
            style:
                TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 11)),
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
                  color: FluxForgeTheme.borderSubtle.withValues(alpha: 0.5)),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _stateColor(inst.state),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('#${inst.instanceId} — ${inst.assetId}',
                        style: TextStyle(
                            color: FluxForgeTheme.textPrimary, fontSize: 10),
                        overflow: TextOverflow.ellipsis),
                    Text(
                        '${inst.currentRegion}  loops:${inst.loopCount}  ${inst.state.name}',
                        style: TextStyle(
                            color: FluxForgeTheme.textTertiary, fontSize: 9)),
                  ],
                ),
              ),
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

  Widget _buildCallbackLog() {
    final callbacks = _provider.recentCallbacks;
    if (callbacks.isEmpty) {
      return Center(
        child: Text('No callbacks',
            style:
                TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 11)),
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

  // ═══════════════════════════════════════════════════════════════════════════
  // SHARED WIDGETS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSectionHeader(String title, IconData icon) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: FluxForgeTheme.bgSurface,
      child: Row(
        children: [
          Icon(icon, size: 14, color: FluxForgeTheme.textSecondary),
          const SizedBox(width: 6),
          Text(title,
              style: TextStyle(
                  color: FluxForgeTheme.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1)),
        ],
      ),
    );
  }

  Widget _buildListItem(
      String title, String subtitle, bool selected, VoidCallback? onTap) {
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
            Expanded(
              child: Text(title,
                  style: TextStyle(
                      color: selected
                          ? FluxForgeTheme.accentBlue
                          : FluxForgeTheme.textPrimary,
                      fontSize: 12,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w400),
                  overflow: TextOverflow.ellipsis),
            ),
            Text(subtitle,
                style: TextStyle(
                    color: FluxForgeTheme.textTertiary, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Widget _buildPropertyGroup(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: TextStyle(
                color: FluxForgeTheme.accentBlue,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
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
            child: Text(label,
                style: TextStyle(
                    color: FluxForgeTheme.textSecondary, fontSize: 11)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    color: FluxForgeTheme.textPrimary,
                    fontSize: 11,
                    fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(
      String label, IconData icon, VoidCallback? onPressed, Color color) {
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
          foregroundColor:
              onPressed != null ? color : FluxForgeTheme.textTertiary,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  Color _stateColor(LoopPlaybackState state) => switch (state) {
        LoopPlaybackState.intro => Colors.amber,
        LoopPlaybackState.looping => Colors.green,
        LoopPlaybackState.exiting => Colors.orange,
        LoopPlaybackState.stopped => FluxForgeTheme.textTertiary,
      };

  IconData _cueIcon(CueType type) => switch (type) {
        CueType.entry => Icons.play_arrow,
        CueType.exit => Icons.stop,
        CueType.event => Icons.flash_on,
        CueType.sync => Icons.sync,
        CueType.custom => Icons.flag,
      };

  String _loopModeName(LoopMode mode) => switch (mode) {
        LoopMode.hard => 'Hard (zero-crossing)',
        LoopMode.crossfade => 'Crossfade (single voice)',
        LoopMode.dualVoice => 'Dual Voice (web-safe)',
      };

  String _wrapPolicyName(WrapPolicy p) => switch (p) {
        WrapPolicy.playOnceThenLoop => 'Play Once Then Loop',
        WrapPolicy.skipIntro => 'Skip Intro',
        WrapPolicy.includeInLoop => 'Include In Loop',
        WrapPolicy.introOnly => 'Intro Only (no repeat)',
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

  String _gainDesc(double f) =>
      f < 1.0 ? 'decay' : (f > 1.0 ? 'crescendo' : 'unity');

  double _gainAt(double factor, int n) {
    double g = 1.0;
    for (int i = 0; i < n; i++) g *= factor;
    return g;
  }

  String _callbackSummary(LoopCallback cb) {
    if (cb.isStarted) return 'STARTED #${cb.instanceId} ${cb.assetId}';
    if (cb.isStateChanged) {
      return 'STATE #${cb.instanceId} → ${cb.state?.name}';
    }
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
