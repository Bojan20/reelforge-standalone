// Pro Tools-Style Edit Modes Provider
//
// Implements the four fundamental edit modes from Pro Tools:
//
// 1. SHUFFLE (F1): Clips automatically close gaps
//    - Moving/deleting clips causes adjacent clips to snap together
//    - No gaps allowed - timeline is always contiguous
//    - Used for dialogue editing, podcast, audiobook
//
// 2. SLIP (F2): Clips move freely
//    - Default mode - clips can overlap or have gaps
//    - Most flexible for music production
//    - No automatic repositioning
//
// 3. SPOT (F3): Precise placement dialog
//    - Opens dialog to enter exact timecode position
//    - Used for post-production sync (video, ADR, Foley)
//    - Places clips at exact SMPTE timecode
//
// 4. GRID (F4): Snap to grid divisions
//    - Clips snap to nearest grid line
//    - Grid resolution: bar, beat, 1/4, 1/8, 1/16, etc.
//    - Used for rhythmic alignment in music

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════════

/// Pro Tools-style edit modes
enum EditMode {
  /// Shuffle mode - clips close gaps automatically
  shuffle,

  /// Slip mode - free movement, clips can overlap
  slip,

  /// Spot mode - precise timecode placement
  spot,

  /// Grid mode - snap to grid divisions
  grid,
}

/// Grid resolution for Grid mode
enum GridResolution {
  bar,
  halfBar,
  beat,
  halfBeat,
  quarterBeat,
  eighth,
  sixteenth,
  thirtysecond,
  sixtyfourth,
  triplet,
  dotted,
  frames,
  samples,
}

/// Timecode format for Spot mode
enum TimecodeFormat {
  /// HH:MM:SS:FF (SMPTE)
  smpte,

  /// Bars|Beats|Ticks
  barsBeats,

  /// Minutes:Seconds.Milliseconds
  minSecMs,

  /// Samples
  samples,

  /// Feet+Frames (film)
  feetFrames,
}

/// Frame rate for SMPTE timecode
enum FrameRate {
  fps23976,
  fps24,
  fps25,
  fps2997df, // Drop-frame
  fps2997nd, // Non-drop
  fps30,
}

/// Edit mode configuration
class EditModeConfig {
  final EditMode mode;
  final String name;
  final String shortcut;
  final String description;
  final IconData icon;
  final Color color;

  const EditModeConfig({
    required this.mode,
    required this.name,
    required this.shortcut,
    required this.description,
    required this.icon,
    required this.color,
  });
}

/// Grid resolution configuration
class GridResolutionConfig {
  final GridResolution resolution;
  final String name;
  final String symbol;
  final double multiplier; // Relative to beat

  const GridResolutionConfig({
    required this.resolution,
    required this.name,
    required this.symbol,
    required this.multiplier,
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════════

/// Edit mode configurations
const Map<EditMode, EditModeConfig> kEditModeConfigs = {
  EditMode.shuffle: EditModeConfig(
    mode: EditMode.shuffle,
    name: 'Shuffle',
    shortcut: 'F1',
    description: 'Clips close gaps automatically',
    icon: Icons.view_stream,
    color: Color(0xFF40ff90), // Green
  ),
  EditMode.slip: EditModeConfig(
    mode: EditMode.slip,
    name: 'Slip',
    shortcut: 'F2',
    description: 'Free movement, clips can overlap',
    icon: Icons.swap_horiz,
    color: Color(0xFF4a9eff), // Blue
  ),
  EditMode.spot: EditModeConfig(
    mode: EditMode.spot,
    name: 'Spot',
    shortcut: 'F3',
    description: 'Precise timecode placement',
    icon: Icons.pin_drop,
    color: Color(0xFFff9040), // Orange
  ),
  EditMode.grid: EditModeConfig(
    mode: EditMode.grid,
    name: 'Grid',
    shortcut: 'F4',
    description: 'Snap to grid divisions',
    icon: Icons.grid_on,
    color: Color(0xFFff4090), // Magenta
  ),
};

/// Grid resolution configurations
const Map<GridResolution, GridResolutionConfig> kGridResolutionConfigs = {
  GridResolution.bar: GridResolutionConfig(
    resolution: GridResolution.bar,
    name: 'Bar',
    symbol: '1',
    multiplier: 4.0,
  ),
  GridResolution.halfBar: GridResolutionConfig(
    resolution: GridResolution.halfBar,
    name: '1/2 Bar',
    symbol: '1/2',
    multiplier: 2.0,
  ),
  GridResolution.beat: GridResolutionConfig(
    resolution: GridResolution.beat,
    name: 'Beat',
    symbol: '1/4',
    multiplier: 1.0,
  ),
  GridResolution.halfBeat: GridResolutionConfig(
    resolution: GridResolution.halfBeat,
    name: '1/2 Beat',
    symbol: '1/8',
    multiplier: 0.5,
  ),
  GridResolution.quarterBeat: GridResolutionConfig(
    resolution: GridResolution.quarterBeat,
    name: '1/4 Beat',
    symbol: '1/16',
    multiplier: 0.25,
  ),
  GridResolution.eighth: GridResolutionConfig(
    resolution: GridResolution.eighth,
    name: '8th',
    symbol: '♪',
    multiplier: 0.5,
  ),
  GridResolution.sixteenth: GridResolutionConfig(
    resolution: GridResolution.sixteenth,
    name: '16th',
    symbol: '♬',
    multiplier: 0.25,
  ),
  GridResolution.thirtysecond: GridResolutionConfig(
    resolution: GridResolution.thirtysecond,
    name: '32nd',
    symbol: '1/32',
    multiplier: 0.125,
  ),
  GridResolution.sixtyfourth: GridResolutionConfig(
    resolution: GridResolution.sixtyfourth,
    name: '64th',
    symbol: '1/64',
    multiplier: 0.0625,
  ),
  GridResolution.triplet: GridResolutionConfig(
    resolution: GridResolution.triplet,
    name: 'Triplet',
    symbol: '3',
    multiplier: 1.0 / 3.0,
  ),
  GridResolution.dotted: GridResolutionConfig(
    resolution: GridResolution.dotted,
    name: 'Dotted',
    symbol: '.',
    multiplier: 1.5,
  ),
  GridResolution.frames: GridResolutionConfig(
    resolution: GridResolution.frames,
    name: 'Frames',
    symbol: 'F',
    multiplier: 0.0, // Calculated from frame rate
  ),
  GridResolution.samples: GridResolutionConfig(
    resolution: GridResolution.samples,
    name: 'Samples',
    symbol: 'S',
    multiplier: 0.0, // Depends on sample rate
  ),
};

// ═══════════════════════════════════════════════════════════════════════════════
// SPOT MODE DATA
// ═══════════════════════════════════════════════════════════════════════════════

/// Timecode position for Spot mode
class TimecodePosition {
  final int hours;
  final int minutes;
  final int seconds;
  final int frames;
  final int subFrames; // For higher precision

  const TimecodePosition({
    this.hours = 0,
    this.minutes = 0,
    this.seconds = 0,
    this.frames = 0,
    this.subFrames = 0,
  });

  /// Create from total samples
  factory TimecodePosition.fromSamples(
    int samples,
    double sampleRate,
    FrameRate frameRate,
  ) {
    final fps = _getFrameRateValue(frameRate);
    final totalSeconds = samples / sampleRate;
    final totalFrames = (totalSeconds * fps).floor();

    final hours = totalFrames ~/ (3600 * fps.floor());
    final minutes = (totalFrames ~/ (60 * fps.floor())) % 60;
    final seconds = (totalFrames ~/ fps.floor()) % 60;
    final frames = totalFrames % fps.floor();

    return TimecodePosition(
      hours: hours,
      minutes: minutes,
      seconds: seconds,
      frames: frames,
    );
  }

  /// Convert to total samples
  int toSamples(double sampleRate, FrameRate frameRate) {
    final fps = _getFrameRateValue(frameRate);
    final totalSeconds =
        hours * 3600 + minutes * 60 + seconds + (frames / fps);
    return (totalSeconds * sampleRate).round();
  }

  /// Format as SMPTE string
  String toSmpteString(FrameRate frameRate) {
    final separator = frameRate == FrameRate.fps2997df ? ';' : ':';
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}$separator'
        '${frames.toString().padLeft(2, '0')}';
  }

  static double _getFrameRateValue(FrameRate rate) {
    switch (rate) {
      case FrameRate.fps23976:
        return 23.976;
      case FrameRate.fps24:
        return 24.0;
      case FrameRate.fps25:
        return 25.0;
      case FrameRate.fps2997df:
      case FrameRate.fps2997nd:
        return 29.97;
      case FrameRate.fps30:
        return 30.0;
    }
  }

  TimecodePosition copyWith({
    int? hours,
    int? minutes,
    int? seconds,
    int? frames,
    int? subFrames,
  }) {
    return TimecodePosition(
      hours: hours ?? this.hours,
      minutes: minutes ?? this.minutes,
      seconds: seconds ?? this.seconds,
      frames: frames ?? this.frames,
      subFrames: subFrames ?? this.subFrames,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PROVIDER
// ═══════════════════════════════════════════════════════════════════════════════

/// Pro Tools-style Edit Mode Provider
class EditModeProProvider extends ChangeNotifier {
  // Current edit mode
  EditMode _mode = EditMode.slip; // Default to Slip (most common)

  // Grid settings
  GridResolution _gridResolution = GridResolution.beat;
  bool _gridEnabled = true;
  bool _tripletGrid = false;
  bool _dottedGrid = false;

  // Spot mode settings
  TimecodeFormat _timecodeFormat = TimecodeFormat.smpte;
  FrameRate _frameRate = FrameRate.fps2997df;
  TimecodePosition _spotPosition = const TimecodePosition();

  // Shuffle mode settings
  bool _shuffleSync = false; // Sync Point shuffle

  // Callbacks
  void Function(EditMode)? onModeChanged;
  void Function(TimecodePosition)? onSpotRequested;

  // ═══ Getters ═══

  EditMode get mode => _mode;
  EditModeConfig get modeConfig => kEditModeConfigs[_mode]!;
  GridResolution get gridResolution => _gridResolution;
  GridResolutionConfig get gridConfig => kGridResolutionConfigs[_gridResolution]!;
  bool get gridEnabled => _gridEnabled;
  bool get tripletGrid => _tripletGrid;
  bool get dottedGrid => _dottedGrid;
  TimecodeFormat get timecodeFormat => _timecodeFormat;
  FrameRate get frameRate => _frameRate;
  TimecodePosition get spotPosition => _spotPosition;
  bool get shuffleSync => _shuffleSync;

  // Mode checks
  bool get isShuffleMode => _mode == EditMode.shuffle;
  bool get isSlipMode => _mode == EditMode.slip;
  bool get isSpotMode => _mode == EditMode.spot;
  bool get isGridMode => _mode == EditMode.grid;

  // ═══ Mode Control ═══

  /// Set edit mode
  void setMode(EditMode mode) {
    if (_mode != mode) {
      _mode = mode;
      onModeChanged?.call(mode);
      notifyListeners();
    }
  }

  /// Set mode by index (0=Shuffle, 1=Slip, 2=Spot, 3=Grid)
  void setModeByIndex(int index) {
    if (index >= 0 && index < EditMode.values.length) {
      setMode(EditMode.values[index]);
    }
  }

  /// Cycle through modes
  void cycleMode() {
    final nextIndex = (_mode.index + 1) % EditMode.values.length;
    setMode(EditMode.values[nextIndex]);
  }

  // ═══ Grid Settings ═══

  /// Set grid resolution
  void setGridResolution(GridResolution resolution) {
    if (_gridResolution != resolution) {
      _gridResolution = resolution;
      notifyListeners();
    }
  }

  /// Toggle grid on/off
  void toggleGrid() {
    _gridEnabled = !_gridEnabled;
    notifyListeners();
  }

  /// Set grid enabled state
  void setGridEnabled(bool enabled) {
    if (_gridEnabled != enabled) {
      _gridEnabled = enabled;
      notifyListeners();
    }
  }

  /// Toggle triplet grid modifier
  void toggleTriplet() {
    _tripletGrid = !_tripletGrid;
    if (_tripletGrid) _dottedGrid = false; // Mutually exclusive
    notifyListeners();
  }

  /// Toggle dotted grid modifier
  void toggleDotted() {
    _dottedGrid = !_dottedGrid;
    if (_dottedGrid) _tripletGrid = false; // Mutually exclusive
    notifyListeners();
  }

  /// Get effective grid resolution in beats
  double getEffectiveGridBeats() {
    double base = gridConfig.multiplier;

    if (_tripletGrid) {
      base *= (2.0 / 3.0); // Triplet = 2/3 of normal
    } else if (_dottedGrid) {
      base *= 1.5; // Dotted = 1.5x normal
    }

    return base;
  }

  // ═══ Spot Mode ═══

  /// Set timecode format
  void setTimecodeFormat(TimecodeFormat format) {
    if (_timecodeFormat != format) {
      _timecodeFormat = format;
      notifyListeners();
    }
  }

  /// Set frame rate
  void setFrameRate(FrameRate rate) {
    if (_frameRate != rate) {
      _frameRate = rate;
      notifyListeners();
    }
  }

  /// Set spot position
  void setSpotPosition(TimecodePosition position) {
    _spotPosition = position;
    notifyListeners();
  }

  /// Request spot placement (triggers dialog)
  void requestSpot() {
    onSpotRequested?.call(_spotPosition);
  }

  // ═══ Shuffle Mode ═══

  /// Toggle Sync Point shuffle
  void toggleShuffleSync() {
    _shuffleSync = !_shuffleSync;
    notifyListeners();
  }

  /// Set Sync Point shuffle
  void setShuffleSync(bool enabled) {
    if (_shuffleSync != enabled) {
      _shuffleSync = enabled;
      notifyListeners();
    }
  }

  // ═══ Keyboard Handling ═══

  /// Handle keyboard shortcuts (F1-F4 for modes)
  KeyEventResult handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;

    // F1 = Shuffle
    if (key == LogicalKeyboardKey.f1) {
      setMode(EditMode.shuffle);
      return KeyEventResult.handled;
    }

    // F2 = Slip
    if (key == LogicalKeyboardKey.f2) {
      setMode(EditMode.slip);
      return KeyEventResult.handled;
    }

    // F3 = Spot
    if (key == LogicalKeyboardKey.f3) {
      setMode(EditMode.spot);
      return KeyEventResult.handled;
    }

    // F4 = Grid
    if (key == LogicalKeyboardKey.f4) {
      setMode(EditMode.grid);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  // ═══ Snap Calculation ═══

  /// Snap position to grid (returns snapped position in samples)
  int snapToGrid(int positionSamples, double sampleRate, double tempo) {
    if (!_gridEnabled || _mode != EditMode.grid) {
      return positionSamples;
    }

    // Calculate grid interval in samples
    final beatsPerSecond = tempo / 60.0;
    final samplesPerBeat = sampleRate / beatsPerSecond;
    final gridInterval = samplesPerBeat * getEffectiveGridBeats();

    // Snap to nearest grid line
    final gridIndex = (positionSamples / gridInterval).round();
    return (gridIndex * gridInterval).round();
  }

  /// Calculate shuffle positions after move/delete
  List<int> calculateShufflePositions(
    List<int> clipStarts,
    List<int> clipLengths,
    int removedIndex,
  ) {
    if (_mode != EditMode.shuffle) {
      return clipStarts;
    }

    final result = <int>[];
    int currentPosition = 0;

    for (int i = 0; i < clipStarts.length; i++) {
      if (i == removedIndex) continue;

      result.add(currentPosition);
      currentPosition += clipLengths[i];
    }

    return result;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// WIDGET: Edit Mode Selector
// ═══════════════════════════════════════════════════════════════════════════════

/// Visual selector for edit modes (toolbar button)
class EditModeSelector extends StatelessWidget {
  final EditModeProProvider provider;
  final bool showLabel;
  final double size;

  const EditModeSelector({
    super.key,
    required this.provider,
    this.showLabel = true,
    this.size = 32,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: provider,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: EditMode.values.map((mode) {
            final config = kEditModeConfigs[mode]!;
            final isSelected = provider.mode == mode;

            return Tooltip(
              message: '${config.name} (${config.shortcut})\n${config.description}',
              child: GestureDetector(
                onTap: () => provider.setMode(mode),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: size,
                  height: size,
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? config.color.withValues(alpha: 0.2)
                        : const Color(0xFF1a1a20),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isSelected ? config.color : const Color(0xFF3a3a40),
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      config.icon,
                      size: size * 0.5,
                      color: isSelected ? config.color : const Color(0xFF808090),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// WIDGET: Grid Resolution Selector
// ═══════════════════════════════════════════════════════════════════════════════

/// Dropdown selector for grid resolution
class GridResolutionSelector extends StatelessWidget {
  final EditModeProProvider provider;

  const GridResolutionSelector({
    super.key,
    required this.provider,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: provider,
      builder: (context, _) {
        if (!provider.isGridMode) {
          return const SizedBox.shrink();
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF1a1a20),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFF3a3a40)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Grid resolution dropdown
              DropdownButton<GridResolution>(
                value: provider.gridResolution,
                underline: const SizedBox.shrink(),
                dropdownColor: const Color(0xFF242430),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                ),
                items: GridResolution.values.map((res) {
                  final config = kGridResolutionConfigs[res]!;
                  return DropdownMenuItem(
                    value: res,
                    child: Text('${config.symbol} ${config.name}'),
                  );
                }).toList(),
                onChanged: (res) {
                  if (res != null) provider.setGridResolution(res);
                },
              ),

              const SizedBox(width: 8),

              // Triplet toggle
              _ModifierButton(
                label: '3',
                tooltip: 'Triplet',
                isActive: provider.tripletGrid,
                onTap: provider.toggleTriplet,
              ),

              const SizedBox(width: 4),

              // Dotted toggle
              _ModifierButton(
                label: '.',
                tooltip: 'Dotted',
                isActive: provider.dottedGrid,
                onTap: provider.toggleDotted,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ModifierButton extends StatelessWidget {
  final String label;
  final String tooltip;
  final bool isActive;
  final VoidCallback onTap;

  const _ModifierButton({
    required this.label,
    required this.tooltip,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: isActive
                ? const Color(0xFF4a9eff).withValues(alpha: 0.2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(
              color: isActive
                  ? const Color(0xFF4a9eff)
                  : const Color(0xFF3a3a40),
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isActive
                    ? const Color(0xFF4a9eff)
                    : const Color(0xFF808090),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// WIDGET: Spot Mode Dialog
// ═══════════════════════════════════════════════════════════════════════════════

/// Dialog for entering precise timecode position in Spot mode
class SpotModeDialog extends StatefulWidget {
  final EditModeProProvider provider;
  final void Function(TimecodePosition)? onConfirm;

  const SpotModeDialog({
    super.key,
    required this.provider,
    this.onConfirm,
  });

  @override
  State<SpotModeDialog> createState() => _SpotModeDialogState();
}

class _SpotModeDialogState extends State<SpotModeDialog> {
  late TextEditingController _hoursController;
  late TextEditingController _minutesController;
  late TextEditingController _secondsController;
  late TextEditingController _framesController;

  @override
  void initState() {
    super.initState();
    final pos = widget.provider.spotPosition;
    _hoursController = TextEditingController(text: pos.hours.toString().padLeft(2, '0'));
    _minutesController = TextEditingController(text: pos.minutes.toString().padLeft(2, '0'));
    _secondsController = TextEditingController(text: pos.seconds.toString().padLeft(2, '0'));
    _framesController = TextEditingController(text: pos.frames.toString().padLeft(2, '0'));
  }

  @override
  void dispose() {
    _hoursController.dispose();
    _minutesController.dispose();
    _secondsController.dispose();
    _framesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1a1a20),
      title: const Text(
        'Spot Position',
        style: TextStyle(color: Colors.white),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _TimecodeField(
                controller: _hoursController,
                label: 'HH',
                max: 23,
              ),
              const Text(':', style: TextStyle(color: Colors.white, fontSize: 24)),
              _TimecodeField(
                controller: _minutesController,
                label: 'MM',
                max: 59,
              ),
              const Text(':', style: TextStyle(color: Colors.white, fontSize: 24)),
              _TimecodeField(
                controller: _secondsController,
                label: 'SS',
                max: 59,
              ),
              Text(
                widget.provider.frameRate == FrameRate.fps2997df ? ';' : ':',
                style: const TextStyle(color: Colors.white, fontSize: 24),
              ),
              _TimecodeField(
                controller: _framesController,
                label: 'FF',
                max: 29,
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Frame rate selector
          DropdownButton<FrameRate>(
            value: widget.provider.frameRate,
            dropdownColor: const Color(0xFF242430),
            style: const TextStyle(color: Colors.white),
            items: FrameRate.values.map((rate) {
              return DropdownMenuItem(
                value: rate,
                child: Text(_frameRateLabel(rate)),
              );
            }).toList(),
            onChanged: (rate) {
              if (rate != null) {
                widget.provider.setFrameRate(rate);
                setState(() {});
              }
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final position = TimecodePosition(
              hours: int.tryParse(_hoursController.text) ?? 0,
              minutes: int.tryParse(_minutesController.text) ?? 0,
              seconds: int.tryParse(_secondsController.text) ?? 0,
              frames: int.tryParse(_framesController.text) ?? 0,
            );
            widget.provider.setSpotPosition(position);
            widget.onConfirm?.call(position);
            Navigator.of(context).pop();
          },
          child: const Text('Spot'),
        ),
      ],
    );
  }

  String _frameRateLabel(FrameRate rate) {
    switch (rate) {
      case FrameRate.fps23976:
        return '23.976 fps';
      case FrameRate.fps24:
        return '24 fps';
      case FrameRate.fps25:
        return '25 fps (PAL)';
      case FrameRate.fps2997df:
        return '29.97 fps DF';
      case FrameRate.fps2997nd:
        return '29.97 fps ND';
      case FrameRate.fps30:
        return '30 fps';
    }
  }
}

class _TimecodeField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final int max;

  const _TimecodeField({
    required this.controller,
    required this.label,
    required this.max,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 50,
      child: TextField(
        controller: controller,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 24,
          fontFamily: 'monospace',
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Color(0xFF808090), fontSize: 10),
          enabledBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Color(0xFF4a9eff)),
          ),
          focusedBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Color(0xFF4a9eff), width: 2),
          ),
        ),
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(2),
        ],
      ),
    );
  }
}
