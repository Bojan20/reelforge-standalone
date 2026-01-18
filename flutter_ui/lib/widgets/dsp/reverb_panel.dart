/// FluxForge Studio Professional Reverb Panel
///
/// Dual-mode reverb with Convolution (IR-based) and Algorithmic (Freeverb-style)
/// processing options.

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../src/rust/native_ffi.dart';
import '../../theme/fluxforge_theme.dart';
import '../../services/native_file_picker.dart';

/// Reverb mode selection
enum ReverbMode {
  algorithmic,
  convolution,
}

/// Professional Reverb Panel Widget
class ReverbPanel extends StatefulWidget {
  /// Track ID to process
  final int trackId;

  /// Sample rate
  final double sampleRate;

  /// Callback when settings change
  final VoidCallback? onSettingsChanged;

  const ReverbPanel({
    super.key,
    required this.trackId,
    this.sampleRate = 48000.0,
    this.onSettingsChanged,
  });

  @override
  State<ReverbPanel> createState() => _ReverbPanelState();
}

class _ReverbPanelState extends State<ReverbPanel> {
  // Mode selection
  ReverbMode _mode = ReverbMode.algorithmic;

  // Algorithmic reverb parameters
  ReverbType _reverbType = ReverbType.room;
  double _roomSize = 0.5;
  double _damping = 0.5;
  double _width = 1.0;
  double _dryWet = 0.3;
  double _predelay = 0.0;

  // Convolution reverb parameters
  double _convDryWet = 0.5;
  double _convPredelay = 0.0;
  String _irName = 'No IR Loaded';

  // State
  bool _initialized = false;
  bool _bypassed = false;

  @override
  void initState() {
    super.initState();
    _initializeProcessor();
  }

  @override
  void dispose() {
    NativeFFI.instance.algorithmicReverbRemove(widget.trackId);
    NativeFFI.instance.convolutionReverbRemove(widget.trackId);
    super.dispose();
  }

  void _initializeProcessor() {
    // Create both reverb types
    final algoSuccess = NativeFFI.instance.algorithmicReverbCreate(
      widget.trackId,
      sampleRate: widget.sampleRate,
    );
    final convSuccess = NativeFFI.instance.convolutionReverbCreate(
      widget.trackId,
      sampleRate: widget.sampleRate,
    );

    if (algoSuccess || convSuccess) {
      setState(() => _initialized = true);
      _applyAllSettings();
    }
  }

  void _applyAllSettings() {
    if (!_initialized) return;

    // Apply algorithmic settings
    NativeFFI.instance.algorithmicReverbSetType(widget.trackId, _reverbType);
    NativeFFI.instance.algorithmicReverbSetRoomSize(widget.trackId, _roomSize);
    NativeFFI.instance.algorithmicReverbSetDamping(widget.trackId, _damping);
    NativeFFI.instance.algorithmicReverbSetWidth(widget.trackId, _width);
    NativeFFI.instance.algorithmicReverbSetDryWet(widget.trackId, _dryWet);
    NativeFFI.instance.algorithmicReverbSetPredelay(widget.trackId, _predelay);

    // Apply convolution settings
    NativeFFI.instance.convolutionReverbSetDryWet(widget.trackId, _convDryWet);
    NativeFFI.instance.convolutionReverbSetPredelay(widget.trackId, _convPredelay);

    widget.onSettingsChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FluxForgeTheme.surfaceDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          _buildHeader(),
          const SizedBox(height: 16),

          // Mode selector
          _buildModeSelector(),
          const SizedBox(height: 16),

          // Mode-specific controls
          if (_mode == ReverbMode.algorithmic)
            _buildAlgorithmicControls()
          else
            _buildConvolutionControls(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Icon(Icons.waves, color: FluxForgeTheme.accentBlue, size: 20),
        const SizedBox(width: 8),
        Text(
          'Reverb',
          style: TextStyle(
            color: FluxForgeTheme.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const Spacer(),
        // Bypass button
        GestureDetector(
          onTap: () => setState(() => _bypassed = !_bypassed),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _bypassed
                  ? Colors.orange.withOpacity(0.3)
                  : FluxForgeTheme.surface,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: _bypassed ? Colors.orange : FluxForgeTheme.border,
              ),
            ),
            child: Text(
              'BYPASS',
              style: TextStyle(
                color: _bypassed ? Colors.orange : FluxForgeTheme.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Status indicator
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: _initialized
                ? Colors.green.withOpacity(0.2)
                : Colors.red.withOpacity(0.2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            _initialized ? 'Ready' : 'Init...',
            style: TextStyle(
              color: _initialized ? Colors.green : Colors.red,
              fontSize: 10,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildModeSelector() {
    return Row(
      children: [
        _buildModeButton('Algorithmic', ReverbMode.algorithmic),
        const SizedBox(width: 8),
        _buildModeButton('Convolution', ReverbMode.convolution),
      ],
    );
  }

  Widget _buildModeButton(String label, ReverbMode mode) {
    final isActive = _mode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _mode = mode),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isActive
                ? FluxForgeTheme.accentBlue.withOpacity(0.2)
                : FluxForgeTheme.surface,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isActive ? FluxForgeTheme.accentBlue : FluxForgeTheme.border,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isActive ? FluxForgeTheme.accentBlue : FluxForgeTheme.textSecondary,
              fontSize: 12,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAlgorithmicControls() {
    return Column(
      children: [
        // Reverb type dropdown
        _buildTypeSelector(),
        const SizedBox(height: 16),

        // Room Size
        _buildParameterRow(
          label: 'Room Size',
          value: '${(_roomSize * 100).toStringAsFixed(0)}%',
          child: _buildSlider(
            value: _roomSize,
            onChanged: (v) {
              setState(() => _roomSize = v);
              NativeFFI.instance.algorithmicReverbSetRoomSize(widget.trackId, v);
              widget.onSettingsChanged?.call();
            },
          ),
        ),
        const SizedBox(height: 8),

        // Damping
        _buildParameterRow(
          label: 'Damping',
          value: '${(_damping * 100).toStringAsFixed(0)}%',
          child: _buildSlider(
            value: _damping,
            onChanged: (v) {
              setState(() => _damping = v);
              NativeFFI.instance.algorithmicReverbSetDamping(widget.trackId, v);
              widget.onSettingsChanged?.call();
            },
          ),
        ),
        const SizedBox(height: 8),

        // Width
        _buildParameterRow(
          label: 'Width',
          value: '${(_width * 100).toStringAsFixed(0)}%',
          child: _buildSlider(
            value: _width,
            onChanged: (v) {
              setState(() => _width = v);
              NativeFFI.instance.algorithmicReverbSetWidth(widget.trackId, v);
              widget.onSettingsChanged?.call();
            },
          ),
        ),
        const SizedBox(height: 8),

        // Dry/Wet
        _buildParameterRow(
          label: 'Dry/Wet',
          value: '${(_dryWet * 100).toStringAsFixed(0)}%',
          child: _buildSlider(
            value: _dryWet,
            onChanged: (v) {
              setState(() => _dryWet = v);
              NativeFFI.instance.algorithmicReverbSetDryWet(widget.trackId, v);
              widget.onSettingsChanged?.call();
            },
          ),
        ),
        const SizedBox(height: 8),

        // Pre-delay
        _buildParameterRow(
          label: 'Pre-delay',
          value: '${_predelay.toStringAsFixed(0)} ms',
          child: _buildSlider(
            value: _predelay / 200.0,
            onChanged: (v) {
              setState(() => _predelay = v * 200.0);
              NativeFFI.instance.algorithmicReverbSetPredelay(widget.trackId, _predelay);
              widget.onSettingsChanged?.call();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTypeSelector() {
    return Row(
      children: [
        Text(
          'Type',
          style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 12),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: FluxForgeTheme.surface,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: FluxForgeTheme.border),
            ),
            child: DropdownButton<ReverbType>(
              value: _reverbType,
              isExpanded: true,
              dropdownColor: FluxForgeTheme.surfaceDark,
              underline: const SizedBox(),
              style: TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 13),
              items: ReverbType.values.map((t) => DropdownMenuItem(
                value: t,
                child: Text(_getTypeName(t)),
              )).toList(),
              onChanged: (v) {
                if (v != null) {
                  setState(() => _reverbType = v);
                  NativeFFI.instance.algorithmicReverbSetType(widget.trackId, v);
                  widget.onSettingsChanged?.call();
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  String _getTypeName(ReverbType type) {
    switch (type) {
      case ReverbType.room: return 'Room';
      case ReverbType.hall: return 'Hall';
      case ReverbType.plate: return 'Plate';
      case ReverbType.chamber: return 'Chamber';
      case ReverbType.spring: return 'Spring';
    }
  }

  Widget _buildConvolutionControls() {
    return Column(
      children: [
        // IR loader
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: FluxForgeTheme.surface.withOpacity(0.5),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: FluxForgeTheme.border),
          ),
          child: Row(
            children: [
              Icon(Icons.folder_open, color: FluxForgeTheme.textSecondary, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _irName,
                  style: TextStyle(
                    color: FluxForgeTheme.textSecondary,
                    fontSize: 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: _loadImpulseResponse,
                child: Text(
                  'Load IR',
                  style: TextStyle(color: FluxForgeTheme.accentBlue, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Dry/Wet
        _buildParameterRow(
          label: 'Dry/Wet',
          value: '${(_convDryWet * 100).toStringAsFixed(0)}%',
          child: _buildSlider(
            value: _convDryWet,
            onChanged: (v) {
              setState(() => _convDryWet = v);
              NativeFFI.instance.convolutionReverbSetDryWet(widget.trackId, v);
              widget.onSettingsChanged?.call();
            },
          ),
        ),
        const SizedBox(height: 8),

        // Pre-delay
        _buildParameterRow(
          label: 'Pre-delay',
          value: '${_convPredelay.toStringAsFixed(0)} ms',
          child: _buildSlider(
            value: _convPredelay / 500.0,
            onChanged: (v) {
              setState(() => _convPredelay = v * 500.0);
              NativeFFI.instance.convolutionReverbSetPredelay(widget.trackId, _convPredelay);
              widget.onSettingsChanged?.call();
            },
          ),
        ),
        const SizedBox(height: 16),

        // Preset buttons
        _buildConvolutionPresets(),
      ],
    );
  }

  Widget _buildConvolutionPresets() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick Presets',
          style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 11),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildPresetChip('Small Room'),
            _buildPresetChip('Large Hall'),
            _buildPresetChip('Studio Plate'),
            _buildPresetChip('Cathedral'),
          ],
        ),
      ],
    );
  }

  Widget _buildPresetChip(String label) {
    return GestureDetector(
      onTap: () {
        // TODO: Load preset IR
        setState(() => _irName = label);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: FluxForgeTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: FluxForgeTheme.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: FluxForgeTheme.textSecondary,
            fontSize: 11,
          ),
        ),
      ),
    );
  }

  Future<void> _loadImpulseResponse() async {
    final path = await NativeFilePicker.pickIrFile();
    if (path == null) return;

    try {
      // Read audio file and extract samples
      final file = File(path);
      if (!await file.exists()) {
        setState(() => _irName = 'File not found');
        return;
      }

      // Read raw bytes
      final bytes = await file.readAsBytes();

      // Parse WAV file (simplified - assumes 16-bit PCM stereo)
      final samples = _parseWavFile(bytes);
      if (samples == null || samples.isEmpty) {
        setState(() => _irName = 'Invalid IR format');
        return;
      }

      // Load into convolution engine
      final success = NativeFFI.instance.convolutionReverbLoadIr(
        widget.trackId,
        samples,
        channelCount: 2,
      );

      if (success) {
        // Extract filename
        final fileName = path.split('/').last;
        setState(() => _irName = fileName);
        widget.onSettingsChanged?.call();
      } else {
        setState(() => _irName = 'Load failed');
      }
    } catch (e) {
      setState(() => _irName = 'Error: $e');
    }
  }

  /// Parse WAV file to Float64List samples
  Float64List? _parseWavFile(Uint8List bytes) {
    if (bytes.length < 44) return null;

    // Check WAV header
    final riff = String.fromCharCodes(bytes.sublist(0, 4));
    final wave = String.fromCharCodes(bytes.sublist(8, 12));
    if (riff != 'RIFF' || wave != 'WAVE') return null;

    // Find data chunk
    int dataOffset = 12;
    int dataSize = 0;
    while (dataOffset < bytes.length - 8) {
      final chunkId = String.fromCharCodes(bytes.sublist(dataOffset, dataOffset + 4));
      final chunkSize = bytes.buffer.asByteData().getUint32(dataOffset + 4, Endian.little);

      if (chunkId == 'data') {
        dataOffset += 8;
        dataSize = chunkSize;
        break;
      }
      dataOffset += 8 + chunkSize;
    }

    if (dataSize == 0) return null;

    // Get format info
    final bitsPerSample = bytes.buffer.asByteData().getUint16(34, Endian.little);
    // numChannels stored at offset 22, but we process all samples interleaved

    // Convert to Float64List
    final numSamples = dataSize ~/ (bitsPerSample ~/ 8);
    final samples = Float64List(numSamples);
    final byteData = bytes.buffer.asByteData();

    for (int i = 0; i < numSamples && dataOffset + (bitsPerSample ~/ 8) <= bytes.length; i++) {
      if (bitsPerSample == 16) {
        final int16 = byteData.getInt16(dataOffset, Endian.little);
        samples[i] = int16 / 32768.0;
        dataOffset += 2;
      } else if (bitsPerSample == 24) {
        final b0 = bytes[dataOffset];
        final b1 = bytes[dataOffset + 1];
        final b2 = bytes[dataOffset + 2];
        final int24 = (b2 << 16) | (b1 << 8) | b0;
        final signed = int24 > 0x7FFFFF ? int24 - 0x1000000 : int24;
        samples[i] = signed / 8388608.0;
        dataOffset += 3;
      } else if (bitsPerSample == 32) {
        final float32 = byteData.getFloat32(dataOffset, Endian.little);
        samples[i] = float32;
        dataOffset += 4;
      }
    }

    return samples;
  }

  Widget _buildParameterRow({
    required String label,
    required String value,
    required Widget child,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 12),
          ),
        ),
        Expanded(child: child),
        SizedBox(
          width: 60,
          child: Text(
            value,
            style: TextStyle(
              color: FluxForgeTheme.accentBlue,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _buildSlider({
    required double value,
    required ValueChanged<double> onChanged,
    double min = 0.0,
    double max = 1.0,
  }) {
    return SliderTheme(
      data: SliderThemeData(
        trackHeight: 4,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
        activeTrackColor: FluxForgeTheme.accentBlue,
        inactiveTrackColor: FluxForgeTheme.surface,
        thumbColor: FluxForgeTheme.accentBlue,
        overlayColor: FluxForgeTheme.accentBlue.withOpacity(0.2),
      ),
      child: Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        onChanged: onChanged,
      ),
    );
  }
}
