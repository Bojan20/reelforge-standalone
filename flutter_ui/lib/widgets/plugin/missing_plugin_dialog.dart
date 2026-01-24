/// Missing Plugin Dialog
///
/// Dialog shown when loading a project with missing plugins.
/// Allows user to continue with preserved state, use freeze audio,
/// or replace with alternatives.
///
/// Documentation: .claude/architecture/PLUGIN_STATE_SYSTEM.md

import 'package:flutter/material.dart';

import '../../models/plugin_manifest.dart';
import '../../services/missing_plugin_detector.dart';

// =============================================================================
// MISSING PLUGIN DIALOG
// =============================================================================

/// Result of the missing plugin dialog
enum MissingPluginDialogResult {
  /// Continue loading with missing plugins (state preserved)
  continueWithMissing,

  /// Cancel project loading
  cancel,

  /// User made replacements - check replacements map
  replaced,
}

/// Dialog result with optional replacements
class MissingPluginDialogResponse {
  final MissingPluginDialogResult result;

  /// Map of original plugin UID -> replacement plugin UID
  final Map<String, String> replacements;

  /// Plugins to use freeze audio for
  final Set<String> useFreezeFor;

  const MissingPluginDialogResponse({
    required this.result,
    this.replacements = const {},
    this.useFreezeFor = const {},
  });
}

/// Dialog for handling missing plugins when loading a project
class MissingPluginDialog extends StatefulWidget {
  final MissingPluginReport report;
  final String projectName;

  const MissingPluginDialog({
    super.key,
    required this.report,
    required this.projectName,
  });

  /// Show the dialog and return the user's choice
  static Future<MissingPluginDialogResponse?> show(
    BuildContext context, {
    required MissingPluginReport report,
    required String projectName,
  }) async {
    return showDialog<MissingPluginDialogResponse>(
      context: context,
      barrierDismissible: false,
      builder: (context) => MissingPluginDialog(
        report: report,
        projectName: projectName,
      ),
    );
  }

  @override
  State<MissingPluginDialog> createState() => _MissingPluginDialogState();
}

class _MissingPluginDialogState extends State<MissingPluginDialog> {
  final Map<String, String> _replacements = {};
  final Set<String> _useFreezeFor = {};
  final Set<String> _expandedPlugins = {};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      backgroundColor: const Color(0xFF1a1a20),
      title: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: colorScheme.error,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Missing Plugins',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  widget.projectName,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 600,
        height: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Summary
            _buildSummary(colorScheme),
            const SizedBox(height: 16),
            const Divider(color: Colors.white24),
            const SizedBox(height: 12),

            // Plugin list
            Expanded(
              child: ListView.builder(
                itemCount: widget.report.missingPlugins.length,
                itemBuilder: (context, index) {
                  final info = widget.report.missingPlugins[index];
                  return _buildPluginCard(info, colorScheme);
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        // Cancel
        TextButton(
          onPressed: () => Navigator.of(context).pop(
            const MissingPluginDialogResponse(
              result: MissingPluginDialogResult.cancel,
            ),
          ),
          child: Text(
            'Cancel',
            style: TextStyle(color: Colors.white.withOpacity(0.7)),
          ),
        ),

        // Continue with missing
        if (widget.report.withStatePreserved.isNotEmpty)
          TextButton(
            onPressed: () => Navigator.of(context).pop(
              MissingPluginDialogResponse(
                result: MissingPluginDialogResult.continueWithMissing,
                useFreezeFor: _useFreezeFor,
              ),
            ),
            child: const Text(
              'Continue (Preserved)',
              style: TextStyle(color: Color(0xFF4a9eff)),
            ),
          ),

        // Apply replacements
        if (_replacements.isNotEmpty)
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(
              MissingPluginDialogResponse(
                result: MissingPluginDialogResult.replaced,
                replacements: Map.from(_replacements),
                useFreezeFor: _useFreezeFor,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF40ff90),
              foregroundColor: Colors.black,
            ),
            child: Text('Apply ${_replacements.length} Replacement(s)'),
          ),
      ],
    );
  }

  Widget _buildSummary(ColorScheme colorScheme) {
    final report = widget.report;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          // Missing count
          _buildStatBox(
            icon: Icons.error_outline,
            label: 'Missing',
            value: '${report.missingCount}',
            color: colorScheme.error,
          ),
          const SizedBox(width: 16),

          // With state preserved
          _buildStatBox(
            icon: Icons.save_outlined,
            label: 'State Preserved',
            value: '${report.withStatePreserved.length}',
            color: const Color(0xFF4a9eff),
          ),
          const SizedBox(width: 16),

          // With freeze audio
          _buildStatBox(
            icon: Icons.ac_unit,
            label: 'Freeze Available',
            value: '${report.withFreezeAudio.length}',
            color: const Color(0xFF40c8ff),
          ),
          const SizedBox(width: 16),

          // Installed
          _buildStatBox(
            icon: Icons.check_circle_outline,
            label: 'Installed',
            value: '${report.installedPlugins}/${report.totalPlugins}',
            color: const Color(0xFF40ff90),
          ),
        ],
      ),
    );
  }

  Widget _buildStatBox({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPluginCard(MissingPluginInfo info, ColorScheme colorScheme) {
    final plugin = info.plugin;
    final uid = plugin.uid.toString();
    final isExpanded = _expandedPlugins.contains(uid);
    final hasReplacement = _replacements.containsKey(uid);
    final useFreeze = _useFreezeFor.contains(uid);

    return Card(
      color: Colors.white.withOpacity(0.05),
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          // Header
          ListTile(
            leading: _buildPluginIcon(plugin, info, hasReplacement, useFreeze),
            title: Text(
              plugin.name,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
            subtitle: Text(
              '${plugin.vendor} • ${plugin.uid.format.name.toUpperCase()} • ${info.slotCount} slot(s)',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 12,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // State badge
                if (info.statePreserved)
                  _buildBadge('State', const Color(0xFF4a9eff)),
                if (info.hasFreezeAudio) ...[
                  const SizedBox(width: 4),
                  _buildBadge('Freeze', const Color(0xFF40c8ff)),
                ],
                const SizedBox(width: 8),
                // Expand button
                IconButton(
                  icon: Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.white54,
                  ),
                  onPressed: () {
                    setState(() {
                      if (isExpanded) {
                        _expandedPlugins.remove(uid);
                      } else {
                        _expandedPlugins.add(uid);
                      }
                    });
                  },
                ),
              ],
            ),
          ),

          // Expanded content
          if (isExpanded) _buildExpandedContent(info, colorScheme),
        ],
      ),
    );
  }

  Widget _buildPluginIcon(
    PluginReference plugin,
    MissingPluginInfo info,
    bool hasReplacement,
    bool useFreeze,
  ) {
    Color color;
    IconData icon;

    if (hasReplacement) {
      color = const Color(0xFF40ff90);
      icon = Icons.swap_horiz;
    } else if (useFreeze) {
      color = const Color(0xFF40c8ff);
      icon = Icons.ac_unit;
    } else {
      color = Colors.red;
      icon = Icons.extension_off;
    }

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }

  Widget _buildBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w500),
      ),
    );
  }

  Widget _buildExpandedContent(MissingPluginInfo info, ColorScheme colorScheme) {
    final plugin = info.plugin;
    final uid = plugin.uid.toString();

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(color: Colors.white12),

          // Usage info
          Text(
            'Used in ${info.trackCount} track(s), ${info.slotCount} slot(s)',
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),

          // Actions
          Row(
            children: [
              // Use freeze audio
              if (info.hasFreezeAudio)
                _buildActionButton(
                  icon: Icons.ac_unit,
                  label: 'Use Freeze',
                  color: const Color(0xFF40c8ff),
                  isActive: _useFreezeFor.contains(uid),
                  onPressed: () {
                    setState(() {
                      if (_useFreezeFor.contains(uid)) {
                        _useFreezeFor.remove(uid);
                      } else {
                        _useFreezeFor.add(uid);
                        _replacements.remove(uid);
                      }
                    });
                  },
                ),
              if (info.hasFreezeAudio) const SizedBox(width: 8),

              // Replace with alternative
              if (info.alternatives.isNotEmpty)
                PopupMenuButton<PluginReference>(
                  child: _buildActionButton(
                    icon: Icons.swap_horiz,
                    label: 'Replace',
                    color: const Color(0xFF40ff90),
                    isActive: _replacements.containsKey(uid),
                    onPressed: null,
                  ),
                  itemBuilder: (context) => info.alternatives.map((alt) {
                    return PopupMenuItem<PluginReference>(
                      value: alt,
                      child: Row(
                        children: [
                          Icon(
                            _getFormatIcon(alt.uid.format),
                            size: 16,
                            color: Colors.white70,
                          ),
                          const SizedBox(width: 8),
                          Text(alt.name),
                          const Spacer(),
                          Text(
                            alt.vendor,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  onSelected: (alt) {
                    setState(() {
                      _replacements[uid] = alt.uid.toString();
                      _useFreezeFor.remove(uid);
                    });
                  },
                ),

              const Spacer(),

              // Clear selection
              if (_replacements.containsKey(uid) || _useFreezeFor.contains(uid))
                TextButton.icon(
                  icon: const Icon(Icons.clear, size: 16),
                  label: const Text('Clear'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white54,
                  ),
                  onPressed: () {
                    setState(() {
                      _replacements.remove(uid);
                      _useFreezeFor.remove(uid);
                    });
                  },
                ),
            ],
          ),

          // Replacement info
          if (_replacements.containsKey(uid)) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF40ff90).withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle,
                    color: Color(0xFF40ff90),
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Will be replaced with: ${_replacements[uid]}',
                    style: const TextStyle(
                      color: Color(0xFF40ff90),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required bool isActive,
    required VoidCallback? onPressed,
  }) {
    return Material(
      color: isActive ? color.withOpacity(0.2) : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(
              color: isActive ? color : Colors.white24,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: isActive ? color : Colors.white70),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isActive ? color : Colors.white70,
                  fontSize: 12,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getFormatIcon(PluginFormat format) {
    switch (format) {
      case PluginFormat.vst3:
        return Icons.extension;
      case PluginFormat.au:
        return Icons.apple;
      case PluginFormat.clap:
        return Icons.music_note;
      case PluginFormat.aax:
        return Icons.audiotrack;
      case PluginFormat.lv2:
        return Icons.settings_input_component;
    }
  }
}
