// Direct Offline Processing (DOP) Provider
//
// Cubase-style non-destructive offline processing system:
//
// ## What is Direct Offline Processing?
// Apply effects to audio clips offline (not real-time) while keeping
// the processing chain editable. The original audio is preserved.
//
// ## Key Features:
// 1. Non-destructive - original audio always preserved
// 2. Editable chain - reorder, bypass, remove effects
// 3. Audition - preview before applying
// 4. Batch processing - apply to multiple clips
// 5. Favorites - save common processing chains
// 6. Full undo history per clip
//
// ## Workflow:
// 1. Select clip(s)
// 2. Open DOP panel (Audio > Direct Offline Processing)
// 3. Add effects to chain
// 4. Audition result
// 5. Apply (renders to new audio, keeps chain for editing)
//
// ## Supported Processes:
// - Gain, Normalize, DC Offset
// - Fade In/Out, Crossfade
// - Time Stretch, Pitch Shift
// - Reverse, Invert Phase
// - EQ, Compression, Limiting
// - Noise Reduction, De-essing
// - Plugin effects (VST3, AU)

import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════════

/// Process category
enum DopCategory {
  gain,
  time,
  pitch,
  effects,
  restoration,
  plugin,
}

/// Base class for offline process
abstract class OfflineProcess {
  /// Unique ID
  String get id;

  /// Display name
  String get name;

  /// Category
  DopCategory get category;

  /// Icon
  IconData get icon;

  /// Is this process bypassed
  bool bypassed = false;

  /// Get parameters map for serialization
  Map<String, dynamic> toParams();

  /// Apply from parameters
  void fromParams(Map<String, dynamic> params);

  /// Create a copy
  OfflineProcess copy();
}

// ═══════════════════════════════════════════════════════════════════════════════
// BUILT-IN PROCESSES
// ═══════════════════════════════════════════════════════════════════════════════

/// Gain adjustment
class GainProcess extends OfflineProcess {
  double gainDb;
  bool normalize;
  double targetLufs;

  GainProcess({
    this.gainDb = 0.0,
    this.normalize = false,
    this.targetLufs = -14.0,
  });

  @override
  String get id => 'gain';
  @override
  String get name => 'Gain';
  @override
  DopCategory get category => DopCategory.gain;
  @override
  IconData get icon => Icons.volume_up;

  @override
  Map<String, dynamic> toParams() => {
        'gainDb': gainDb,
        'normalize': normalize,
        'targetLufs': targetLufs,
      };

  @override
  void fromParams(Map<String, dynamic> params) {
    gainDb = params['gainDb'] ?? 0.0;
    normalize = params['normalize'] ?? false;
    targetLufs = params['targetLufs'] ?? -14.0;
  }

  @override
  OfflineProcess copy() => GainProcess(
        gainDb: gainDb,
        normalize: normalize,
        targetLufs: targetLufs,
      )..bypassed = bypassed;
}

/// Normalize
class NormalizeProcess extends OfflineProcess {
  double targetPeakDb;
  bool useTruePeak;
  double targetLufs;
  bool useLufs;

  NormalizeProcess({
    this.targetPeakDb = -1.0,
    this.useTruePeak = true,
    this.targetLufs = -14.0,
    this.useLufs = false,
  });

  @override
  String get id => 'normalize';
  @override
  String get name => 'Normalize';
  @override
  DopCategory get category => DopCategory.gain;
  @override
  IconData get icon => Icons.equalizer;

  @override
  Map<String, dynamic> toParams() => {
        'targetPeakDb': targetPeakDb,
        'useTruePeak': useTruePeak,
        'targetLufs': targetLufs,
        'useLufs': useLufs,
      };

  @override
  void fromParams(Map<String, dynamic> params) {
    targetPeakDb = params['targetPeakDb'] ?? -1.0;
    useTruePeak = params['useTruePeak'] ?? true;
    targetLufs = params['targetLufs'] ?? -14.0;
    useLufs = params['useLufs'] ?? false;
  }

  @override
  OfflineProcess copy() => NormalizeProcess(
        targetPeakDb: targetPeakDb,
        useTruePeak: useTruePeak,
        targetLufs: targetLufs,
        useLufs: useLufs,
      )..bypassed = bypassed;
}

/// Fade In/Out
class FadeProcess extends OfflineProcess {
  double fadeInMs;
  double fadeOutMs;
  String fadeInCurve; // linear, exponential, scurve
  String fadeOutCurve;

  FadeProcess({
    this.fadeInMs = 10.0,
    this.fadeOutMs = 10.0,
    this.fadeInCurve = 'linear',
    this.fadeOutCurve = 'linear',
  });

  @override
  String get id => 'fade';
  @override
  String get name => 'Fade';
  @override
  DopCategory get category => DopCategory.gain;
  @override
  IconData get icon => Icons.gradient;

  @override
  Map<String, dynamic> toParams() => {
        'fadeInMs': fadeInMs,
        'fadeOutMs': fadeOutMs,
        'fadeInCurve': fadeInCurve,
        'fadeOutCurve': fadeOutCurve,
      };

  @override
  void fromParams(Map<String, dynamic> params) {
    fadeInMs = params['fadeInMs'] ?? 10.0;
    fadeOutMs = params['fadeOutMs'] ?? 10.0;
    fadeInCurve = params['fadeInCurve'] ?? 'linear';
    fadeOutCurve = params['fadeOutCurve'] ?? 'linear';
  }

  @override
  OfflineProcess copy() => FadeProcess(
        fadeInMs: fadeInMs,
        fadeOutMs: fadeOutMs,
        fadeInCurve: fadeInCurve,
        fadeOutCurve: fadeOutCurve,
      )..bypassed = bypassed;
}

/// Time Stretch
class TimeStretchProcess extends OfflineProcess {
  double stretchRatio; // 1.0 = original, 2.0 = double length
  bool preservePitch;
  String algorithm; // elastique, zplane, basic

  TimeStretchProcess({
    this.stretchRatio = 1.0,
    this.preservePitch = true,
    this.algorithm = 'elastique',
  });

  @override
  String get id => 'timestretch';
  @override
  String get name => 'Time Stretch';
  @override
  DopCategory get category => DopCategory.time;
  @override
  IconData get icon => Icons.swap_horiz;

  @override
  Map<String, dynamic> toParams() => {
        'stretchRatio': stretchRatio,
        'preservePitch': preservePitch,
        'algorithm': algorithm,
      };

  @override
  void fromParams(Map<String, dynamic> params) {
    stretchRatio = params['stretchRatio'] ?? 1.0;
    preservePitch = params['preservePitch'] ?? true;
    algorithm = params['algorithm'] ?? 'elastique';
  }

  @override
  OfflineProcess copy() => TimeStretchProcess(
        stretchRatio: stretchRatio,
        preservePitch: preservePitch,
        algorithm: algorithm,
      )..bypassed = bypassed;
}

/// Pitch Shift
class PitchShiftProcess extends OfflineProcess {
  double semitones;
  double cents;
  bool preserveFormants;
  String algorithm;

  PitchShiftProcess({
    this.semitones = 0.0,
    this.cents = 0.0,
    this.preserveFormants = true,
    this.algorithm = 'elastique',
  });

  @override
  String get id => 'pitchshift';
  @override
  String get name => 'Pitch Shift';
  @override
  DopCategory get category => DopCategory.pitch;
  @override
  IconData get icon => Icons.music_note;

  @override
  Map<String, dynamic> toParams() => {
        'semitones': semitones,
        'cents': cents,
        'preserveFormants': preserveFormants,
        'algorithm': algorithm,
      };

  @override
  void fromParams(Map<String, dynamic> params) {
    semitones = params['semitones'] ?? 0.0;
    cents = params['cents'] ?? 0.0;
    preserveFormants = params['preserveFormants'] ?? true;
    algorithm = params['algorithm'] ?? 'elastique';
  }

  @override
  OfflineProcess copy() => PitchShiftProcess(
        semitones: semitones,
        cents: cents,
        preserveFormants: preserveFormants,
        algorithm: algorithm,
      )..bypassed = bypassed;
}

/// Reverse
class ReverseProcess extends OfflineProcess {
  ReverseProcess();

  @override
  String get id => 'reverse';
  @override
  String get name => 'Reverse';
  @override
  DopCategory get category => DopCategory.time;
  @override
  IconData get icon => Icons.swap_horizontal_circle;

  @override
  Map<String, dynamic> toParams() => {};

  @override
  void fromParams(Map<String, dynamic> params) {}

  @override
  OfflineProcess copy() => ReverseProcess()..bypassed = bypassed;
}

/// Phase Invert
class PhaseInvertProcess extends OfflineProcess {
  bool leftChannel;
  bool rightChannel;

  PhaseInvertProcess({
    this.leftChannel = true,
    this.rightChannel = true,
  });

  @override
  String get id => 'phaseinvert';
  @override
  String get name => 'Phase Invert';
  @override
  DopCategory get category => DopCategory.effects;
  @override
  IconData get icon => Icons.sync_alt;

  @override
  Map<String, dynamic> toParams() => {
        'leftChannel': leftChannel,
        'rightChannel': rightChannel,
      };

  @override
  void fromParams(Map<String, dynamic> params) {
    leftChannel = params['leftChannel'] ?? true;
    rightChannel = params['rightChannel'] ?? true;
  }

  @override
  OfflineProcess copy() => PhaseInvertProcess(
        leftChannel: leftChannel,
        rightChannel: rightChannel,
      )..bypassed = bypassed;
}

/// DC Offset Removal
class DcOffsetProcess extends OfflineProcess {
  DcOffsetProcess();

  @override
  String get id => 'dcoffset';
  @override
  String get name => 'Remove DC Offset';
  @override
  DopCategory get category => DopCategory.restoration;
  @override
  IconData get icon => Icons.horizontal_rule;

  @override
  Map<String, dynamic> toParams() => {};

  @override
  void fromParams(Map<String, dynamic> params) {}

  @override
  OfflineProcess copy() => DcOffsetProcess()..bypassed = bypassed;
}

/// Silence
class SilenceProcess extends OfflineProcess {
  double thresholdDb;
  double minDurationMs;

  SilenceProcess({
    this.thresholdDb = -60.0,
    this.minDurationMs = 100.0,
  });

  @override
  String get id => 'silence';
  @override
  String get name => 'Detect Silence';
  @override
  DopCategory get category => DopCategory.restoration;
  @override
  IconData get icon => Icons.volume_off;

  @override
  Map<String, dynamic> toParams() => {
        'thresholdDb': thresholdDb,
        'minDurationMs': minDurationMs,
      };

  @override
  void fromParams(Map<String, dynamic> params) {
    thresholdDb = params['thresholdDb'] ?? -60.0;
    minDurationMs = params['minDurationMs'] ?? 100.0;
  }

  @override
  OfflineProcess copy() => SilenceProcess(
        thresholdDb: thresholdDb,
        minDurationMs: minDurationMs,
      )..bypassed = bypassed;
}

/// Plugin process (wraps VST3/AU)
class PluginProcess extends OfflineProcess {
  final String pluginId;
  final String pluginName;
  Map<String, dynamic> pluginState;

  PluginProcess({
    required this.pluginId,
    required this.pluginName,
    this.pluginState = const {},
  });

  @override
  String get id => 'plugin_$pluginId';
  @override
  String get name => pluginName;
  @override
  DopCategory get category => DopCategory.plugin;
  @override
  IconData get icon => Icons.extension;

  @override
  Map<String, dynamic> toParams() => {
        'pluginId': pluginId,
        'pluginName': pluginName,
        'pluginState': pluginState,
      };

  @override
  void fromParams(Map<String, dynamic> params) {
    pluginState = Map<String, dynamic>.from(params['pluginState'] ?? {});
  }

  @override
  OfflineProcess copy() => PluginProcess(
        pluginId: pluginId,
        pluginName: pluginName,
        pluginState: Map<String, dynamic>.from(pluginState),
      )..bypassed = bypassed;
}

// ═══════════════════════════════════════════════════════════════════════════════
// PROCESSING CHAIN
// ═══════════════════════════════════════════════════════════════════════════════

/// A chain of offline processes applied to a clip
class DopChain {
  final String clipId;
  final List<OfflineProcess> processes;
  final DateTime createdAt;
  DateTime? appliedAt;

  DopChain({
    required this.clipId,
    List<OfflineProcess>? processes,
    DateTime? createdAt,
    this.appliedAt,
  })  : processes = processes ?? [],
        createdAt = createdAt ?? DateTime.now();

  bool get isEmpty => processes.isEmpty;
  int get length => processes.length;

  /// Add process to chain
  void add(OfflineProcess process) {
    processes.add(process);
  }

  /// Remove process at index
  void removeAt(int index) {
    if (index >= 0 && index < processes.length) {
      processes.removeAt(index);
    }
  }

  /// Move process from one index to another
  void move(int from, int to) {
    if (from < 0 || from >= processes.length) return;
    if (to < 0 || to >= processes.length) return;

    final process = processes.removeAt(from);
    processes.insert(to, process);
  }

  /// Toggle bypass on process at index
  void toggleBypass(int index) {
    if (index >= 0 && index < processes.length) {
      processes[index].bypassed = !processes[index].bypassed;
    }
  }

  /// Clear all processes
  void clear() {
    processes.clear();
    appliedAt = null;
  }

  /// Create a copy of this chain
  DopChain copy() {
    return DopChain(
      clipId: clipId,
      processes: processes.map((p) => p.copy()).toList(),
      createdAt: createdAt,
      appliedAt: appliedAt,
    );
  }

  /// Serialize to JSON
  Map<String, dynamic> toJson() {
    return {
      'clipId': clipId,
      'processes': processes
          .map((p) => {
                'type': p.id,
                'bypassed': p.bypassed,
                'params': p.toParams(),
              })
          .toList(),
      'createdAt': createdAt.toIso8601String(),
      'appliedAt': appliedAt?.toIso8601String(),
    };
  }
}

/// Favorite processing chain (saved preset)
class DopFavorite {
  final String id;
  final String name;
  final List<OfflineProcess> processes;
  final DateTime createdAt;

  DopFavorite({
    required this.id,
    required this.name,
    required this.processes,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
}

// ═══════════════════════════════════════════════════════════════════════════════
// PROVIDER
// ═══════════════════════════════════════════════════════════════════════════════

/// Direct Offline Processing Provider
class DirectOfflineProcessingProvider extends ChangeNotifier {
  // Active chains per clip
  final Map<String, DopChain> _chains = {};

  // Currently selected clip for editing
  String? _selectedClipId;

  // Favorites
  final List<DopFavorite> _favorites = [];

  // Undo history per chain
  final Map<String, List<DopChain>> _undoHistory = {};
  final Map<String, List<DopChain>> _redoHistory = {};

  // Audition state
  bool _isAuditioning = false;
  double _auditionProgress = 0.0;

  // Callbacks
  void Function(String clipId, DopChain chain)? onApply;
  void Function(String clipId)? onRevert;
  void Function(String clipId, DopChain chain)? onAuditionStart;
  void Function()? onAuditionStop;

  // ═══ Getters ═══

  String? get selectedClipId => _selectedClipId;
  DopChain? get currentChain =>
      _selectedClipId != null ? _chains[_selectedClipId] : null;
  List<DopFavorite> get favorites => List.unmodifiable(_favorites);
  bool get isAuditioning => _isAuditioning;
  double get auditionProgress => _auditionProgress;

  bool get canUndo =>
      _selectedClipId != null &&
      (_undoHistory[_selectedClipId]?.isNotEmpty ?? false);
  bool get canRedo =>
      _selectedClipId != null &&
      (_redoHistory[_selectedClipId]?.isNotEmpty ?? false);

  // ═══ Clip Selection ═══

  void selectClip(String clipId) {
    _selectedClipId = clipId;
    if (!_chains.containsKey(clipId)) {
      _chains[clipId] = DopChain(clipId: clipId);
    }
    notifyListeners();
  }

  void deselectClip() {
    _selectedClipId = null;
    notifyListeners();
  }

  // ═══ Chain Editing ═══

  void addProcess(OfflineProcess process) {
    if (_selectedClipId == null) return;

    _saveUndoState();
    currentChain?.add(process);
    notifyListeners();
  }

  void removeProcess(int index) {
    if (_selectedClipId == null) return;

    _saveUndoState();
    currentChain?.removeAt(index);
    notifyListeners();
  }

  void moveProcess(int from, int to) {
    if (_selectedClipId == null) return;

    _saveUndoState();
    currentChain?.move(from, to);
    notifyListeners();
  }

  void toggleProcessBypass(int index) {
    if (_selectedClipId == null) return;

    _saveUndoState();
    currentChain?.toggleBypass(index);
    notifyListeners();
  }

  void clearChain() {
    if (_selectedClipId == null) return;

    _saveUndoState();
    currentChain?.clear();
    notifyListeners();
  }

  // ═══ Undo/Redo ═══

  void _saveUndoState() {
    if (_selectedClipId == null || currentChain == null) return;

    _undoHistory[_selectedClipId!] ??= [];
    _undoHistory[_selectedClipId!]!.add(currentChain!.copy());

    // Clear redo on new action
    _redoHistory[_selectedClipId!]?.clear();

    // Limit history size
    if (_undoHistory[_selectedClipId!]!.length > 50) {
      _undoHistory[_selectedClipId!]!.removeAt(0);
    }
  }

  void undo() {
    if (!canUndo || _selectedClipId == null) return;

    final history = _undoHistory[_selectedClipId!]!;
    final current = currentChain!.copy();

    _redoHistory[_selectedClipId!] ??= [];
    _redoHistory[_selectedClipId!]!.add(current);

    _chains[_selectedClipId!] = history.removeLast();
    notifyListeners();
  }

  void redo() {
    if (!canRedo || _selectedClipId == null) return;

    final redoList = _redoHistory[_selectedClipId!]!;
    final current = currentChain!.copy();

    _undoHistory[_selectedClipId!] ??= [];
    _undoHistory[_selectedClipId!]!.add(current);

    _chains[_selectedClipId!] = redoList.removeLast();
    notifyListeners();
  }

  // ═══ Apply/Revert ═══

  void apply() {
    if (_selectedClipId == null || currentChain == null) return;
    if (currentChain!.isEmpty) return;

    currentChain!.appliedAt = DateTime.now();
    onApply?.call(_selectedClipId!, currentChain!);
    notifyListeners();
  }

  void revert() {
    if (_selectedClipId == null) return;

    onRevert?.call(_selectedClipId!);
    _chains[_selectedClipId!] = DopChain(clipId: _selectedClipId!);
    _undoHistory[_selectedClipId!]?.clear();
    _redoHistory[_selectedClipId!]?.clear();
    notifyListeners();
  }

  // ═══ Audition ═══

  void startAudition() {
    if (_selectedClipId == null || currentChain == null) return;

    _isAuditioning = true;
    _auditionProgress = 0.0;
    onAuditionStart?.call(_selectedClipId!, currentChain!);
    notifyListeners();
  }

  void stopAudition() {
    _isAuditioning = false;
    _auditionProgress = 0.0;
    onAuditionStop?.call();
    notifyListeners();
  }

  void updateAuditionProgress(double progress) {
    _auditionProgress = progress.clamp(0.0, 1.0);
    notifyListeners();
  }

  // ═══ Favorites ═══

  void saveFavorite(String name) {
    if (currentChain == null || currentChain!.isEmpty) return;

    final favorite = DopFavorite(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      processes: currentChain!.processes.map((p) => p.copy()).toList(),
    );

    _favorites.add(favorite);
    notifyListeners();
  }

  void loadFavorite(DopFavorite favorite) {
    if (_selectedClipId == null) return;

    _saveUndoState();
    _chains[_selectedClipId!] = DopChain(
      clipId: _selectedClipId!,
      processes: favorite.processes.map((p) => p.copy()).toList(),
    );
    notifyListeners();
  }

  void deleteFavorite(String favoriteId) {
    _favorites.removeWhere((f) => f.id == favoriteId);
    notifyListeners();
  }

  // ═══ Available Processes ═══

  static List<OfflineProcess> get availableProcesses => [
        GainProcess(),
        NormalizeProcess(),
        FadeProcess(),
        TimeStretchProcess(),
        PitchShiftProcess(),
        ReverseProcess(),
        PhaseInvertProcess(),
        DcOffsetProcess(),
        SilenceProcess(),
      ];

  static List<OfflineProcess> getProcessesByCategory(DopCategory category) {
    return availableProcesses.where((p) => p.category == category).toList();
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// WIDGET: DOP Panel
// ═══════════════════════════════════════════════════════════════════════════════

/// Direct Offline Processing panel widget
class DopPanel extends StatelessWidget {
  final DirectOfflineProcessingProvider provider;

  const DopPanel({
    super.key,
    required this.provider,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: provider,
      builder: (context, _) {
        if (provider.selectedClipId == null) {
          return const Center(
            child: Text(
              'Select a clip to process',
              style: TextStyle(color: Color(0xFF808090)),
            ),
          );
        }

        return Column(
          children: [
            // Toolbar
            _DopToolbar(provider: provider),

            // Process chain
            Expanded(
              child: _ProcessChainList(provider: provider),
            ),

            // Add process button
            _AddProcessButton(provider: provider),

            // Apply/Audition buttons
            _ActionButtons(provider: provider),
          ],
        );
      },
    );
  }
}

class _DopToolbar extends StatelessWidget {
  final DirectOfflineProcessingProvider provider;

  const _DopToolbar({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF1a1a20),
        border: Border(bottom: BorderSide(color: Color(0xFF3a3a40))),
      ),
      child: Row(
        children: [
          const Text(
            'Direct Offline Processing',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.undo, size: 16),
            onPressed: provider.canUndo ? provider.undo : null,
            tooltip: 'Undo',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          ),
          IconButton(
            icon: const Icon(Icons.redo, size: 16),
            onPressed: provider.canRedo ? provider.redo : null,
            tooltip: 'Redo',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 16),
            onPressed:
                provider.currentChain?.isEmpty == false ? provider.clearChain : null,
            tooltip: 'Clear Chain',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          ),
        ],
      ),
    );
  }
}

class _ProcessChainList extends StatelessWidget {
  final DirectOfflineProcessingProvider provider;

  const _ProcessChainList({required this.provider});

  @override
  Widget build(BuildContext context) {
    final chain = provider.currentChain;
    if (chain == null || chain.isEmpty) {
      return const Center(
        child: Text(
          'No processes added\nClick + to add',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF606070)),
        ),
      );
    }

    return ReorderableListView.builder(
      itemCount: chain.length,
      onReorder: provider.moveProcess,
      itemBuilder: (context, index) {
        final process = chain.processes[index];
        return _ProcessListItem(
          key: ValueKey('${process.id}_$index'),
          process: process,
          index: index,
          onToggleBypass: () => provider.toggleProcessBypass(index),
          onRemove: () => provider.removeProcess(index),
        );
      },
    );
  }
}

class _ProcessListItem extends StatelessWidget {
  final OfflineProcess process;
  final int index;
  final VoidCallback onToggleBypass;
  final VoidCallback onRemove;

  const _ProcessListItem({
    super.key,
    required this.process,
    required this.index,
    required this.onToggleBypass,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: process.bypassed
            ? const Color(0xFF1a1a20)
            : const Color(0xFF242430),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: process.bypassed
              ? const Color(0xFF3a3a40)
              : const Color(0xFF4a9eff),
        ),
      ),
      child: Row(
        children: [
          // Drag handle
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Icon(Icons.drag_handle, size: 16, color: Color(0xFF606070)),
          ),

          // Process icon
          Icon(
            process.icon,
            size: 16,
            color: process.bypassed
                ? const Color(0xFF606070)
                : const Color(0xFF4a9eff),
          ),
          const SizedBox(width: 8),

          // Process name
          Expanded(
            child: Text(
              process.name,
              style: TextStyle(
                fontSize: 12,
                color: process.bypassed
                    ? const Color(0xFF606070)
                    : Colors.white,
              ),
            ),
          ),

          // Bypass button
          IconButton(
            icon: Icon(
              process.bypassed ? Icons.toggle_off : Icons.toggle_on,
              size: 20,
              color: process.bypassed
                  ? const Color(0xFF606070)
                  : const Color(0xFF40ff90),
            ),
            onPressed: onToggleBypass,
            tooltip: process.bypassed ? 'Enable' : 'Bypass',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),

          // Remove button
          IconButton(
            icon: const Icon(Icons.close, size: 16, color: Color(0xFF808090)),
            onPressed: onRemove,
            tooltip: 'Remove',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }
}

class _AddProcessButton extends StatelessWidget {
  final DirectOfflineProcessingProvider provider;

  const _AddProcessButton({required this.provider});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<OfflineProcess>(
      tooltip: 'Add Process',
      offset: const Offset(0, -200),
      itemBuilder: (context) {
        return DirectOfflineProcessingProvider.availableProcesses.map((process) {
          return PopupMenuItem<OfflineProcess>(
            value: process,
            child: Row(
              children: [
                Icon(process.icon, size: 16),
                const SizedBox(width: 8),
                Text(process.name),
              ],
            ),
          );
        }).toList();
      },
      onSelected: (process) => provider.addProcess(process.copy()),
      child: Container(
        height: 36,
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF242430),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFF4a9eff)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, size: 16, color: Color(0xFF4a9eff)),
            SizedBox(width: 4),
            Text(
              'Add Process',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF4a9eff),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButtons extends StatelessWidget {
  final DirectOfflineProcessingProvider provider;

  const _ActionButtons({required this.provider});

  @override
  Widget build(BuildContext context) {
    final hasProcesses = provider.currentChain?.isEmpty == false;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: const BoxDecoration(
        color: Color(0xFF1a1a20),
        border: Border(top: BorderSide(color: Color(0xFF3a3a40))),
      ),
      child: Row(
        children: [
          // Audition button
          Expanded(
            child: ElevatedButton.icon(
              onPressed: hasProcesses
                  ? (provider.isAuditioning
                      ? provider.stopAudition
                      : provider.startAudition)
                  : null,
              icon: Icon(
                provider.isAuditioning ? Icons.stop : Icons.headphones,
                size: 16,
              ),
              label: Text(provider.isAuditioning ? 'Stop' : 'Audition'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF242430),
                foregroundColor: const Color(0xFF4a9eff),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Apply button
          Expanded(
            child: ElevatedButton.icon(
              onPressed: hasProcesses ? provider.apply : null,
              icon: const Icon(Icons.check, size: 16),
              label: const Text('Apply'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF40ff90),
                foregroundColor: Colors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
