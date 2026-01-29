/// Stage Editor Dialog
///
/// Edit trigger stages for composite events.
///
/// Features:
/// - Current stages list (removable)
/// - Search stage catalog from StageConfigurationService
/// - Add stages via clickable chips
/// - Save updates via MiddlewareProvider
///
/// Task: SL-RP-P0.2
library;

import 'package:flutter/material.dart';
import '../../models/slot_audio_events.dart';
import '../../services/stage_configuration_service.dart';
import '../../theme/fluxforge_theme.dart';

/// Stage Editor Dialog
class StageEditorDialog extends StatefulWidget {
  final SlotCompositeEvent event;

  const StageEditorDialog({
    super.key,
    required this.event,
  });

  /// Show stage editor dialog
  static Future<List<String>?> show(
    BuildContext context, {
    required SlotCompositeEvent event,
  }) {
    return showDialog<List<String>>(
      context: context,
      builder: (_) => StageEditorDialog(event: event),
    );
  }

  @override
  State<StageEditorDialog> createState() => _StageEditorDialogState();
}

class _StageEditorDialogState extends State<StageEditorDialog> {
  late List<String> _editedStages;
  String _searchQuery = '';
  List<String> _allStages = [];

  @override
  void initState() {
    super.initState();
    _editedStages = List.from(widget.event.triggerStages);
    _loadAllStages();
  }

  void _loadAllStages() {
    // Get all stage names from StageConfigurationService
    final service = StageConfigurationService.instance;
    _allStages = service.allStageNames.toList()..sort();
  }

  List<String> get _filteredStages {
    if (_searchQuery.isEmpty) return _allStages;
    final query = _searchQuery.toLowerCase();
    return _allStages.where((s) => s.toLowerCase().contains(query)).toList();
  }

  void _addStage(String stage) {
    if (!_editedStages.contains(stage)) {
      setState(() => _editedStages.add(stage));
    }
  }

  void _removeStage(int index) {
    setState(() => _editedStages.removeAt(index));
  }

  @override
  Widget build(BuildContext context) {
    final hasChanges = !_listsEqual(_editedStages, widget.event.triggerStages);

    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A22),
      title: Row(
        children: [
          Icon(Icons.edit_note, color: FluxForgeTheme.accentBlue, size: 20),
          const SizedBox(width: 8),
          const Text(
            'Edit Trigger Stages',
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
        ],
      ),
      content: SizedBox(
        width: 500,
        height: 600,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Event name (read-only reference)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF16161C),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Icon(Icons.audiotrack, size: 16, color: Colors.white54),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.event.name,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: FluxForgeTheme.accentBlue.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${_editedStages.length} stage${_editedStages.length == 1 ? '' : 's'}',
                      style: TextStyle(
                        fontSize: 9,
                        color: FluxForgeTheme.accentBlue,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Current stages section
            Text(
              'CURRENT TRIGGER STAGES',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.white54,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              height: 200,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF0D0D10),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: _editedStages.isEmpty
                  ? Center(
                      child: Text(
                        'No stages assigned\nAdd stages below',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white24,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _editedStages.length,
                      itemBuilder: (context, index) {
                        final stage = _editedStages[index];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(
                            color: FluxForgeTheme.accentGreen.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: FluxForgeTheme.accentGreen.withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.tag, size: 12, color: FluxForgeTheme.accentGreen),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  stage,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: FluxForgeTheme.accentGreen,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.close, size: 14, color: Colors.white38),
                                onPressed: () => _removeStage(index),
                                padding: EdgeInsets.zero,
                                constraints: BoxConstraints.tightFor(width: 24, height: 24),
                                tooltip: 'Remove stage',
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),

            const SizedBox(height: 16),

            // Add stages section
            Text(
              'ADD STAGES',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.white54,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 8),

            // Search field
            TextField(
              style: const TextStyle(fontSize: 12, color: Colors.white),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: const Color(0xFF16161C),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                hintText: 'Search stages... (${_allStages.length} available)',
                hintStyle: const TextStyle(color: Colors.white24, fontSize: 11),
                prefixIcon: Icon(Icons.search, size: 16, color: Colors.white38),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear, size: 16, color: Colors.white38),
                        onPressed: () => setState(() => _searchQuery = ''),
                      )
                    : null,
              ),
              onChanged: (value) {
                setState(() => _searchQuery = value);
              },
            ),

            const SizedBox(height: 12),

            // Filtered stage chips
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D0D10),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                child: _filteredStages.isEmpty
                    ? Center(
                        child: Text(
                          'No stages match "$_searchQuery"',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white24,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      )
                    : SingleChildScrollView(
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: _filteredStages.map((stage) {
                            final isAdded = _editedStages.contains(stage);
                            return ActionChip(
                              label: Text(
                                stage,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isAdded ? Colors.white38 : Colors.white70,
                                  fontFamily: 'monospace',
                                ),
                              ),
                              backgroundColor: isAdded
                                  ? Colors.white.withOpacity(0.05)
                                  : FluxForgeTheme.accentBlue.withOpacity(0.2),
                              side: BorderSide(
                                color: isAdded
                                    ? Colors.white.withOpacity(0.1)
                                    : FluxForgeTheme.accentBlue.withOpacity(0.4),
                              ),
                              onPressed: isAdded ? null : () => _addStage(stage),
                              avatar: isAdded
                                  ? Icon(Icons.check, size: 12, color: Colors.white38)
                                  : Icon(Icons.add, size: 12, color: FluxForgeTheme.accentBlue),
                            );
                          }).toList(),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          child: const Text('Cancel'),
          onPressed: () => Navigator.pop(context),
        ),
        ElevatedButton.icon(
          icon: Icon(Icons.check, size: 16),
          label: const Text('Save Changes'),
          onPressed: hasChanges
              ? () => Navigator.pop(context, _editedStages)
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: FluxForgeTheme.accentGreen,
            foregroundColor: Colors.black,
            disabledBackgroundColor: Colors.white.withOpacity(0.1),
            disabledForegroundColor: Colors.white38,
          ),
        ),
      ],
    );
  }

  bool _listsEqual(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
