// RTPC Live Value Debugger Panel
//
// Real-time visualization and editing of RTPC parameters:
// - Live value display with history graph
// - Parameter editing via sliders/knobs
// - Binding visualization (what parameters are affected)
// - Value history (sparklines)
// - Curve preview

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/middleware_models.dart';
import '../../theme/fluxforge_theme.dart';

class RtpcDebuggerPanel extends StatefulWidget {
  const RtpcDebuggerPanel({super.key});

  @override
  State<RtpcDebuggerPanel> createState() => _RtpcDebuggerPanelState();
}

class _RtpcDebuggerPanelState extends State<RtpcDebuggerPanel> {
  // RTPC definitions
  final List<RtpcDefinition> _rtpcs = [];

  // Live values
  final Map<int, double> _liveValues = {};

  // Value history for sparklines (last 100 samples)
  final Map<int, List<double>> _valueHistory = {};
  static const int _historyLength = 100;

  // Bindings
  final List<RtpcBinding> _bindings = [];

  // UI state
  int? _selectedRtpcId;
  bool _isRecording = true;
  bool _showBindings = true;
  String _searchQuery = '';

  // Descriptions (stored separately since RtpcDefinition doesn't have description field)
  final Map<int, String> _rtpcDescriptions = {};

  Timer? _updateTimer;
  final math.Random _rng = math.Random();

  @override
  void initState() {
    super.initState();
    _initDemoData();
    _startUpdateTimer();
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  void _initDemoData() {
    // Create slot-focused RTPC definitions
    _rtpcs.addAll([
      const RtpcDefinition(
        id: 1,
        name: 'WinAmount',
        min: 0,
        max: 10000,
        defaultValue: 0,
      ),
      const RtpcDefinition(
        id: 2,
        name: 'BetMultiplier',
        min: 1,
        max: 100,
        defaultValue: 1,
      ),
      const RtpcDefinition(
        id: 3,
        name: 'ReelSpeed',
        min: 0,
        max: 1,
        defaultValue: 0.5,
      ),
      const RtpcDefinition(
        id: 4,
        name: 'NearWinProximity',
        min: 0,
        max: 1,
        defaultValue: 0,
      ),
      const RtpcDefinition(
        id: 5,
        name: 'FeatureProgress',
        min: 0,
        max: 100,
        defaultValue: 0,
      ),
      const RtpcDefinition(
        id: 6,
        name: 'Tension',
        min: 0,
        max: 1,
        defaultValue: 0,
      ),
      const RtpcDefinition(
        id: 7,
        name: 'ComboMultiplier',
        min: 1,
        max: 20,
        defaultValue: 1,
      ),
      const RtpcDefinition(
        id: 8,
        name: 'JackpotTier',
        min: 0,
        max: 4,
        defaultValue: 0,
      ),
    ]);

    // Store descriptions separately for UI
    _rtpcDescriptions.addAll({
      1: 'Current win amount in credits',
      2: 'Bet multiplier level',
      3: 'Reel spin velocity (0=slow, 1=turbo)',
      4: 'How close to a big win (anticipation)',
      5: 'Progress through bonus feature (%)',
      6: 'Global tension level for music',
      7: 'Cascading wins combo multiplier',
      8: 'Current jackpot tier (0=none, 4=grand)',
    });

    // Initialize live values and history
    for (final rtpc in _rtpcs) {
      _liveValues[rtpc.id] = rtpc.defaultValue;
      _valueHistory[rtpc.id] = List.filled(_historyLength, rtpc.defaultValue);
    }

    // Create demo bindings
    _bindings.addAll([
      RtpcBinding.linear(1, 1, RtpcTargetParameter.volume), // WinAmount → Volume
      RtpcBinding.linear(2, 4, RtpcTargetParameter.lowPassFilter), // NearWin → LPF
      RtpcBinding.linear(3, 6, RtpcTargetParameter.pitch), // Tension → Pitch
      RtpcBinding.forBus(4, 3, RtpcTargetParameter.volume, 1), // ReelSpeed → Bus1 Vol
    ]);
  }

  void _startUpdateTimer() {
    _updateTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (mounted && _isRecording) {
        _updateSimulatedValues();
        setState(() {});
      }
    });
  }

  void _updateSimulatedValues() {
    // Simulate subtle value changes for demo
    for (final rtpc in _rtpcs) {
      final current = _liveValues[rtpc.id] ?? rtpc.defaultValue;

      // Small random walk
      double change = (_rng.nextDouble() - 0.5) * (rtpc.max - rtpc.min) * 0.02;
      double newValue = (current + change).clamp(rtpc.min, rtpc.max);

      _liveValues[rtpc.id] = newValue;

      // Update history
      final history = _valueHistory[rtpc.id] ?? [];
      if (history.length >= _historyLength) {
        history.removeAt(0);
      }
      history.add(newValue);
      _valueHistory[rtpc.id] = history;
    }
  }

  void _setRtpcValue(int rtpcId, double value) {
    final rtpc = _rtpcs.firstWhere((r) => r.id == rtpcId);
    _liveValues[rtpcId] = value.clamp(rtpc.min, rtpc.max);

    // Update history
    final history = _valueHistory[rtpcId] ?? [];
    if (history.length >= _historyLength) {
      history.removeAt(0);
    }
    history.add(_liveValues[rtpcId]!);
    _valueHistory[rtpcId] = history;

    setState(() {});
  }

  void _resetRtpc(int rtpcId) {
    final rtpc = _rtpcs.firstWhere((r) => r.id == rtpcId);
    _setRtpcValue(rtpcId, rtpc.defaultValue);
  }

  void _resetAllRtpcs() {
    for (final rtpc in _rtpcs) {
      _liveValues[rtpc.id] = rtpc.defaultValue;
      _valueHistory[rtpc.id] = List.filled(_historyLength, rtpc.defaultValue);
    }
    setState(() {});
  }

  List<RtpcDefinition> get _filteredRtpcs {
    if (_searchQuery.isEmpty) return _rtpcs;
    return _rtpcs
        .where((r) => r.name.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();
  }

  List<RtpcBinding> _getBindingsForRtpc(int rtpcId) {
    return _bindings.where((b) => b.rtpcId == rtpcId).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: FluxForgeTheme.bgDeep,
      child: Column(
        children: [
          // Toolbar
          _buildToolbar(),

          // Main content
          Expanded(
            child: Row(
              children: [
                // RTPC list
                SizedBox(
                  width: 280,
                  child: _buildRtpcList(),
                ),

                // Divider
                Container(width: 1, color: FluxForgeTheme.borderSubtle),

                // Details panel
                Expanded(
                  child: _selectedRtpcId != null
                      ? _buildRtpcDetails(_rtpcs.firstWhere(
                          (r) => r.id == _selectedRtpcId,
                        ))
                      : _buildEmptyState(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        border: Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle)),
      ),
      child: Row(
        children: [
          // Title
          const Icon(Icons.tune, size: 14, color: FluxForgeTheme.accentOrange),
          const SizedBox(width: 8),
          const Text(
            'RTPC LIVE DEBUGGER',
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),

          const SizedBox(width: 16),

          // Search
          Expanded(
            child: Container(
              height: 24,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: FluxForgeTheme.bgDeep,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: FluxForgeTheme.borderSubtle),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, size: 12, color: FluxForgeTheme.textSecondary),
                  const SizedBox(width: 4),
                  Expanded(
                    child: TextField(
                      style: const TextStyle(
                        color: FluxForgeTheme.textPrimary,
                        fontSize: 10,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Search parameters...',
                        hintStyle: TextStyle(
                          color: FluxForgeTheme.textSecondary,
                          fontSize: 10,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onChanged: (v) => setState(() => _searchQuery = v),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 16),

          // Recording toggle
          GestureDetector(
            onTap: () => setState(() => _isRecording = !_isRecording),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _isRecording
                    ? FluxForgeTheme.accentRed.withValues(alpha: 0.2)
                    : FluxForgeTheme.bgDeep,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: _isRecording
                      ? FluxForgeTheme.accentRed
                      : FluxForgeTheme.borderSubtle,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _isRecording ? Icons.fiber_manual_record : Icons.pause,
                    size: 10,
                    color: _isRecording
                        ? FluxForgeTheme.accentRed
                        : FluxForgeTheme.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _isRecording ? 'LIVE' : 'PAUSED',
                    style: TextStyle(
                      color: _isRecording
                          ? FluxForgeTheme.accentRed
                          : FluxForgeTheme.textSecondary,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 8),

          // Show bindings toggle
          GestureDetector(
            onTap: () => setState(() => _showBindings = !_showBindings),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _showBindings
                    ? FluxForgeTheme.accentBlue.withValues(alpha: 0.2)
                    : FluxForgeTheme.bgDeep,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: _showBindings
                      ? FluxForgeTheme.accentBlue
                      : FluxForgeTheme.borderSubtle,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.link,
                    size: 10,
                    color: _showBindings
                        ? FluxForgeTheme.accentBlue
                        : FluxForgeTheme.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'BINDINGS',
                    style: TextStyle(
                      color: _showBindings
                          ? FluxForgeTheme.accentBlue
                          : FluxForgeTheme.textSecondary,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 8),

          // Reset all button
          GestureDetector(
            onTap: _resetAllRtpcs,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: FluxForgeTheme.bgDeep,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: FluxForgeTheme.borderSubtle),
              ),
              child: const Row(
                children: [
                  Icon(Icons.restart_alt, size: 10, color: FluxForgeTheme.textSecondary),
                  SizedBox(width: 4),
                  Text(
                    'RESET ALL',
                    style: TextStyle(
                      color: FluxForgeTheme.textSecondary,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRtpcList() {
    final rtpcs = _filteredRtpcs;

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgMid.withValues(alpha: 0.5),
            border: Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle)),
          ),
          child: Row(
            children: [
              const Text(
                'PARAMETER',
                style: TextStyle(
                  color: FluxForgeTheme.textSecondary,
                  fontSize: 8,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              const Text(
                'VALUE',
                style: TextStyle(
                  color: FluxForgeTheme.textSecondary,
                  fontSize: 8,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(width: 60),
              const Text(
                'HISTORY',
                style: TextStyle(
                  color: FluxForgeTheme.textSecondary,
                  fontSize: 8,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),

        // List
        Expanded(
          child: ListView.builder(
            itemCount: rtpcs.length,
            itemBuilder: (context, index) {
              final rtpc = rtpcs[index];
              return _buildRtpcRow(rtpc);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRtpcRow(RtpcDefinition rtpc) {
    final isSelected = _selectedRtpcId == rtpc.id;
    final value = _liveValues[rtpc.id] ?? rtpc.defaultValue;
    final normalized = (value - rtpc.min) / (rtpc.max - rtpc.min);
    final history = _valueHistory[rtpc.id] ?? [];
    final bindings = _getBindingsForRtpc(rtpc.id);

    return GestureDetector(
      onTap: () => setState(() => _selectedRtpcId = rtpc.id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? FluxForgeTheme.accentOrange.withValues(alpha: 0.1)
              : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: FluxForgeTheme.borderSubtle.withValues(alpha: 0.5),
            ),
            left: isSelected
                ? BorderSide(color: FluxForgeTheme.accentOrange, width: 2)
                : BorderSide.none,
          ),
        ),
        child: Row(
          children: [
            // Name and bindings indicator
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        rtpc.name,
                        style: TextStyle(
                          color: isSelected
                              ? FluxForgeTheme.accentOrange
                              : FluxForgeTheme.textPrimary,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (_showBindings && bindings.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: FluxForgeTheme.accentBlue.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: Text(
                            '${bindings.length}',
                            style: const TextStyle(
                              color: FluxForgeTheme.accentBlue,
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  // Mini slider
                  Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: FluxForgeTheme.bgDeep,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: normalized.clamp(0.0, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: _getValueColor(normalized),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Value display
            SizedBox(
              width: 60,
              child: Text(
                _formatValue(value, rtpc),
                style: const TextStyle(
                  color: FluxForgeTheme.textPrimary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                ),
                textAlign: TextAlign.right,
              ),
            ),

            const SizedBox(width: 8),

            // Sparkline
            SizedBox(
              width: 60,
              height: 20,
              child: CustomPaint(
                painter: _SparklinePainter(
                  values: history,
                  minValue: rtpc.min,
                  maxValue: rtpc.max,
                  color: _getValueColor(normalized),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getValueColor(double normalized) {
    if (normalized < 0.3) return FluxForgeTheme.accentGreen;
    if (normalized < 0.7) return FluxForgeTheme.accentYellow;
    return FluxForgeTheme.accentOrange;
  }

  String _formatValue(double value, RtpcDefinition rtpc) {
    if (rtpc.max - rtpc.min >= 100) {
      return value.toStringAsFixed(0);
    } else if (rtpc.max - rtpc.min >= 10) {
      return value.toStringAsFixed(1);
    } else {
      return value.toStringAsFixed(2);
    }
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.tune, size: 32, color: FluxForgeTheme.textSecondary),
          SizedBox(height: 8),
          Text(
            'Select a parameter to view details',
            style: TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRtpcDetails(RtpcDefinition rtpc) {
    final value = _liveValues[rtpc.id] ?? rtpc.defaultValue;
    final normalized = (value - rtpc.min) / (rtpc.max - rtpc.min);
    final bindings = _getBindingsForRtpc(rtpc.id);
    final history = _valueHistory[rtpc.id] ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: FluxForgeTheme.accentOrange.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(
                  Icons.tune,
                  size: 20,
                  color: FluxForgeTheme.accentOrange,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rtpc.name,
                    style: const TextStyle(
                      color: FluxForgeTheme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (_rtpcDescriptions.containsKey(rtpc.id))
                    Text(
                      _rtpcDescriptions[rtpc.id]!,
                      style: const TextStyle(
                        color: FluxForgeTheme.textSecondary,
                        fontSize: 10,
                      ),
                    ),
                ],
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => _resetRtpc(rtpc.id),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.bgDeep,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: FluxForgeTheme.borderSubtle),
                  ),
                  child: const Text(
                    'RESET',
                    style: TextStyle(
                      color: FluxForgeTheme.textSecondary,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Large value display with slider
          _buildSection('VALUE CONTROL', [
            Row(
              children: [
                // Large value readout
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.bgDeepest,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: FluxForgeTheme.borderSubtle),
                  ),
                  child: Text(
                    _formatValue(value, rtpc),
                    style: TextStyle(
                      color: _getValueColor(normalized),
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // Range info
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Min: ${rtpc.min}',
                      style: const TextStyle(
                        color: FluxForgeTheme.textSecondary,
                        fontSize: 9,
                      ),
                    ),
                    Text(
                      'Max: ${rtpc.max}',
                      style: const TextStyle(
                        color: FluxForgeTheme.textSecondary,
                        fontSize: 9,
                      ),
                    ),
                    Text(
                      'Default: ${rtpc.defaultValue}',
                      style: const TextStyle(
                        color: FluxForgeTheme.textSecondary,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Slider
            SliderTheme(
              data: SliderThemeData(
                trackHeight: 8,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                activeTrackColor: _getValueColor(normalized),
                inactiveTrackColor: FluxForgeTheme.bgDeep,
                thumbColor: _getValueColor(normalized),
              ),
              child: Slider(
                value: value,
                min: rtpc.min,
                max: rtpc.max,
                onChanged: (v) => _setRtpcValue(rtpc.id, v),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  rtpc.min.toString(),
                  style: const TextStyle(
                    color: FluxForgeTheme.textSecondary,
                    fontSize: 9,
                  ),
                ),
                Text(
                  rtpc.max.toString(),
                  style: const TextStyle(
                    color: FluxForgeTheme.textSecondary,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ]),

          const SizedBox(height: 16),

          // History graph
          _buildSection('VALUE HISTORY', [
            SizedBox(
              height: 80,
              child: CustomPaint(
                painter: _HistoryGraphPainter(
                  values: history,
                  minValue: rtpc.min,
                  maxValue: rtpc.max,
                  color: _getValueColor(normalized),
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ]),

          const SizedBox(height: 16),

          // Bindings
          if (_showBindings)
            _buildSection('PARAMETER BINDINGS (${bindings.length})', [
              if (bindings.isEmpty)
                const Text(
                  'No bindings configured',
                  style: TextStyle(
                    color: FluxForgeTheme.textSecondary,
                    fontSize: 10,
                    fontStyle: FontStyle.italic,
                  ),
                )
              else
                ...bindings.map((b) => _buildBindingRow(b, rtpc)),
            ]),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: FluxForgeTheme.textSecondary,
            fontSize: 9,
            fontWeight: FontWeight.w600,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgMid,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: FluxForgeTheme.borderSubtle),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _buildBindingRow(RtpcBinding binding, RtpcDefinition rtpc) {
    final value = _liveValues[rtpc.id] ?? rtpc.defaultValue;
    final outputValue = binding.evaluate(value);
    final targetRange = binding.target.defaultRange;
    final outputNormalized =
        (outputValue - targetRange.$1) / (targetRange.$2 - targetRange.$1);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: binding.enabled
              ? FluxForgeTheme.accentBlue.withValues(alpha: 0.3)
              : FluxForgeTheme.borderSubtle,
        ),
      ),
      child: Row(
        children: [
          // Target icon
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: FluxForgeTheme.accentBlue.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(
              _getTargetIcon(binding.target),
              size: 14,
              color: FluxForgeTheme.accentBlue,
            ),
          ),
          const SizedBox(width: 8),

          // Target info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  binding.target.displayName,
                  style: const TextStyle(
                    color: FluxForgeTheme.textPrimary,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (binding.targetBusId != null)
                  Text(
                    'Bus: ${binding.targetBusId}',
                    style: const TextStyle(
                      color: FluxForgeTheme.textSecondary,
                      fontSize: 8,
                    ),
                  ),
              ],
            ),
          ),

          // Arrow
          const Icon(
            Icons.arrow_forward,
            size: 12,
            color: FluxForgeTheme.textSecondary,
          ),

          const SizedBox(width: 8),

          // Output value
          SizedBox(
            width: 60,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  outputValue.toStringAsFixed(2),
                  style: const TextStyle(
                    color: FluxForgeTheme.accentCyan,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 2),
                // Mini output meter
                Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.bgDeep,
                    borderRadius: BorderRadius.circular(1),
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: outputNormalized.clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: FluxForgeTheme.accentCyan,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _getTargetIcon(RtpcTargetParameter target) {
    switch (target) {
      case RtpcTargetParameter.volume:
        return Icons.volume_up;
      case RtpcTargetParameter.pitch:
        return Icons.music_note;
      case RtpcTargetParameter.lowPassFilter:
        return Icons.arrow_downward;
      case RtpcTargetParameter.highPassFilter:
        return Icons.arrow_upward;
      case RtpcTargetParameter.pan:
        return Icons.compare_arrows;
      case RtpcTargetParameter.busVolume:
        return Icons.speaker;
      case RtpcTargetParameter.reverbSend:
        return Icons.blur_on;
      case RtpcTargetParameter.delaySend:
        return Icons.timer;
      case RtpcTargetParameter.width:
        return Icons.unfold_more;
      case RtpcTargetParameter.playbackRate:
        return Icons.speed;
    }
  }
}

/// Sparkline painter for compact value history
class _SparklinePainter extends CustomPainter {
  final List<double> values;
  final double minValue;
  final double maxValue;
  final Color color;

  _SparklinePainter({
    required this.values,
    required this.minValue,
    required this.maxValue,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final path = Path();
    final range = maxValue - minValue;

    for (int i = 0; i < values.length; i++) {
      final x = size.width * i / values.length;
      final normalized = range > 0 ? (values[i] - minValue) / range : 0.5;
      final y = size.height * (1 - normalized.clamp(0.0, 1.0));

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) => true;
}

/// Large history graph painter
class _HistoryGraphPainter extends CustomPainter {
  final List<double> values;
  final double minValue;
  final double maxValue;
  final Color color;

  _HistoryGraphPainter({
    required this.values,
    required this.minValue,
    required this.maxValue,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    // Draw grid
    final gridPaint = Paint()
      ..color = FluxForgeTheme.borderSubtle.withValues(alpha: 0.3)
      ..strokeWidth = 0.5;

    // Horizontal lines
    for (int i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Fill
    final fillPath = Path();
    final range = maxValue - minValue;

    fillPath.moveTo(0, size.height);
    for (int i = 0; i < values.length; i++) {
      final x = size.width * i / values.length;
      final normalized = range > 0 ? (values[i] - minValue) / range : 0.5;
      final y = size.height * (1 - normalized.clamp(0.0, 1.0));
      fillPath.lineTo(x, y);
    }
    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.2)
      ..style = PaintingStyle.fill;
    canvas.drawPath(fillPath, fillPaint);

    // Line
    final linePath = Path();
    for (int i = 0; i < values.length; i++) {
      final x = size.width * i / values.length;
      final normalized = range > 0 ? (values[i] - minValue) / range : 0.5;
      final y = size.height * (1 - normalized.clamp(0.0, 1.0));

      if (i == 0) {
        linePath.moveTo(x, y);
      } else {
        linePath.lineTo(x, y);
      }
    }

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawPath(linePath, linePaint);

    // Current value dot
    if (values.isNotEmpty) {
      final lastNormalized =
          range > 0 ? (values.last - minValue) / range : 0.5;
      final lastY = size.height * (1 - lastNormalized.clamp(0.0, 1.0));

      final dotPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(size.width, lastY), 4, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _HistoryGraphPainter oldDelegate) => true;
}
