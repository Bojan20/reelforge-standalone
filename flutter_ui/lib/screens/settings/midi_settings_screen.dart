/// MIDI Settings Screen
///
/// Allows users to configure:
/// - MIDI input devices
/// - MIDI output devices
/// - MIDI channels
/// - MIDI sync settings
/// - MIDI learn mode

import 'package:flutter/material.dart';
import '../../theme/fluxforge_theme.dart';

/// MIDI device info
class MidiDeviceInfo {
  final String id;
  final String name;
  final bool isInput;
  final bool isOutput;
  final bool isEnabled;

  MidiDeviceInfo({
    required this.id,
    required this.name,
    this.isInput = false,
    this.isOutput = false,
    this.isEnabled = false,
  });

  MidiDeviceInfo copyWith({bool? isEnabled}) {
    return MidiDeviceInfo(
      id: id,
      name: name,
      isInput: isInput,
      isOutput: isOutput,
      isEnabled: isEnabled ?? this.isEnabled,
    );
  }
}

/// MIDI sync mode
enum MidiSyncMode { none, midiClock, mtc }

class MidiSettingsScreen extends StatefulWidget {
  const MidiSettingsScreen({super.key});

  @override
  State<MidiSettingsScreen> createState() => _MidiSettingsScreenState();
}

class _MidiSettingsScreenState extends State<MidiSettingsScreen> {
  List<MidiDeviceInfo> _inputDevices = [];
  List<MidiDeviceInfo> _outputDevices = [];
  MidiSyncMode _syncMode = MidiSyncMode.none;
  bool _sendMidiClock = false;
  bool _sendMtc = false;
  bool _midiThru = false;
  int _midiClockPpq = 24;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    setState(() => _isLoading = true);

    // TODO: Call Rust FFI to get actual MIDI devices
    // For now, mock data
    await Future.delayed(const Duration(milliseconds: 300));

    _inputDevices = [
      MidiDeviceInfo(
        id: 'midi-in-1',
        name: 'IAC Driver Bus 1',
        isInput: true,
        isEnabled: true,
      ),
      MidiDeviceInfo(
        id: 'midi-in-2',
        name: 'USB MIDI Keyboard',
        isInput: true,
        isEnabled: false,
      ),
      MidiDeviceInfo(
        id: 'midi-in-3',
        name: 'Network Session 1',
        isInput: true,
        isEnabled: false,
      ),
    ];

    _outputDevices = [
      MidiDeviceInfo(
        id: 'midi-out-1',
        name: 'IAC Driver Bus 1',
        isOutput: true,
        isEnabled: true,
      ),
      MidiDeviceInfo(
        id: 'midi-out-2',
        name: 'USB MIDI Interface',
        isOutput: true,
        isEnabled: false,
      ),
    ];

    setState(() => _isLoading = false);
  }

  void _toggleInputDevice(int index) {
    setState(() {
      _inputDevices[index] = _inputDevices[index].copyWith(
        isEnabled: !_inputDevices[index].isEnabled,
      );
    });
    // TODO: Call Rust FFI to enable/disable device
  }

  void _toggleOutputDevice(int index) {
    setState(() {
      _outputDevices[index] = _outputDevices[index].copyWith(
        isEnabled: !_outputDevices[index].isEnabled,
      );
    });
    // TODO: Call Rust FFI to enable/disable device
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FluxForgeTheme.bgDeep,
      appBar: AppBar(
        backgroundColor: FluxForgeTheme.bgMid,
        title: const Text('MIDI Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh devices',
            onPressed: _loadDevices,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInputDevicesSection(),
                  const SizedBox(height: 24),
                  _buildOutputDevicesSection(),
                  const SizedBox(height: 24),
                  _buildSyncSection(),
                  const SizedBox(height: 24),
                  _buildOptionsSection(),
                ],
              ),
            ),
    );
  }

  Widget _buildInputDevicesSection() {
    return _buildSection(
      title: 'MIDI Inputs',
      icon: Icons.piano,
      child: Column(
        children: [
          if (_inputDevices.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'No MIDI input devices found',
                style: TextStyle(color: FluxForgeTheme.textSecondary),
              ),
            )
          else
            ..._inputDevices.asMap().entries.map((entry) {
              final index = entry.key;
              final device = entry.value;
              return _buildDeviceItem(
                device: device,
                onToggle: () => _toggleInputDevice(index),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildOutputDevicesSection() {
    return _buildSection(
      title: 'MIDI Outputs',
      icon: Icons.output,
      child: Column(
        children: [
          if (_outputDevices.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'No MIDI output devices found',
                style: TextStyle(color: FluxForgeTheme.textSecondary),
              ),
            )
          else
            ..._outputDevices.asMap().entries.map((entry) {
              final index = entry.key;
              final device = entry.value;
              return _buildDeviceItem(
                device: device,
                onToggle: () => _toggleOutputDevice(index),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildDeviceItem({
    required MidiDeviceInfo device,
    required VoidCallback onToggle,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: device.isEnabled
              ? FluxForgeTheme.accentGreen.withValues(alpha: 0.5)
              : FluxForgeTheme.borderSubtle,
        ),
      ),
      child: ListTile(
        leading: Icon(
          device.isInput ? Icons.input : Icons.output,
          color: device.isEnabled
              ? FluxForgeTheme.accentGreen
              : FluxForgeTheme.textSecondary,
        ),
        title: Text(
          device.name,
          style: TextStyle(color: FluxForgeTheme.textPrimary),
        ),
        subtitle: Text(
          device.isEnabled ? 'Active' : 'Inactive',
          style: TextStyle(
            color: device.isEnabled
                ? FluxForgeTheme.accentGreen
                : FluxForgeTheme.textTertiary,
            fontSize: 12,
          ),
        ),
        trailing: Switch(
          value: device.isEnabled,
          onChanged: (_) => onToggle(),
          activeColor: FluxForgeTheme.accentGreen,
        ),
      ),
    );
  }

  Widget _buildSyncSection() {
    return _buildSection(
      title: 'MIDI Sync',
      icon: Icons.sync,
      child: Column(
        children: [
          // Sync receive mode
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgSurface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Receive Sync From',
                  style: TextStyle(
                    color: FluxForgeTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: MidiSyncMode.values.map((mode) {
                    final isSelected = _syncMode == mode;
                    return ChoiceChip(
                      label: Text(_getSyncModeName(mode)),
                      selected: isSelected,
                      onSelected: (_) => setState(() => _syncMode = mode),
                      backgroundColor: FluxForgeTheme.bgMid,
                      selectedColor: FluxForgeTheme.accentBlue,
                      labelStyle: TextStyle(
                        color:
                            isSelected ? FluxForgeTheme.textPrimary : FluxForgeTheme.textPrimary,
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Send sync options
          _buildSwitchItem(
            title: 'Send MIDI Clock',
            subtitle: 'Transmit MIDI clock to connected devices',
            value: _sendMidiClock,
            onChanged: (v) => setState(() => _sendMidiClock = v),
          ),
          const SizedBox(height: 8),
          _buildSwitchItem(
            title: 'Send MTC (MIDI Time Code)',
            subtitle: 'Transmit MTC for video sync',
            value: _sendMtc,
            onChanged: (v) => setState(() => _sendMtc = v),
          ),
          const SizedBox(height: 12),
          // PPQ selection
          if (_sendMidiClock)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: FluxForgeTheme.bgSurface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Text(
                    'Clock PPQ',
                    style: TextStyle(color: FluxForgeTheme.textPrimary),
                  ),
                  const Spacer(),
                  DropdownButton<int>(
                    value: _midiClockPpq,
                    dropdownColor: FluxForgeTheme.bgMid,
                    style: TextStyle(color: FluxForgeTheme.textPrimary),
                    items: [24, 48, 96, 192, 384].map((ppq) {
                      return DropdownMenuItem(
                        value: ppq,
                        child: Text('$ppq PPQ'),
                      );
                    }).toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _midiClockPpq = v);
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOptionsSection() {
    return _buildSection(
      title: 'Options',
      icon: Icons.settings,
      child: Column(
        children: [
          _buildSwitchItem(
            title: 'MIDI Thru',
            subtitle: 'Pass through MIDI input to selected output',
            value: _midiThru,
            onChanged: (v) => setState(() => _midiThru = v),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchItem({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgSurface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SwitchListTile(
        title: Text(
          title,
          style: TextStyle(color: FluxForgeTheme.textPrimary),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: FluxForgeTheme.textSecondary,
            fontSize: 12,
          ),
        ),
        value: value,
        onChanged: onChanged,
        activeColor: FluxForgeTheme.accentBlue,
      ),
    );
  }

  String _getSyncModeName(MidiSyncMode mode) {
    switch (mode) {
      case MidiSyncMode.none:
        return 'None';
      case MidiSyncMode.midiClock:
        return 'MIDI Clock';
      case MidiSyncMode.mtc:
        return 'MTC';
    }
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: FluxForgeTheme.accentBlue, size: 20),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                color: FluxForgeTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}
