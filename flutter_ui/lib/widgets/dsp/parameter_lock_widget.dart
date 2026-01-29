/// P2.8: Parameter Lock Widget — Lock DSP parameters from changes
///
/// Allows users to lock specific parameters so they won't be affected by:
/// - Preset loading
/// - A/B comparison switching
/// - Automation
/// - Reset operations

import 'package:flutter/material.dart';

/// Locked parameter info
class LockedParameter {
  final String parameterId;
  final String displayName;
  final double lockedValue;
  final DateTime lockedAt;
  final String? category;

  const LockedParameter({
    required this.parameterId,
    required this.displayName,
    required this.lockedValue,
    required this.lockedAt,
    this.category,
  });

  LockedParameter copyWith({
    String? parameterId,
    String? displayName,
    double? lockedValue,
    DateTime? lockedAt,
    String? category,
  }) {
    return LockedParameter(
      parameterId: parameterId ?? this.parameterId,
      displayName: displayName ?? this.displayName,
      lockedValue: lockedValue ?? this.lockedValue,
      lockedAt: lockedAt ?? this.lockedAt,
      category: category ?? this.category,
    );
  }

  Map<String, dynamic> toJson() => {
    'parameterId': parameterId,
    'displayName': displayName,
    'lockedValue': lockedValue,
    'lockedAt': lockedAt.toIso8601String(),
    'category': category,
  };

  factory LockedParameter.fromJson(Map<String, dynamic> json) => LockedParameter(
    parameterId: json['parameterId'] as String,
    displayName: json['displayName'] as String,
    lockedValue: (json['lockedValue'] as num).toDouble(),
    lockedAt: DateTime.tryParse(json['lockedAt'] as String? ?? '') ?? DateTime.now(),
    category: json['category'] as String?,
  );
}

/// Parameter lock state for a DSP processor
class ParameterLockState {
  final String processorId;
  final Set<String> lockedParameterIds;
  final Map<String, LockedParameter> lockedParameters;
  final bool lockAllEnabled;

  const ParameterLockState({
    required this.processorId,
    this.lockedParameterIds = const {},
    this.lockedParameters = const {},
    this.lockAllEnabled = false,
  });

  bool isLocked(String parameterId) => lockedParameterIds.contains(parameterId);

  LockedParameter? getLockedParameter(String parameterId) => lockedParameters[parameterId];

  ParameterLockState copyWith({
    String? processorId,
    Set<String>? lockedParameterIds,
    Map<String, LockedParameter>? lockedParameters,
    bool? lockAllEnabled,
  }) {
    return ParameterLockState(
      processorId: processorId ?? this.processorId,
      lockedParameterIds: lockedParameterIds ?? this.lockedParameterIds,
      lockedParameters: lockedParameters ?? this.lockedParameters,
      lockAllEnabled: lockAllEnabled ?? this.lockAllEnabled,
    );
  }
}

/// Parameter lock manager mixin for DSP panels
mixin ParameterLockMixin<T extends StatefulWidget> on State<T> {
  ParameterLockState _lockState = const ParameterLockState(processorId: '');

  ParameterLockState get lockState => _lockState;

  void initLockState(String processorId) {
    _lockState = ParameterLockState(processorId: processorId);
  }

  bool isParameterLocked(String parameterId) => _lockState.isLocked(parameterId);

  void toggleParameterLock(String parameterId, String displayName, double currentValue, {String? category}) {
    final newLockedIds = Set<String>.from(_lockState.lockedParameterIds);
    final newLockedParams = Map<String, LockedParameter>.from(_lockState.lockedParameters);

    if (newLockedIds.contains(parameterId)) {
      newLockedIds.remove(parameterId);
      newLockedParams.remove(parameterId);
    } else {
      newLockedIds.add(parameterId);
      newLockedParams[parameterId] = LockedParameter(
        parameterId: parameterId,
        displayName: displayName,
        lockedValue: currentValue,
        lockedAt: DateTime.now(),
        category: category,
      );
    }

    setState(() {
      _lockState = _lockState.copyWith(
        lockedParameterIds: newLockedIds,
        lockedParameters: newLockedParams,
      );
    });
  }

  void lockAllParameters(Map<String, LockableParameter> parameters) {
    final newLockedIds = <String>{};
    final newLockedParams = <String, LockedParameter>{};

    for (final entry in parameters.entries) {
      newLockedIds.add(entry.key);
      newLockedParams[entry.key] = LockedParameter(
        parameterId: entry.key,
        displayName: entry.value.displayName,
        lockedValue: entry.value.currentValue,
        lockedAt: DateTime.now(),
        category: entry.value.category,
      );
    }

    setState(() {
      _lockState = _lockState.copyWith(
        lockedParameterIds: newLockedIds,
        lockedParameters: newLockedParams,
        lockAllEnabled: true,
      );
    });
  }

  void unlockAllParameters() {
    setState(() {
      _lockState = _lockState.copyWith(
        lockedParameterIds: {},
        lockedParameters: {},
        lockAllEnabled: false,
      );
    });
  }

  /// Get value, respecting lock state
  double getEffectiveValue(String parameterId, double newValue) {
    if (_lockState.isLocked(parameterId)) {
      return _lockState.lockedParameters[parameterId]?.lockedValue ?? newValue;
    }
    return newValue;
  }
}

/// Parameter info for lockable parameters
class LockableParameter {
  final String displayName;
  final double currentValue;
  final String? category;

  const LockableParameter({
    required this.displayName,
    required this.currentValue,
    this.category,
  });
}

/// Parameter lock indicator badge
class ParameterLockBadge extends StatelessWidget {
  final bool isLocked;
  final VoidCallback? onTap;
  final double size;

  const ParameterLockBadge({
    super.key,
    required this.isLocked,
    this.onTap,
    this.size = 16,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: isLocked ? 'Unlock parameter' : 'Lock parameter',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: isLocked
                ? const Color(0xFFFF9040).withValues(alpha: 0.2)
                : const Color(0xFF1A1A20),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isLocked ? const Color(0xFFFF9040) : const Color(0xFF2A2A35),
            ),
          ),
          child: Icon(
            isLocked ? Icons.lock : Icons.lock_open,
            size: size * 0.65,
            color: isLocked ? const Color(0xFFFF9040) : const Color(0xFF505060),
          ),
        ),
      ),
    );
  }
}

/// Parameter lock toolbar for DSP panels
class ParameterLockToolbar extends StatelessWidget {
  final int lockedCount;
  final int totalCount;
  final bool allLocked;
  final VoidCallback? onLockAll;
  final VoidCallback? onUnlockAll;
  final VoidCallback? onShowLockedList;

  const ParameterLockToolbar({
    super.key,
    required this.lockedCount,
    required this.totalCount,
    required this.allLocked,
    this.onLockAll,
    this.onUnlockAll,
    this.onShowLockedList,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A20),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF2A2A35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.lock_outline,
            size: 12,
            color: lockedCount > 0 ? const Color(0xFFFF9040) : const Color(0xFF505060),
          ),
          const SizedBox(width: 6),
          Text(
            '$lockedCount/$totalCount locked',
            style: TextStyle(
              fontSize: 10,
              color: lockedCount > 0 ? const Color(0xFFFF9040) : const Color(0xFF808090),
            ),
          ),
          if (lockedCount > 0) ...[
            const SizedBox(width: 8),
            _buildButton(
              icon: Icons.list,
              tooltip: 'View locked parameters',
              onTap: onShowLockedList,
            ),
          ],
          const SizedBox(width: 4),
          _buildButton(
            icon: allLocked ? Icons.lock_open : Icons.lock,
            tooltip: allLocked ? 'Unlock all' : 'Lock all',
            onTap: allLocked ? onUnlockAll : onLockAll,
            isActive: allLocked,
          ),
        ],
      ),
    );
  }

  Widget _buildButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
    bool isActive = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: isActive
                ? const Color(0xFFFF9040).withValues(alpha: 0.2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            icon,
            size: 12,
            color: isActive ? const Color(0xFFFF9040) : const Color(0xFF606070),
          ),
        ),
      ),
    );
  }
}

/// Locked parameters list dialog
class LockedParametersDialog extends StatelessWidget {
  final List<LockedParameter> lockedParameters;
  final Function(String parameterId)? onUnlock;

  const LockedParametersDialog({
    super.key,
    required this.lockedParameters,
    this.onUnlock,
  });

  static Future<void> show(
    BuildContext context, {
    required List<LockedParameter> lockedParameters,
    Function(String parameterId)? onUnlock,
  }) {
    return showDialog(
      context: context,
      builder: (context) => LockedParametersDialog(
        lockedParameters: lockedParameters,
        onUnlock: onUnlock,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Group by category
    final grouped = <String?, List<LockedParameter>>{};
    for (final param in lockedParameters) {
      grouped.putIfAbsent(param.category, () => []).add(param);
    }

    return Dialog(
      backgroundColor: const Color(0xFF121216),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Container(
        width: 360,
        constraints: const BoxConstraints(maxHeight: 450),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: const BoxDecoration(
                color: Color(0xFF1A1A20),
                borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lock, size: 16, color: Color(0xFFFF9040)),
                  const SizedBox(width: 8),
                  const Text(
                    'Locked Parameters',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFE0E0E8),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF9040).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${lockedParameters.length}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFFF9040),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Content
            Flexible(
              child: lockedParameters.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.lock_open, size: 32, color: Color(0xFF404050)),
                          SizedBox(height: 8),
                          Text(
                            'No parameters locked',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF606070),
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.all(12),
                      children: grouped.entries.map((entry) {
                        return _buildCategorySection(entry.key, entry.value);
                      }).toList(),
                    ),
            ),
            // Footer
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFF2A2A35))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'Close',
                      style: TextStyle(color: Color(0xFF808090)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategorySection(String? category, List<LockedParameter> params) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (category != null) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 6, top: 8),
            child: Text(
              category.toUpperCase(),
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: Color(0xFF606070),
                letterSpacing: 1,
              ),
            ),
          ),
        ],
        ...params.map((param) => _buildParameterItem(param)),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildParameterItem(LockedParameter param) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A20),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF2A2A35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock, size: 12, color: Color(0xFFFF9040)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  param.displayName,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFFE0E0E8),
                  ),
                ),
                Text(
                  'Value: ${param.lockedValue.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 9,
                    color: Color(0xFF808090),
                  ),
                ),
              ],
            ),
          ),
          if (onUnlock != null)
            Builder(
              builder: (context) => IconButton(
                icon: const Icon(Icons.lock_open, size: 14),
                color: const Color(0xFF606070),
                tooltip: 'Unlock',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                onPressed: () {
                  onUnlock!(param.parameterId);
                  Navigator.pop(context);
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// Lockable slider with integrated lock badge
class LockableSlider extends StatelessWidget {
  final String parameterId;
  final String label;
  final double value;
  final double min;
  final double max;
  final bool isLocked;
  final ValueChanged<double>? onChanged;
  final VoidCallback? onLockToggle;
  final String? category;
  final String? suffix;

  const LockableSlider({
    super.key,
    required this.parameterId,
    required this.label,
    required this.value,
    this.min = 0.0,
    this.max = 1.0,
    this.isLocked = false,
    this.onChanged,
    this.onLockToggle,
    this.category,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          // Lock badge
          ParameterLockBadge(
            isLocked: isLocked,
            onTap: onLockToggle,
            size: 18,
          ),
          const SizedBox(width: 8),
          // Label
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: isLocked ? const Color(0xFFFF9040) : const Color(0xFFB0B0B8),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Slider
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                activeTrackColor: isLocked
                    ? const Color(0xFFFF9040).withValues(alpha: 0.5)
                    : const Color(0xFF4A9EFF),
                inactiveTrackColor: const Color(0xFF2A2A35),
                thumbColor: isLocked ? const Color(0xFFFF9040) : const Color(0xFF4A9EFF),
              ),
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                onChanged: isLocked ? null : onChanged,
              ),
            ),
          ),
          // Value display
          SizedBox(
            width: 50,
            child: Text(
              '${value.toStringAsFixed(1)}${suffix ?? ''}',
              style: TextStyle(
                fontSize: 10,
                fontFamily: 'monospace',
                color: isLocked ? const Color(0xFFFF9040) : const Color(0xFF808090),
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
