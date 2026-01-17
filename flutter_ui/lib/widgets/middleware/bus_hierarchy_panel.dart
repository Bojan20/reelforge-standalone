// Bus Hierarchy Panel
//
// Visual editor for audio bus hierarchy:
// - Tree view of buses
// - Volume/Pan/Mute/Solo controls
// - Effects chain per bus
// - Metering visualization
// - Real-time spectrum analyzer per bus

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/advanced_middleware_models.dart';
import '../../theme/fluxforge_theme.dart';
import '../spectrum/spectrum_analyzer.dart';

class BusHierarchyPanel extends StatefulWidget {
  final BusHierarchy? hierarchy;

  const BusHierarchyPanel({super.key, this.hierarchy});

  @override
  State<BusHierarchyPanel> createState() => _BusHierarchyPanelState();
}

class _BusHierarchyPanelState extends State<BusHierarchyPanel>
    with SingleTickerProviderStateMixin {
  late final BusHierarchy _hierarchy;
  int? _selectedBusId;
  final Set<int> _expandedBuses = {0}; // Master expanded by default

  // Spectrum analyzer state
  bool _showSpectrum = false;
  SpectrumMode _spectrumMode = SpectrumMode.fill;
  AnalyzerSource _analyzerSource = AnalyzerSource.post;
  FftSizeOption _fftSize = FftSizeOption.fft4096;
  bool _spectrumFrozen = false;

  // Simulated spectrum data (replace with real FFT data from Rust)
  late AnimationController _spectrumAnimController;
  List<double> _spectrumData = List.filled(512, 0.0);
  List<double> _peakHoldData = List.filled(512, 0.0);
  Timer? _spectrumTimer;
  final math.Random _rng = math.Random();

  @override
  void initState() {
    super.initState();
    _hierarchy = widget.hierarchy ?? BusHierarchy();
    _spectrumAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16), // 60fps
    );
    _startSpectrumSimulation();
  }

  @override
  void dispose() {
    _spectrumAnimController.dispose();
    _spectrumTimer?.cancel();
    super.dispose();
  }

  void _startSpectrumSimulation() {
    // Simulate spectrum data updates at 60fps
    _spectrumTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (mounted) {
        if (!_spectrumFrozen) {
          _updateSimulatedSpectrum();
        }
        _updateBusMeters();
        setState(() {});
      }
    });
  }

  // Peak hold values for metering
  final Map<int, double> _peakHoldL = {};
  final Map<int, double> _peakHoldR = {};

  void _updateBusMeters() {
    // Update metering for all buses with simulated data
    void updateBusMeter(AudioBus bus) {
      // Simulate audio activity (random with decay)
      final activity = _rng.nextDouble() * 0.3 + (bus.volume * 0.7);

      // Peak meters - faster attack, slower release
      final targetPeakL = activity * (0.8 + _rng.nextDouble() * 0.2);
      final targetPeakR = activity * (0.8 + _rng.nextDouble() * 0.2);

      bus.peakL = bus.peakL < targetPeakL
          ? targetPeakL // Fast attack
          : bus.peakL * 0.95 + targetPeakL * 0.05; // Slow release
      bus.peakR = bus.peakR < targetPeakR
          ? targetPeakR
          : bus.peakR * 0.95 + targetPeakR * 0.05;

      // RMS - smoother averaging
      bus.rmsL = bus.rmsL * 0.9 + (activity * 0.7) * 0.1;
      bus.rmsR = bus.rmsR * 0.9 + (activity * 0.7) * 0.1;

      // LUFS - very slow integration
      final lufsTarget = -23.0 + (activity * 23.0); // -23 to 0 LUFS
      bus.lufs = bus.lufs * 0.98 + lufsTarget * 0.02;

      // Update peak hold
      _peakHoldL[bus.busId] = (_peakHoldL[bus.busId] ?? 0.0) < bus.peakL
          ? bus.peakL
          : ((_peakHoldL[bus.busId] ?? 0.0) - 0.005).clamp(0.0, 1.0);
      _peakHoldR[bus.busId] = (_peakHoldR[bus.busId] ?? 0.0) < bus.peakR
          ? bus.peakR
          : ((_peakHoldR[bus.busId] ?? 0.0) - 0.005).clamp(0.0, 1.0);

      // Recurse to children
      for (final childId in bus.childBusIds) {
        final child = _hierarchy.getBus(childId);
        if (child != null) {
          updateBusMeter(child);
        }
      }
    }

    updateBusMeter(_hierarchy.master);
  }

  void _updateSimulatedSpectrum() {
    // Generate realistic-looking spectrum (pink noise slope + some peaks)
    for (int i = 0; i < _spectrumData.length; i++) {
      final freq = 20.0 * math.pow(1000.0, i / _spectrumData.length);

      // Pink noise slope (-3dB/octave)
      final baseLevel = -20.0 - (math.log(freq / 20.0) / math.ln2) * 3.0;

      // Add some musical peaks around typical frequencies
      double peak = 0.0;
      if (freq > 80 && freq < 120) peak = 6.0; // Bass fundamental
      if (freq > 400 && freq < 600) peak = 3.0; // Midrange
      if (freq > 2000 && freq < 4000) peak = 4.0; // Presence

      // Random modulation
      final noise = (_rng.nextDouble() - 0.5) * 12.0;

      // Smoothing with previous value
      final targetDb = (baseLevel + peak + noise).clamp(-90.0, 0.0);
      _spectrumData[i] = _spectrumData[i] * 0.7 + targetDb * 0.3;

      // Update peak hold with decay
      if (_spectrumData[i] > _peakHoldData[i]) {
        _peakHoldData[i] = _spectrumData[i];
      } else {
        _peakHoldData[i] -= 0.5; // Decay rate
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: FluxForgeTheme.bgDeep,
      child: Row(
        children: [
          // Bus tree
          SizedBox(
            width: 200,
            child: _buildBusTree(),
          ),

          // Divider
          Container(
            width: 1,
            color: FluxForgeTheme.borderSubtle,
          ),

          // Selected bus details
          Expanded(
            child: _selectedBusId != null
                ? _buildBusDetails(_hierarchy.getBus(_selectedBusId!)!)
                : _buildEmptyState(),
          ),
        ],
      ),
    );
  }

  Widget _buildBusTree() {
    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgMid,
            border: Border(
              bottom: BorderSide(color: FluxForgeTheme.borderSubtle),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.account_tree,
                color: FluxForgeTheme.accentBlue,
                size: 14,
              ),
              const SizedBox(width: 8),
              const Text(
                'BUS HIERARCHY',
                style: TextStyle(
                  color: FluxForgeTheme.textPrimary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),

        // Tree
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(8),
            children: [
              _buildBusNode(_hierarchy.master, 0),
            ],
          ),
        ),

        // Add bus button
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: FluxForgeTheme.borderSubtle),
            ),
          ),
          child: GestureDetector(
            onTap: _addBus,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: FluxForgeTheme.accentBlue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: FluxForgeTheme.accentBlue.withValues(alpha: 0.3),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.add,
                    size: 12,
                    color: FluxForgeTheme.accentBlue,
                  ),
                  SizedBox(width: 4),
                  Text(
                    'Add Bus',
                    style: TextStyle(
                      color: FluxForgeTheme.accentBlue,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBusNode(AudioBus bus, int depth) {
    final isExpanded = _expandedBuses.contains(bus.busId);
    final isSelected = _selectedBusId == bus.busId;
    final hasChildren = bus.childBusIds.isNotEmpty;
    final effectiveVolume = _hierarchy.getEffectiveVolume(bus.busId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => _selectedBusId = bus.busId),
          child: Container(
            margin: EdgeInsets.only(left: depth * 12.0),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: isSelected
                  ? FluxForgeTheme.accentBlue.withValues(alpha: 0.2)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
              border: isSelected
                  ? Border.all(color: FluxForgeTheme.accentBlue)
                  : null,
            ),
            child: Row(
              children: [
                // Expand/collapse button
                if (hasChildren)
                  GestureDetector(
                    onTap: () => setState(() {
                      if (isExpanded) {
                        _expandedBuses.remove(bus.busId);
                      } else {
                        _expandedBuses.add(bus.busId);
                      }
                    }),
                    child: Icon(
                      isExpanded ? Icons.expand_more : Icons.chevron_right,
                      size: 14,
                      color: FluxForgeTheme.textSecondary,
                    ),
                  )
                else
                  const SizedBox(width: 14),

                const SizedBox(width: 4),

                // Bus icon
                Icon(
                  bus.parentBusId == null
                      ? Icons.speaker
                      : Icons.volume_up,
                  size: 12,
                  color: bus.mute
                      ? FluxForgeTheme.textSecondary
                      : FluxForgeTheme.accentGreen,
                ),
                const SizedBox(width: 6),

                // Bus name
                Expanded(
                  child: Text(
                    bus.name,
                    style: TextStyle(
                      color: bus.mute
                          ? FluxForgeTheme.textSecondary
                          : FluxForgeTheme.textPrimary,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

                // Mini meter
                _buildMiniMeter(effectiveVolume * bus.volume),

                // Mute indicator
                if (bus.mute)
                  Container(
                    margin: const EdgeInsets.only(left: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                    decoration: BoxDecoration(
                      color: FluxForgeTheme.accentRed.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: const Text(
                      'M',
                      style: TextStyle(
                        color: FluxForgeTheme.accentRed,
                        fontSize: 7,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),

                // Solo indicator
                if (bus.solo)
                  Container(
                    margin: const EdgeInsets.only(left: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                    decoration: BoxDecoration(
                      color: FluxForgeTheme.accentYellow.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: const Text(
                      'S',
                      style: TextStyle(
                        color: FluxForgeTheme.accentYellow,
                        fontSize: 7,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),

        // Children
        if (isExpanded)
          ...bus.childBusIds.map((childId) {
            final child = _hierarchy.getBus(childId);
            if (child == null) return const SizedBox.shrink();
            return _buildBusNode(child, depth + 1);
          }),
      ],
    );
  }

  Widget _buildMiniMeter(double value) {
    return Container(
      width: 20,
      height: 6,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(1),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: value.clamp(0.0, 1.0),
        child: Container(
          decoration: BoxDecoration(
            color: value > 0.9
                ? FluxForgeTheme.accentRed
                : value > 0.7
                    ? FluxForgeTheme.accentOrange
                    : FluxForgeTheme.accentGreen,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Text(
        'Select a bus to edit',
        style: TextStyle(
          color: FluxForgeTheme.textSecondary,
          fontSize: 11,
        ),
      ),
    );
  }

  Widget _buildBusDetails(AudioBus bus) {
    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgMid,
            border: Border(
              bottom: BorderSide(color: FluxForgeTheme.borderSubtle),
            ),
          ),
          child: Row(
            children: [
              Icon(
                bus.parentBusId == null ? Icons.speaker : Icons.volume_up,
                color: FluxForgeTheme.accentGreen,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                bus.name,
                style: const TextStyle(
                  color: FluxForgeTheme.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              // Delete button (not for master)
              if (bus.parentBusId != null)
                GestureDetector(
                  onTap: () => _deleteBus(bus.busId),
                  child: Icon(
                    Icons.delete_outline,
                    size: 16,
                    color: FluxForgeTheme.accentRed.withValues(alpha: 0.7),
                  ),
                ),
            ],
          ),
        ),

        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              // Volume/Pan section
              _buildSection('CHANNEL STRIP', [
                _buildVolumeSlider(bus),
                const SizedBox(height: 12),
                _buildPanSlider(bus),
                const SizedBox(height: 12),
                _buildMuteSoloButtons(bus),
              ]),

              const SizedBox(height: 16),

              // Pre-insert effects
              _buildSection('PRE-INSERT EFFECTS', [
                _buildEffectChain(bus.preInserts, true, bus),
              ]),

              const SizedBox(height: 16),

              // Post-insert effects
              _buildSection('POST-INSERT EFFECTS', [
                _buildEffectChain(bus.postInserts, false, bus),
              ]),

              const SizedBox(height: 16),

              // Metering
              _buildSection('METERING', [
                _buildMeters(bus),
              ]),

              const SizedBox(height: 16),

              // Spectrum Analyzer
              _buildSection('SPECTRUM ANALYZER', [
                _buildSpectrumAnalyzer(bus),
              ]),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSpectrumAnalyzer(AudioBus bus) {
    return Column(
      children: [
        // Toolbar row
        Row(
          children: [
            // Toggle button
            GestureDetector(
              onTap: () => setState(() => _showSpectrum = !_showSpectrum),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _showSpectrum
                      ? FluxForgeTheme.accentCyan.withValues(alpha: 0.2)
                      : FluxForgeTheme.bgDeep,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: _showSpectrum
                        ? FluxForgeTheme.accentCyan
                        : FluxForgeTheme.borderSubtle,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.show_chart,
                      size: 12,
                      color: _showSpectrum
                          ? FluxForgeTheme.accentCyan
                          : FluxForgeTheme.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _showSpectrum ? 'ON' : 'OFF',
                      style: TextStyle(
                        color: _showSpectrum
                            ? FluxForgeTheme.accentCyan
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

            // Mode selector
            if (_showSpectrum) ...[
              _buildModeChip('FILL', SpectrumMode.fill),
              _buildModeChip('LINE', SpectrumMode.line),
              _buildModeChip('BARS', SpectrumMode.bars),
              _buildModeChip('BOTH', SpectrumMode.both),
            ],

            const Spacer(),

            if (_showSpectrum) ...[
              // Freeze button
              GestureDetector(
                onTap: () => setState(() => _spectrumFrozen = !_spectrumFrozen),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: _spectrumFrozen
                        ? FluxForgeTheme.accentBlue.withValues(alpha: 0.2)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(
                    _spectrumFrozen ? Icons.pause : Icons.play_arrow,
                    size: 14,
                    color: _spectrumFrozen
                        ? FluxForgeTheme.accentBlue
                        : FluxForgeTheme.textSecondary,
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // Source selector
              _buildSourceDropdown(),
            ],
          ],
        ),

        // Spectrum display
        if (_showSpectrum) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 120,
            child: _buildSpectrumDisplay(bus),
          ),

          const SizedBox(height: 8),

          // FFT size & frequency range
          Row(
            children: [
              // FFT size
              Text(
                'FFT: ${_fftSize.size}',
                style: const TextStyle(
                  color: FluxForgeTheme.textSecondary,
                  fontSize: 8,
                ),
              ),
              const SizedBox(width: 8),
              // Frequency range slider (placeholder)
              Expanded(
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.bgDeep,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: 1.0,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            FluxForgeTheme.accentCyan,
                            FluxForgeTheme.accentPurple,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                '20Hz — 20kHz',
                style: TextStyle(
                  color: FluxForgeTheme.textSecondary,
                  fontSize: 8,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildModeChip(String label, SpectrumMode mode) {
    final isSelected = _spectrumMode == mode;
    return GestureDetector(
      onTap: () => setState(() => _spectrumMode = mode),
      child: Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: isSelected
              ? FluxForgeTheme.accentCyan.withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: isSelected
                ? FluxForgeTheme.accentCyan
                : FluxForgeTheme.borderSubtle,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected
                ? FluxForgeTheme.accentCyan
                : FluxForgeTheme.textSecondary,
            fontSize: 8,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildSourceDropdown() {
    return PopupMenuButton<AnalyzerSource>(
      initialValue: _analyzerSource,
      onSelected: (source) => setState(() => _analyzerSource = source),
      itemBuilder: (context) => [
        _buildSourceMenuItem(AnalyzerSource.pre, 'PRE'),
        _buildSourceMenuItem(AnalyzerSource.post, 'POST'),
        _buildSourceMenuItem(AnalyzerSource.delta, 'DELTA'),
        _buildSourceMenuItem(AnalyzerSource.sidechain, 'SC'),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgDeep,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: FluxForgeTheme.borderSubtle),
        ),
        child: Row(
          children: [
            Text(
              _getSourceLabel(_analyzerSource),
              style: const TextStyle(
                color: FluxForgeTheme.textPrimary,
                fontSize: 8,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 2),
            const Icon(
              Icons.arrow_drop_down,
              size: 12,
              color: FluxForgeTheme.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<AnalyzerSource> _buildSourceMenuItem(
      AnalyzerSource source, String label) {
    return PopupMenuItem(
      value: source,
      height: 28,
      child: Text(
        label,
        style: TextStyle(
          color: _analyzerSource == source
              ? FluxForgeTheme.accentCyan
              : FluxForgeTheme.textPrimary,
          fontSize: 10,
        ),
      ),
    );
  }

  String _getSourceLabel(AnalyzerSource source) {
    switch (source) {
      case AnalyzerSource.pre:
        return 'PRE';
      case AnalyzerSource.post:
        return 'POST';
      case AnalyzerSource.delta:
        return 'DELTA';
      case AnalyzerSource.sidechain:
        return 'SC';
    }
  }

  Widget _buildSpectrumDisplay(AudioBus bus) {
    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: CustomPaint(
          painter: _BusSpectrumPainter(
            spectrumData: _spectrumData,
            peakHoldData: _peakHoldData,
            mode: _spectrumMode,
            source: _analyzerSource,
            frozen: _spectrumFrozen,
          ),
          child: const SizedBox.expand(),
        ),
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
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgMid,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: FluxForgeTheme.borderSubtle),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildVolumeSlider(AudioBus bus) {
    return Row(
      children: [
        const SizedBox(
          width: 50,
          child: Text(
            'Volume',
            style: TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 10,
            ),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: FluxForgeTheme.accentGreen,
              inactiveTrackColor: FluxForgeTheme.bgDeep,
              thumbColor: FluxForgeTheme.accentGreen,
            ),
            child: Slider(
              value: bus.volume,
              onChanged: (v) => setState(() => bus.volume = v),
            ),
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            '${(bus.volume * 100).round()}%',
            style: const TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _buildPanSlider(AudioBus bus) {
    return Row(
      children: [
        const SizedBox(
          width: 50,
          child: Text(
            'Pan',
            style: TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 10,
            ),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: FluxForgeTheme.accentCyan,
              inactiveTrackColor: FluxForgeTheme.bgDeep,
              thumbColor: FluxForgeTheme.accentCyan,
            ),
            child: Slider(
              value: bus.pan,
              min: -1.0,
              max: 1.0,
              onChanged: (v) => setState(() => bus.pan = v),
            ),
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            bus.pan == 0
                ? 'C'
                : bus.pan < 0
                    ? 'L${(-bus.pan * 100).round()}'
                    : 'R${(bus.pan * 100).round()}',
            style: const TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _buildMuteSoloButtons(AudioBus bus) {
    return Row(
      children: [
        // Mute
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() => bus.mute = !bus.mute),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: bus.mute
                    ? FluxForgeTheme.accentRed.withValues(alpha: 0.2)
                    : FluxForgeTheme.bgDeep,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: bus.mute
                      ? FluxForgeTheme.accentRed
                      : FluxForgeTheme.borderSubtle,
                ),
              ),
              child: Center(
                child: Text(
                  'MUTE',
                  style: TextStyle(
                    color: bus.mute
                        ? FluxForgeTheme.accentRed
                        : FluxForgeTheme.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Solo
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() => bus.solo = !bus.solo),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: bus.solo
                    ? FluxForgeTheme.accentYellow.withValues(alpha: 0.2)
                    : FluxForgeTheme.bgDeep,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: bus.solo
                      ? FluxForgeTheme.accentYellow
                      : FluxForgeTheme.borderSubtle,
                ),
              ),
              child: Center(
                child: Text(
                  'SOLO',
                  style: TextStyle(
                    color: bus.solo
                        ? FluxForgeTheme.accentYellow
                        : FluxForgeTheme.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEffectChain(List<EffectSlot> effects, bool isPre, AudioBus bus) {
    return Column(
      children: [
        ...effects.map((effect) => _buildEffectSlot(effect, isPre, bus)),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => _addEffect(bus, isPre),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(
                color: FluxForgeTheme.borderSubtle,
                style: BorderStyle.solid,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.add,
                  size: 12,
                  color: FluxForgeTheme.textSecondary,
                ),
                const SizedBox(width: 4),
                Text(
                  'Add Effect',
                  style: TextStyle(
                    color: FluxForgeTheme.textSecondary,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEffectSlot(EffectSlot effect, bool isPre, AudioBus bus) {
    final color = _getEffectColor(effect.type);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: effect.bypass
            ? FluxForgeTheme.bgDeep.withValues(alpha: 0.5)
            : color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: effect.bypass
              ? FluxForgeTheme.borderSubtle
              : color.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          // Bypass button
          GestureDetector(
            onTap: () => setState(() => effect.bypass = !effect.bypass),
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: effect.bypass
                    ? FluxForgeTheme.bgDeep
                    : color,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.power_settings_new,
                size: 10,
                color: effect.bypass
                    ? FluxForgeTheme.textSecondary
                    : Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Effect name
          Expanded(
            child: Text(
              effect.type.name.toUpperCase(),
              style: TextStyle(
                color: effect.bypass
                    ? FluxForgeTheme.textSecondary
                    : color,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

          // Wet/Dry
          SizedBox(
            width: 60,
            child: Row(
              children: [
                Text(
                  'Wet',
                  style: TextStyle(
                    color: FluxForgeTheme.textSecondary,
                    fontSize: 8,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 2,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                      overlayShape: SliderComponentShape.noOverlay,
                      activeTrackColor: color,
                      inactiveTrackColor: FluxForgeTheme.bgDeep,
                      thumbColor: color,
                    ),
                    child: Slider(
                      value: effect.wetDry,
                      onChanged: (v) => setState(() => effect.wetDry = v),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Delete
          GestureDetector(
            onTap: () => setState(() {
              if (isPre) {
                bus.removePreInsert(effect.slotIndex);
              } else {
                bus.removePostInsert(effect.slotIndex);
              }
            }),
            child: Icon(
              Icons.close,
              size: 14,
              color: FluxForgeTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Color _getEffectColor(EffectType type) {
    switch (type) {
      case EffectType.reverb:
        return FluxForgeTheme.accentPurple;
      case EffectType.delay:
        return FluxForgeTheme.accentCyan;
      case EffectType.compressor:
        return FluxForgeTheme.accentOrange;
      case EffectType.limiter:
        return FluxForgeTheme.accentRed;
      case EffectType.eq:
        return FluxForgeTheme.accentBlue;
      case EffectType.lpf:
      case EffectType.hpf:
        return FluxForgeTheme.accentGreen;
      case EffectType.chorus:
        return FluxForgeTheme.accentPink;
      case EffectType.distortion:
        return FluxForgeTheme.accentYellow;
      case EffectType.widener:
        return FluxForgeTheme.accentCyan;
    }
  }

  Widget _buildMeters(AudioBus bus) {
    return Column(
      children: [
        // Peak meters with peak hold
        Row(
          children: [
            const SizedBox(
              width: 30,
              child: Text(
                'Peak',
                style: TextStyle(
                  color: FluxForgeTheme.textSecondary,
                  fontSize: 9,
                ),
              ),
            ),
            Expanded(
              child: _buildStereoMeter(
                bus.peakL,
                bus.peakR,
                peakHoldL: _peakHoldL[bus.busId],
                peakHoldR: _peakHoldR[bus.busId],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // RMS meters
        Row(
          children: [
            const SizedBox(
              width: 30,
              child: Text(
                'RMS',
                style: TextStyle(
                  color: FluxForgeTheme.textSecondary,
                  fontSize: 9,
                ),
              ),
            ),
            Expanded(child: _buildStereoMeter(bus.rmsL, bus.rmsR, isRms: true)),
          ],
        ),
        const SizedBox(height: 8),
        // LUFS
        Row(
          children: [
            const SizedBox(
              width: 30,
              child: Text(
                'LUFS',
                style: TextStyle(
                  color: FluxForgeTheme.textSecondary,
                  fontSize: 9,
                ),
              ),
            ),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: FluxForgeTheme.bgDeep,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  '${bus.lufs.toStringAsFixed(1)} LUFS',
                  style: const TextStyle(
                    color: FluxForgeTheme.textPrimary,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStereoMeter(
    double left,
    double right, {
    bool isRms = false,
    double? peakHoldL,
    double? peakHoldR,
  }) {
    return Row(
      children: [
        // L label
        const Text(
          'L',
          style: TextStyle(
            color: FluxForgeTheme.textSecondary,
            fontSize: 8,
          ),
        ),
        const SizedBox(width: 4),
        // Left meter
        Expanded(
          child: _buildMeterBar(left, isRms: isRms, peakHold: peakHoldL),
        ),
        const SizedBox(width: 8),
        // Right meter
        Expanded(
          child: _buildMeterBar(right, isRms: isRms, peakHold: peakHoldR),
        ),
        const SizedBox(width: 4),
        // R label
        const Text(
          'R',
          style: TextStyle(
            color: FluxForgeTheme.textSecondary,
            fontSize: 8,
          ),
        ),
      ],
    );
  }

  Widget _buildMeterBar(double value, {bool isRms = false, double? peakHold}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          height: 8,
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgDeep,
            borderRadius: BorderRadius.circular(2),
          ),
          child: Stack(
            children: [
              // Main meter fill
              FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: value.clamp(0.0, 1.0),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isRms
                          ? [FluxForgeTheme.accentGreen, FluxForgeTheme.accentGreen]
                          : [
                              FluxForgeTheme.accentGreen,
                              FluxForgeTheme.accentYellow,
                              FluxForgeTheme.accentRed,
                            ],
                      stops: isRms ? null : [0.0, 0.7, 1.0],
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Peak hold marker
              if (peakHold != null && peakHold > 0)
                Positioned(
                  left: (peakHold.clamp(0.0, 1.0) * constraints.maxWidth) - 2,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: 2,
                    decoration: BoxDecoration(
                      color: peakHold > 0.9
                          ? FluxForgeTheme.accentRed
                          : FluxForgeTheme.textPrimary,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
              // Clip indicator
              if (value > 0.98)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: 4,
                    decoration: BoxDecoration(
                      color: FluxForgeTheme.accentRed,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _addBus() {
    // Simple dialog to add bus
    showDialog(
      context: context,
      builder: (context) {
        String name = 'New Bus';
        int parentId = _selectedBusId ?? 0;

        return AlertDialog(
          backgroundColor: FluxForgeTheme.bgMid,
          title: const Text(
            'Add Bus',
            style: TextStyle(color: FluxForgeTheme.textPrimary),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Bus Name',
                  labelStyle: TextStyle(color: FluxForgeTheme.textSecondary),
                ),
                style: const TextStyle(color: FluxForgeTheme.textPrimary),
                onChanged: (v) => name = v,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final newId = DateTime.now().millisecondsSinceEpoch % 10000;
                _hierarchy.addBus(AudioBus(
                  busId: newId,
                  name: name,
                  parentBusId: parentId,
                ));
                setState(() {});
                Navigator.pop(context);
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  void _deleteBus(int busId) {
    setState(() {
      _hierarchy.removeBus(busId);
      if (_selectedBusId == busId) {
        _selectedBusId = null;
      }
    });
  }

  void _addEffect(AudioBus bus, bool isPre) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: FluxForgeTheme.bgMid,
          title: const Text(
            'Add Effect',
            style: TextStyle(color: FluxForgeTheme.textPrimary),
          ),
          content: SizedBox(
            width: 200,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: EffectType.values.map((type) {
                return ListTile(
                  dense: true,
                  leading: Icon(
                    _getEffectIcon(type),
                    color: _getEffectColor(type),
                    size: 16,
                  ),
                  title: Text(
                    type.name.toUpperCase(),
                    style: const TextStyle(
                      color: FluxForgeTheme.textPrimary,
                      fontSize: 11,
                    ),
                  ),
                  onTap: () {
                    setState(() {
                      final effect = EffectSlot(
                        slotIndex: isPre
                            ? bus.preInserts.length
                            : bus.postInserts.length,
                        type: type,
                      );
                      if (isPre) {
                        bus.addPreInsert(effect);
                      } else {
                        bus.addPostInsert(effect);
                      }
                    });
                    Navigator.pop(context);
                  },
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  IconData _getEffectIcon(EffectType type) {
    switch (type) {
      case EffectType.reverb:
        return Icons.waves;
      case EffectType.delay:
        return Icons.timer;
      case EffectType.compressor:
        return Icons.compress;
      case EffectType.limiter:
        return Icons.vertical_align_top;
      case EffectType.eq:
        return Icons.equalizer;
      case EffectType.lpf:
        return Icons.arrow_downward;
      case EffectType.hpf:
        return Icons.arrow_upward;
      case EffectType.chorus:
        return Icons.blur_on;
      case EffectType.distortion:
        return Icons.flash_on;
      case EffectType.widener:
        return Icons.unfold_more;
    }
  }
}

/// Custom painter for bus spectrum visualization
class _BusSpectrumPainter extends CustomPainter {
  final List<double> spectrumData;
  final List<double> peakHoldData;
  final SpectrumMode mode;
  final AnalyzerSource source;
  final bool frozen;

  _BusSpectrumPainter({
    required this.spectrumData,
    required this.peakHoldData,
    required this.mode,
    required this.source,
    required this.frozen,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (spectrumData.isEmpty) return;

    final minDb = -90.0;
    final maxDb = 0.0;
    final dbRange = maxDb - minDb;

    // Get color based on source
    final Color primaryColor;
    final Color secondaryColor;
    switch (source) {
      case AnalyzerSource.pre:
        primaryColor = FluxForgeTheme.accentGreen;
        secondaryColor = FluxForgeTheme.accentGreen.withValues(alpha: 0.3);
        break;
      case AnalyzerSource.post:
        primaryColor = FluxForgeTheme.accentCyan;
        secondaryColor = FluxForgeTheme.accentCyan.withValues(alpha: 0.3);
        break;
      case AnalyzerSource.delta:
        primaryColor = FluxForgeTheme.accentOrange;
        secondaryColor = FluxForgeTheme.accentOrange.withValues(alpha: 0.3);
        break;
      case AnalyzerSource.sidechain:
        primaryColor = FluxForgeTheme.accentPurple;
        secondaryColor = FluxForgeTheme.accentPurple.withValues(alpha: 0.3);
        break;
    }

    // Draw grid
    _drawGrid(canvas, size, minDb, maxDb);

    // Draw frozen indicator
    if (frozen) {
      final frozenPaint = Paint()
        ..color = FluxForgeTheme.accentBlue.withValues(alpha: 0.3)
        ..style = PaintingStyle.fill;
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), frozenPaint);
    }

    // Draw spectrum based on mode
    switch (mode) {
      case SpectrumMode.bars:
        _drawBars(canvas, size, minDb, dbRange, primaryColor, secondaryColor);
        break;
      case SpectrumMode.line:
        _drawLine(canvas, size, minDb, dbRange, primaryColor);
        _drawPeakHold(canvas, size, minDb, dbRange, primaryColor);
        break;
      case SpectrumMode.fill:
        _drawFill(canvas, size, minDb, dbRange, primaryColor, secondaryColor);
        _drawPeakHold(canvas, size, minDb, dbRange, primaryColor);
        break;
      case SpectrumMode.both:
        _drawFill(canvas, size, minDb, dbRange, primaryColor, secondaryColor);
        _drawLine(canvas, size, minDb, dbRange, primaryColor);
        _drawPeakHold(canvas, size, minDb, dbRange, primaryColor);
        break;
      case SpectrumMode.waterfall:
      case SpectrumMode.spectrogram:
        // Simplified - just draw fill for now
        _drawFill(canvas, size, minDb, dbRange, primaryColor, secondaryColor);
        break;
    }

    // Draw frequency labels
    _drawFrequencyLabels(canvas, size);
  }

  void _drawGrid(Canvas canvas, Size size, double minDb, double maxDb) {
    final gridPaint = Paint()
      ..color = FluxForgeTheme.borderSubtle.withValues(alpha: 0.3)
      ..strokeWidth = 0.5;

    // Horizontal dB lines
    for (double db = minDb; db <= maxDb; db += 10) {
      final y = size.height * (1 - (db - minDb) / (maxDb - minDb));
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Vertical frequency lines (log scale)
    final freqs = [100, 1000, 10000];
    for (final freq in freqs) {
      final x = size.width * (math.log(freq / 20) / math.log(20000 / 20));
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
  }

  void _drawBars(Canvas canvas, Size size, double minDb, double dbRange,
      Color primary, Color secondary) {
    final barCount = 64;
    final barWidth = size.width / barCount - 1;
    final samplesPerBar = spectrumData.length ~/ barCount;

    for (int i = 0; i < barCount; i++) {
      // Average samples for this bar
      double sum = 0;
      for (int j = 0; j < samplesPerBar; j++) {
        final idx = i * samplesPerBar + j;
        if (idx < spectrumData.length) {
          sum += spectrumData[idx];
        }
      }
      final db = sum / samplesPerBar;
      final normalizedHeight = ((db - minDb) / dbRange).clamp(0.0, 1.0);
      final barHeight = normalizedHeight * size.height;

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          i * (barWidth + 1),
          size.height - barHeight,
          barWidth,
          barHeight,
        ),
        const Radius.circular(1),
      );

      // Gradient fill
      final gradient = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [secondary, primary],
      );

      final paint = Paint()
        ..shader = gradient.createShader(rect.outerRect);

      canvas.drawRRect(rect, paint);
    }
  }

  void _drawLine(Canvas canvas, Size size, double minDb, double dbRange,
      Color color) {
    final path = Path();
    bool started = false;

    for (int i = 0; i < spectrumData.length; i++) {
      final x = size.width * i / spectrumData.length;
      final normalizedHeight =
          ((spectrumData[i] - minDb) / dbRange).clamp(0.0, 1.0);
      final y = size.height * (1 - normalizedHeight);

      if (!started) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
    }

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, paint);
  }

  void _drawFill(Canvas canvas, Size size, double minDb, double dbRange,
      Color primary, Color secondary) {
    final path = Path();
    path.moveTo(0, size.height);

    for (int i = 0; i < spectrumData.length; i++) {
      final x = size.width * i / spectrumData.length;
      final normalizedHeight =
          ((spectrumData[i] - minDb) / dbRange).clamp(0.0, 1.0);
      final y = size.height * (1 - normalizedHeight);
      path.lineTo(x, y);
    }

    path.lineTo(size.width, size.height);
    path.close();

    final gradient = LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: [secondary.withValues(alpha: 0.1), secondary],
    );

    final paint = Paint()
      ..shader = gradient.createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    canvas.drawPath(path, paint);
  }

  void _drawPeakHold(Canvas canvas, Size size, double minDb, double dbRange,
      Color color) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.8)
      ..strokeWidth = 1.0;

    for (int i = 0; i < peakHoldData.length - 1; i++) {
      final x1 = size.width * i / peakHoldData.length;
      final x2 = size.width * (i + 1) / peakHoldData.length;
      final y1 = size.height *
          (1 - ((peakHoldData[i] - minDb) / dbRange).clamp(0.0, 1.0));
      final y2 = size.height *
          (1 - ((peakHoldData[i + 1] - minDb) / dbRange).clamp(0.0, 1.0));

      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), paint);
    }
  }

  void _drawFrequencyLabels(Canvas canvas, Size size) {
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    final labels = ['100', '1k', '10k'];
    final freqs = [100.0, 1000.0, 10000.0];

    for (int i = 0; i < labels.length; i++) {
      final x = size.width * (math.log(freqs[i] / 20) / math.log(20000 / 20));

      textPainter.text = TextSpan(
        text: labels[i],
        style: TextStyle(
          color: FluxForgeTheme.textSecondary.withValues(alpha: 0.5),
          fontSize: 7,
        ),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(x - textPainter.width / 2, size.height - 10));
    }
  }

  @override
  bool shouldRepaint(covariant _BusSpectrumPainter oldDelegate) {
    return true; // Always repaint for animation
  }
}
