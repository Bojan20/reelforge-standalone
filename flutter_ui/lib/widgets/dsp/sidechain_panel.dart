/// Sidechain Selector Panel
///
/// Configure sidechain input for dynamics processors:
/// - Source selection (track, bus, external)
/// - Filter controls (HPF/LPF/BPF)
/// - Monitor (listen to key signal)
/// - Mix control

import 'package:flutter/material.dart';
import '../../src/rust/native_ffi.dart';

/// Sidechain source type
enum SidechainSource {
  internal(0, 'Internal'),
  track(1, 'Track'),
  bus(2, 'Bus'),
  external(3, 'External');

  final int value;
  final String label;
  const SidechainSource(this.value, this.label);
}

/// Sidechain filter mode
enum SidechainFilterMode {
  off(0, 'OFF'),
  highpass(1, 'HPF'),
  lowpass(2, 'LPF'),
  bandpass(3, 'BPF');

  final int value;
  final String label;
  const SidechainFilterMode(this.value, this.label);
}

/// Sidechain Panel Widget
class SidechainPanel extends StatefulWidget {
  final int processorId;
  final List<SidechainSourceInfo> availableSources;
  final VoidCallback? onSettingsChanged;

  const SidechainPanel({
    super.key,
    required this.processorId,
    this.availableSources = const [],
    this.onSettingsChanged,
  });

  @override
  State<SidechainPanel> createState() => _SidechainPanelState();
}

/// Info about an available sidechain source
class SidechainSourceInfo {
  final int id;
  final String name;
  final SidechainSource type;

  const SidechainSourceInfo({
    required this.id,
    required this.name,
    required this.type,
  });
}

class _SidechainPanelState extends State<SidechainPanel> {
  final _ffi = NativeFFI.instance;

  SidechainSource _source = SidechainSource.internal;
  int _selectedExternalId = 0;
  SidechainFilterMode _filterMode = SidechainFilterMode.off;
  double _filterFreq = 200.0;
  double _filterQ = 1.0;
  double _mix = 0.0; // 0 = internal only, 1 = external only
  double _gainDb = 0.0;
  bool _monitoring = false;

  @override
  void initState() {
    super.initState();
    _ffi.sidechainCreateInput(widget.processorId);
    _syncToEngine();
  }

  @override
  void dispose() {
    _ffi.sidechainRemoveInput(widget.processorId);
    super.dispose();
  }

  void _syncToEngine() {
    _ffi.sidechainSetSource(widget.processorId, _source.value, externalId: _selectedExternalId);
    _ffi.sidechainSetFilterMode(widget.processorId, _filterMode.value);
    _ffi.sidechainSetFilterFreq(widget.processorId, _filterFreq);
    _ffi.sidechainSetFilterQ(widget.processorId, _filterQ);
    _ffi.sidechainSetMix(widget.processorId, _mix);
    _ffi.sidechainSetGainDb(widget.processorId, _gainDb);
    _ffi.sidechainSetMonitor(widget.processorId, _monitoring);
    widget.onSettingsChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0C),
        border: Border.all(color: const Color(0xFF2A2A30)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          _buildHeader(),
          const Divider(height: 1, color: Color(0xFF2A2A30)),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSourceSection(),
                  const SizedBox(height: 24),
                  _buildFilterSection(),
                  const SizedBox(height: 24),
                  _buildMixSection(),
                  const SizedBox(height: 24),
                  _buildMonitorSection(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.call_split, color: Color(0xFF40C8FF), size: 20),
          const SizedBox(width: 8),
          const Text(
            'SIDECHAIN',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          if (_source != SidechainSource.internal)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF40C8FF).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'EXT',
                style: TextStyle(
                  color: Color(0xFF40C8FF),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSourceSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('KEY INPUT SOURCE'),
        const SizedBox(height: 12),
        // Source type buttons
        Row(
          children: SidechainSource.values.map((source) {
            final isSelected = source == _source;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: GestureDetector(
                  onTap: () {
                    setState(() => _source = source);
                    _ffi.sidechainSetSource(widget.processorId, source.value, externalId: _selectedExternalId);
                    widget.onSettingsChanged?.call();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF40C8FF) : const Color(0xFF1A1A20),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: isSelected ? const Color(0xFF40C8FF) : const Color(0xFF3A3A40),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        source.label,
                        style: TextStyle(
                          color: isSelected ? Colors.white : const Color(0xFF808090),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        // External source selector
        if (_source != SidechainSource.internal && widget.availableSources.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A20),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFF3A3A40)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _selectedExternalId,
                isExpanded: true,
                dropdownColor: const Color(0xFF1A1A20),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                ),
                items: widget.availableSources
                    .where((s) => s.type == _source)
                    .map((s) => DropdownMenuItem(
                          value: s.id,
                          child: Text(s.name),
                        ))
                    .toList(),
                onChanged: (id) {
                  if (id != null) {
                    setState(() => _selectedExternalId = id);
                    _ffi.sidechainSetSource(widget.processorId, _source.value, externalId: id);
                    widget.onSettingsChanged?.call();
                  }
                },
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFilterSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('KEY FILTER'),
        const SizedBox(height: 12),
        // Filter mode buttons
        Row(
          children: SidechainFilterMode.values.map((mode) {
            final isSelected = mode == _filterMode;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: GestureDetector(
                  onTap: () {
                    setState(() => _filterMode = mode);
                    _ffi.sidechainSetFilterMode(widget.processorId, mode.value);
                    widget.onSettingsChanged?.call();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFFFF9040) : const Color(0xFF1A1A20),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: isSelected ? const Color(0xFFFF9040) : const Color(0xFF3A3A40),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        mode.label,
                        style: TextStyle(
                          color: isSelected ? Colors.white : const Color(0xFF808090),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        // Filter controls
        if (_filterMode != SidechainFilterMode.off) ...[
          const SizedBox(height: 16),
          _buildSlider('FREQ', _filterFreq, 20, 20000, 'Hz', (v) {
            setState(() => _filterFreq = v);
            _ffi.sidechainSetFilterFreq(widget.processorId, v);
            widget.onSettingsChanged?.call();
          }, isLog: true),
          const SizedBox(height: 12),
          _buildSlider('Q', _filterQ, 0.1, 10, '', (v) {
            setState(() => _filterQ = v);
            _ffi.sidechainSetFilterQ(widget.processorId, v);
            widget.onSettingsChanged?.call();
          }),
        ],
      ],
    );
  }

  Widget _buildMixSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('KEY MIX'),
        const SizedBox(height: 12),
        Row(
          children: [
            const Text(
              'INT',
              style: TextStyle(
                color: Color(0xFF808090),
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildSlider('', _mix * 100, 0, 100, '%', (v) {
                setState(() => _mix = v / 100);
                _ffi.sidechainSetMix(widget.processorId, v / 100);
                widget.onSettingsChanged?.call();
              }),
            ),
            const SizedBox(width: 8),
            const Text(
              'EXT',
              style: TextStyle(
                color: Color(0xFF808090),
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildSlider('GAIN', _gainDb, -24, 24, 'dB', (v) {
          setState(() => _gainDb = v);
          _ffi.sidechainSetGainDb(widget.processorId, v);
          widget.onSettingsChanged?.call();
        }),
      ],
    );
  }

  Widget _buildMonitorSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('MONITOR'),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () {
            setState(() => _monitoring = !_monitoring);
            _ffi.sidechainSetMonitor(widget.processorId, _monitoring);
            widget.onSettingsChanged?.call();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: _monitoring
                  ? const Color(0xFFFF9040).withValues(alpha: 0.3)
                  : const Color(0xFF1A1A20),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: _monitoring
                    ? const Color(0xFFFF9040)
                    : const Color(0xFF3A3A40),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _monitoring ? Icons.headphones : Icons.headphones_outlined,
                  color: _monitoring
                      ? const Color(0xFFFF9040)
                      : const Color(0xFF606070),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  _monitoring ? 'LISTENING TO KEY' : 'LISTEN TO KEY SIGNAL',
                  style: TextStyle(
                    color: _monitoring
                        ? const Color(0xFFFF9040)
                        : const Color(0xFF808090),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Solo the sidechain signal to hear what the compressor is responding to.',
          style: TextStyle(
            color: Color(0xFF606070),
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Color(0xFF808090),
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.0,
      ),
    );
  }

  Widget _buildSlider(
    String label,
    double value,
    double min,
    double max,
    String unit,
    void Function(double) onChanged, {
    bool isLog = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label.isNotEmpty)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF808090),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
              Text(
                '${value.toStringAsFixed(value < 10 ? 1 : 0)} $unit',
                style: const TextStyle(
                  color: Color(0xFF40C8FF),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        if (label.isNotEmpty) const SizedBox(height: 4),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 4,
            activeTrackColor: const Color(0xFF40C8FF),
            inactiveTrackColor: const Color(0xFF2A2A30),
            thumbColor: const Color(0xFF40C8FF),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            overlayColor: const Color(0xFF40C8FF).withValues(alpha: 0.2),
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
