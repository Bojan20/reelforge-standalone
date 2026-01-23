/// Context Transition Timeline — ALE Context Flow Visualization
///
/// Features:
/// - Visual timeline of context transitions
/// - Transition profile configuration
/// - Sync point visualization (beat/bar/phrase)
/// - Layer volume crossfade preview
/// - Context flow diagram
/// - Transition history log

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/ale_provider.dart';
import '../../theme/fluxforge_theme.dart';

/// Recorded transition event
class TransitionEvent {
  final String fromContext;
  final String toContext;
  final String? transitionProfile;
  final DateTime timestamp;
  final SyncMode syncMode;
  final int durationMs;

  TransitionEvent({
    required this.fromContext,
    required this.toContext,
    this.transitionProfile,
    required this.timestamp,
    required this.syncMode,
    required this.durationMs,
  });
}

class ContextTransitionTimeline extends StatefulWidget {
  final double height;

  const ContextTransitionTimeline({
    super.key,
    this.height = 500,
  });

  @override
  State<ContextTransitionTimeline> createState() => _ContextTransitionTimelineState();
}

class _ContextTransitionTimelineState extends State<ContextTransitionTimeline>
    with TickerProviderStateMixin {
  late TabController _tabController;
  late AnimationController _transitionAnimator;

  // Simulation state
  String? _currentContextId;
  String? _previousContextId;
  bool _isTransitioning = false;
  double _transitionProgress = 0.0;
  Timer? _transitionTimer;

  // History
  final List<TransitionEvent> _transitionHistory = [];

  // Selected transition profile
  String? _selectedTransitionId;

  // Beat grid simulation
  int _currentBeat = 0;
  int _beatsPerBar = 4;
  double _tempo = 120.0;
  Timer? _beatTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _transitionAnimator = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _startBeatTimer();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _transitionAnimator.dispose();
    _transitionTimer?.cancel();
    _beatTimer?.cancel();
    super.dispose();
  }

  void _startBeatTimer() {
    final beatDuration = Duration(milliseconds: (60000 / _tempo).round());
    _beatTimer = Timer.periodic(beatDuration, (_) {
      setState(() {
        _currentBeat = (_currentBeat + 1) % (_beatsPerBar * 4);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        border: Border.all(color: FluxForgeTheme.borderSubtle),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Consumer<AleProvider>(
        builder: (context, ale, _) {
          return Column(
            children: [
              _buildHeader(ale),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildTimelineTab(ale),
                    _buildContextsTab(ale),
                    _buildTransitionsTab(ale),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader(AleProvider ale) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgSurface,
        border: Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.timeline, color: Colors.cyan, size: 20),
              const SizedBox(width: 8),
              Text(
                'Context Transition Timeline',
                style: TextStyle(
                  color: FluxForgeTheme.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              // Beat indicator
              _buildBeatIndicator(),
              const SizedBox(width: 16),
              // Current context badge
              if (_currentContextId != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getContextColor(_currentContextId!).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: _getContextColor(_currentContextId!)),
                  ),
                  child: Text(
                    _currentContextId!,
                    style: TextStyle(
                      color: _getContextColor(_currentContextId!),
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          TabBar(
            controller: _tabController,
            labelColor: FluxForgeTheme.accent,
            unselectedLabelColor: FluxForgeTheme.textMuted,
            indicatorColor: FluxForgeTheme.accent,
            tabs: const [
              Tab(text: 'Timeline'),
              Tab(text: 'Contexts'),
              Tab(text: 'Transitions'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBeatIndicator() {
    final bar = _currentBeat ~/ _beatsPerBar;
    final beat = (_currentBeat % _beatsPerBar) + 1;
    final isDownbeat = beat == 1;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDownbeat
            ? Colors.orange.withValues(alpha: 0.2)
            : FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...List.generate(_beatsPerBar, (i) {
            final isCurrent = i + 1 == beat;
            return Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(right: 2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isCurrent
                    ? (isDownbeat ? Colors.orange : Colors.green)
                    : FluxForgeTheme.borderSubtle,
              ),
            );
          }),
          const SizedBox(width: 4),
          Text(
            '${bar + 1}.$beat',
            style: TextStyle(
              color: FluxForgeTheme.textMuted,
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TIMELINE TAB
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildTimelineTab(AleProvider ale) {
    return Column(
      children: [
        // Transition visualization
        Expanded(
          flex: 2,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: _buildTransitionVisualization(ale),
          ),
        ),
        // History
        Expanded(
          flex: 3,
          child: _buildHistoryList(),
        ),
      ],
    );
  }

  Widget _buildTransitionVisualization(AleProvider ale) {
    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgSurface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Text(
                  'Transition Preview',
                  style: TextStyle(
                    color: FluxForgeTheme.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                const Spacer(),
                if (_isTransitioning)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            value: _transitionProgress,
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(Colors.orange),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'TRANSITIONING',
                          style: TextStyle(
                            color: Colors.orange,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // From context
                  Expanded(
                    child: _buildContextBox(
                      _previousContextId ?? 'None',
                      isFrom: true,
                      fadeOut: _isTransitioning,
                      progress: _transitionProgress,
                    ),
                  ),
                  // Arrow
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.arrow_forward,
                          color: _isTransitioning
                              ? Colors.orange
                              : FluxForgeTheme.textMuted,
                          size: 24,
                        ),
                        if (_isTransitioning)
                          Text(
                            '${(_transitionProgress * 100).toStringAsFixed(0)}%',
                            style: TextStyle(
                              color: Colors.orange,
                              fontSize: 10,
                            ),
                          ),
                      ],
                    ),
                  ),
                  // To context
                  Expanded(
                    child: _buildContextBox(
                      _currentContextId ?? 'None',
                      isFrom: false,
                      fadeIn: _isTransitioning,
                      progress: _transitionProgress,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Crossfade visualization
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: _buildCrossfadeVisualization(),
          ),
        ],
      ),
    );
  }

  Widget _buildContextBox(
    String contextId, {
    required bool isFrom,
    bool fadeOut = false,
    bool fadeIn = false,
    double progress = 0,
  }) {
    double opacity = 1.0;
    if (fadeOut) opacity = 1.0 - progress;
    if (fadeIn) opacity = progress;

    final color = _getContextColor(contextId);

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 100),
      opacity: opacity.clamp(0.3, 1.0),
      child: Container(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: color.withValues(alpha: opacity),
            width: 2,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              isFrom ? 'FROM' : 'TO',
              style: TextStyle(
                color: FluxForgeTheme.textMuted,
                fontSize: 9,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              contextId,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            // Layer indicators
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) {
                final layerActive = i < 3; // Simulated
                return Container(
                  width: 8,
                  height: 16,
                  margin: const EdgeInsets.only(right: 2),
                  decoration: BoxDecoration(
                    color: layerActive
                        ? color.withValues(alpha: opacity * 0.8)
                        : FluxForgeTheme.bgDeep,
                    borderRadius: BorderRadius.circular(2),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCrossfadeVisualization() {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(4),
      ),
      child: CustomPaint(
        size: const Size(double.infinity, 40),
        painter: _CrossfadePainter(
          progress: _transitionProgress,
          fromColor: _previousContextId != null
              ? _getContextColor(_previousContextId!)
              : FluxForgeTheme.textMuted,
          toColor: _currentContextId != null
              ? _getContextColor(_currentContextId!)
              : FluxForgeTheme.textMuted,
        ),
      ),
    );
  }

  Widget _buildHistoryList() {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgSurface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Text(
                  'Transition History',
                  style: TextStyle(
                    color: FluxForgeTheme.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.clear_all, size: 14),
                  label: const Text('Clear'),
                  onPressed: () => setState(() => _transitionHistory.clear()),
                ),
              ],
            ),
          ),
          Expanded(
            child: _transitionHistory.isEmpty
                ? Center(
                    child: Text(
                      'No transitions recorded yet',
                      style: TextStyle(color: FluxForgeTheme.textMuted),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _transitionHistory.length,
                    itemBuilder: (context, index) {
                      final reversed = _transitionHistory.length - 1 - index;
                      final event = _transitionHistory[reversed];
                      return _buildHistoryItem(event);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryItem(TransitionEvent event) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          // From context
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: _getContextColor(event.fromContext).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              event.fromContext,
              style: TextStyle(
                color: _getContextColor(event.fromContext),
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Icon(
              Icons.arrow_forward,
              size: 12,
              color: FluxForgeTheme.textMuted,
            ),
          ),
          // To context
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: _getContextColor(event.toContext).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              event.toContext,
              style: TextStyle(
                color: _getContextColor(event.toContext),
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Spacer(),
          // Sync mode badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: _getSyncModeColor(event.syncMode).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              event.syncMode.name.toUpperCase(),
              style: TextStyle(
                color: _getSyncModeColor(event.syncMode),
                fontSize: 8,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${event.durationMs}ms',
            style: TextStyle(
              color: FluxForgeTheme.textMuted,
              fontSize: 9,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _formatTime(event.timestamp),
            style: TextStyle(
              color: FluxForgeTheme.textMuted,
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CONTEXTS TAB
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildContextsTab(AleProvider ale) {
    final contexts = ale.profile?.contexts.values.toList() ?? [];

    if (contexts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.layers, size: 48, color: FluxForgeTheme.textMuted),
            const SizedBox(height: 8),
            Text(
              'No contexts defined',
              style: TextStyle(color: FluxForgeTheme.textMuted),
            ),
            const SizedBox(height: 4),
            Text(
              'Load an ALE profile to see contexts',
              style: TextStyle(
                color: FluxForgeTheme.textMuted,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Available Contexts',
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 1.5,
              ),
              itemCount: contexts.length,
              itemBuilder: (context, index) {
                final ctx = contexts[index];
                return _buildContextCard(ctx, ale);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContextCard(AleContext ctx, AleProvider ale) {
    final isActive = ctx.id == _currentContextId;
    final color = _getContextColor(ctx.id);

    return GestureDetector(
      onTap: () => _transitionToContext(ctx.id, ale),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isActive
              ? color.withValues(alpha: 0.2)
              : FluxForgeTheme.bgSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? color : FluxForgeTheme.borderSubtle,
            width: isActive ? 2 : 1,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.3),
                    blurRadius: 8,
                  ),
                ]
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isActive ? color : FluxForgeTheme.textMuted,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      ctx.name,
                      style: TextStyle(
                        color: FluxForgeTheme.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Row(
                children: [
                  Icon(
                    Icons.layers,
                    size: 12,
                    color: FluxForgeTheme.textMuted,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${ctx.layers.length} layers',
                    style: TextStyle(
                      color: FluxForgeTheme.textMuted,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // Layer preview
              Row(
                children: List.generate(
                  ctx.layers.length.clamp(0, 5),
                  (i) => Container(
                    width: 12,
                    height: 4,
                    margin: const EdgeInsets.only(right: 2),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.3 + (i * 0.15)),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TRANSITIONS TAB
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildTransitionsTab(AleProvider ale) {
    final transitions = ale.profile?.transitions.values.toList() ?? [];

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Transition Profiles',
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: transitions.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.swap_horiz, size: 48, color: FluxForgeTheme.textMuted),
                        const SizedBox(height: 8),
                        Text(
                          'No transition profiles defined',
                          style: TextStyle(color: FluxForgeTheme.textMuted),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: transitions.length,
                    itemBuilder: (context, index) {
                      final transition = transitions[index];
                      return _buildTransitionProfileCard(transition);
                    },
                  ),
          ),
          const SizedBox(height: 12),
          // Quick presets
          Text(
            'Quick Test Presets',
            style: TextStyle(
              color: FluxForgeTheme.textMuted,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              _buildPresetButton('Immediate', SyncMode.immediate, 0),
              _buildPresetButton('Beat Sync', SyncMode.beat, 500),
              _buildPresetButton('Bar Sync', SyncMode.bar, 1000),
              _buildPresetButton('Phrase Sync', SyncMode.phrase, 2000),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTransitionProfileCard(AleTransitionProfile profile) {
    final isSelected = _selectedTransitionId == profile.id;

    return GestureDetector(
      onTap: () => setState(() => _selectedTransitionId = profile.id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? FluxForgeTheme.accent.withValues(alpha: 0.1)
              : FluxForgeTheme.bgSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? FluxForgeTheme.accent : FluxForgeTheme.borderSubtle,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _getSyncModeIcon(profile.syncMode),
                  size: 16,
                  color: _getSyncModeColor(profile.syncMode),
                ),
                const SizedBox(width: 8),
                Text(
                  profile.name,
                  style: TextStyle(
                    color: FluxForgeTheme.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _getSyncModeColor(profile.syncMode).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    profile.syncMode.name.toUpperCase(),
                    style: TextStyle(
                      color: _getSyncModeColor(profile.syncMode),
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildTimingChip('Fade In', profile.fadeInMs),
                const SizedBox(width: 8),
                _buildTimingChip('Fade Out', profile.fadeOutMs),
                const SizedBox(width: 8),
                _buildTimingChip('Overlap', '${(profile.overlap * 100).toStringAsFixed(0)}%'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimingChip(String label, dynamic value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              color: FluxForgeTheme.textMuted,
              fontSize: 9,
            ),
          ),
          Text(
            value is int ? '${value}ms' : value.toString(),
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetButton(String label, SyncMode mode, int durationMs) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        side: BorderSide(color: _getSyncModeColor(mode)),
      ),
      onPressed: () => _testTransition(mode, durationMs),
      child: Text(
        label,
        style: TextStyle(
          color: _getSyncModeColor(mode),
          fontSize: 11,
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTIONS
  // ═══════════════════════════════════════════════════════════════════════════

  void _transitionToContext(String contextId, AleProvider ale) {
    if (_isTransitioning || contextId == _currentContextId) return;

    final fromContext = _currentContextId ?? 'None';
    final profile = _selectedTransitionId != null
        ? ale.profile?.transitions[_selectedTransitionId]
        : null;

    _startTransition(
      fromContext: fromContext,
      toContext: contextId,
      syncMode: profile?.syncMode ?? SyncMode.immediate,
      durationMs: (profile?.fadeInMs ?? 500) + (profile?.fadeOutMs ?? 500),
    );
  }

  void _testTransition(SyncMode mode, int durationMs) {
    final contexts = ['BASE', 'FREESPINS', 'BIGWIN', 'BONUS'];
    final fromContext = _currentContextId ?? 'BASE';
    var toContext = contexts[(contexts.indexOf(fromContext) + 1) % contexts.length];

    _startTransition(
      fromContext: fromContext,
      toContext: toContext,
      syncMode: mode,
      durationMs: durationMs,
    );
  }

  void _startTransition({
    required String fromContext,
    required String toContext,
    required SyncMode syncMode,
    required int durationMs,
  }) {
    setState(() {
      _previousContextId = fromContext;
      _currentContextId = toContext;
      _isTransitioning = true;
      _transitionProgress = 0.0;
    });

    // Animate transition
    final totalMs = durationMs > 0 ? durationMs : 500;
    const stepMs = 50;
    final steps = totalMs ~/ stepMs;
    int currentStep = 0;

    _transitionTimer?.cancel();
    _transitionTimer = Timer.periodic(Duration(milliseconds: stepMs), (timer) {
      currentStep++;
      setState(() {
        _transitionProgress = currentStep / steps;
      });

      if (currentStep >= steps) {
        timer.cancel();
        setState(() {
          _isTransitioning = false;
          _transitionProgress = 0.0;
        });

        // Record in history
        _transitionHistory.add(TransitionEvent(
          fromContext: fromContext,
          toContext: toContext,
          timestamp: DateTime.now(),
          syncMode: syncMode,
          durationMs: durationMs,
        ));
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  Color _getContextColor(String contextId) {
    final id = contextId.toUpperCase();
    return switch (id) {
      'BASE' => Colors.blue,
      'FREESPINS' || 'FREE_SPINS' => Colors.purple,
      'BONUS' => Colors.orange,
      'BIGWIN' || 'BIG_WIN' => Colors.amber,
      'JACKPOT' => Colors.red,
      'HOLDWIN' || 'HOLD_WIN' => Colors.green,
      'NONE' => FluxForgeTheme.textMuted,
      _ => Colors.cyan,
    };
  }

  Color _getSyncModeColor(SyncMode mode) {
    return switch (mode) {
      SyncMode.immediate => Colors.red,
      SyncMode.beat => Colors.green,
      SyncMode.bar => Colors.blue,
      SyncMode.phrase => Colors.purple,
      SyncMode.nextDownbeat => Colors.orange,
      SyncMode.custom => Colors.cyan,
    };
  }

  IconData _getSyncModeIcon(SyncMode mode) {
    return switch (mode) {
      SyncMode.immediate => Icons.flash_on,
      SyncMode.beat => Icons.music_note,
      SyncMode.bar => Icons.view_week,
      SyncMode.phrase => Icons.audiotrack,
      SyncMode.nextDownbeat => Icons.first_page,
      SyncMode.custom => Icons.tune,
    };
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CROSSFADE PAINTER
// ═══════════════════════════════════════════════════════════════════════════

class _CrossfadePainter extends CustomPainter {
  final double progress;
  final Color fromColor;
  final Color toColor;

  _CrossfadePainter({
    required this.progress,
    required this.fromColor,
    required this.toColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    // From curve (fade out)
    final fromPath = Path();
    fromPath.moveTo(0, size.height);
    for (double x = 0; x <= size.width; x += 2) {
      final t = x / size.width;
      final y = size.height * (1 - _easeOut(1 - t));
      fromPath.lineTo(x, y);
    }
    fromPath.lineTo(size.width, size.height);
    fromPath.close();

    paint.color = fromColor.withValues(alpha: 0.5);
    canvas.drawPath(fromPath, paint);

    // To curve (fade in)
    final toPath = Path();
    toPath.moveTo(0, size.height);
    for (double x = 0; x <= size.width; x += 2) {
      final t = x / size.width;
      final y = size.height * (1 - _easeIn(t));
      toPath.lineTo(x, y);
    }
    toPath.lineTo(size.width, size.height);
    toPath.close();

    paint.color = toColor.withValues(alpha: 0.5);
    canvas.drawPath(toPath, paint);

    // Progress line
    if (progress > 0) {
      paint.color = Colors.white;
      paint.style = PaintingStyle.stroke;
      paint.strokeWidth = 2;
      final progressX = progress * size.width;
      canvas.drawLine(
        Offset(progressX, 0),
        Offset(progressX, size.height),
        paint,
      );
    }

    // Labels
    final textStyle = TextStyle(
      color: FluxForgeTheme.textMuted,
      fontSize: 8,
    );

    TextPainter(
      text: TextSpan(text: 'OUT', style: textStyle.copyWith(color: fromColor)),
      textDirection: TextDirection.ltr,
    )
      ..layout()
      ..paint(canvas, const Offset(4, 2));

    TextPainter(
      text: TextSpan(text: 'IN', style: textStyle.copyWith(color: toColor)),
      textDirection: TextDirection.ltr,
    )
      ..layout()
      ..paint(canvas, Offset(size.width - 16, 2));
  }

  double _easeIn(double t) => t * t;
  double _easeOut(double t) => 1 - (1 - t) * (1 - t);

  @override
  bool shouldRepaint(covariant _CrossfadePainter oldDelegate) {
    return progress != oldDelegate.progress ||
        fromColor != oldDelegate.fromColor ||
        toColor != oldDelegate.toColor;
  }
}
