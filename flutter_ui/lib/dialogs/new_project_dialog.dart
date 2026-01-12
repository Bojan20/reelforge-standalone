// New Project Dialog
//
// Creates a new project with:
// - Project name
// - Template selection
// - Initial settings

import 'package:flutter/material.dart';
import '../theme/fluxforge_theme.dart';

enum ProjectTemplate {
  empty,
  music,
  soundDesign,
  podcast,
  filmScore,
}

class NewProjectDialog extends StatefulWidget {
  const NewProjectDialog({super.key});

  static Future<NewProjectResult?> show(BuildContext context) {
    return showDialog<NewProjectResult>(
      context: context,
      builder: (context) => const NewProjectDialog(),
    );
  }

  @override
  State<NewProjectDialog> createState() => _NewProjectDialogState();
}

class NewProjectResult {
  final String name;
  final ProjectTemplate template;
  final int sampleRate;
  final double tempo;

  NewProjectResult({
    required this.name,
    required this.template,
    required this.sampleRate,
    required this.tempo,
  });
}

class _NewProjectDialogState extends State<NewProjectDialog> {
  final _nameController = TextEditingController(text: 'Untitled Project');
  final _tempoController = TextEditingController(text: '120');
  ProjectTemplate _selectedTemplate = ProjectTemplate.empty;
  int _sampleRate = 48000;
  double _tempo = 120.0;
  bool _isCreating = false;

  @override
  void dispose() {
    _nameController.dispose();
    _tempoController.dispose();
    super.dispose();
  }

  Future<void> _createProject() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please enter a project name'),
          backgroundColor: FluxForgeTheme.accentRed,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isCreating = true);

    try {
      // TODO: Call Rust API
      // await api.projectNew(_nameController.text);
      // await api.projectSetTempo(_tempo);
      // await api.projectSetSampleRate(_sampleRate);

      await Future.delayed(const Duration(milliseconds: 300)); // Simulate

      if (mounted) {
        Navigator.of(context).pop(NewProjectResult(
          name: _nameController.text,
          template: _selectedTemplate,
          sampleRate: _sampleRate,
          tempo: _tempo,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating project: $e'),
            backgroundColor: FluxForgeTheme.accentRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }

    setState(() => _isCreating = false);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: FluxForgeTheme.bgMid,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: FluxForgeTheme.borderSubtle),
      ),
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.add_box,
                  color: FluxForgeTheme.accentGreen,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  'New Project',
                  style: FluxForgeTheme.h2,
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Project name
            Text(
              'Project Name',
              style: TextStyle(
                color: FluxForgeTheme.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              autofocus: true,
              style: TextStyle(color: FluxForgeTheme.textPrimary),
              decoration: InputDecoration(
                filled: true,
                fillColor: FluxForgeTheme.bgSurface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: FluxForgeTheme.borderSubtle),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: FluxForgeTheme.borderSubtle),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: FluxForgeTheme.accentBlue),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
              onSubmitted: (_) => _createProject(),
            ),

            const SizedBox(height: 20),

            // Template selection
            Text(
              'Template',
              style: TextStyle(
                color: FluxForgeTheme.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildTemplateChip(ProjectTemplate.empty, 'Empty', Icons.crop_square),
                _buildTemplateChip(ProjectTemplate.music, 'Music', Icons.music_note),
                _buildTemplateChip(ProjectTemplate.soundDesign, 'Sound Design', Icons.surround_sound),
                _buildTemplateChip(ProjectTemplate.podcast, 'Podcast', Icons.mic),
                _buildTemplateChip(ProjectTemplate.filmScore, 'Film Score', Icons.movie),
              ],
            ),

            const SizedBox(height: 20),

            // Quick settings
            Row(
              children: [
                // Sample rate
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sample Rate',
                        style: TextStyle(
                          color: FluxForgeTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<int>(
                        value: _sampleRate,
                        dropdownColor: FluxForgeTheme.bgMid,
                        style: TextStyle(color: FluxForgeTheme.textPrimary),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: FluxForgeTheme.bgSurface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: FluxForgeTheme.borderSubtle),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        items: [44100, 48000, 88200, 96000].map((rate) {
                          return DropdownMenuItem(
                            value: rate,
                            child: Text('${rate ~/ 1000}.${(rate % 1000) ~/ 100} kHz'),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _sampleRate = value);
                          }
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                // Tempo
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tempo (BPM)',
                        style: TextStyle(
                          color: FluxForgeTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _tempoController,
                        keyboardType: TextInputType.number,
                        style: TextStyle(color: FluxForgeTheme.textPrimary),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: FluxForgeTheme.bgSurface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: FluxForgeTheme.borderSubtle),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        onChanged: (value) {
                          final parsed = double.tryParse(value);
                          if (parsed != null) {
                            _tempo = parsed.clamp(20, 300);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 32),

            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _isCreating ? null : _createProject,
                  icon: _isCreating
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: FluxForgeTheme.textPrimary,
                          ),
                        )
                      : const Icon(Icons.add, size: 18),
                  label: Text(_isCreating ? 'Creating...' : 'Create Project'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: FluxForgeTheme.accentGreen,
                    foregroundColor: FluxForgeTheme.textPrimary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTemplateChip(ProjectTemplate template, String label, IconData icon) {
    final isSelected = _selectedTemplate == template;

    return FilterChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: isSelected ? FluxForgeTheme.textPrimary : FluxForgeTheme.textSecondary,
          ),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
      selected: isSelected,
      onSelected: (_) => setState(() => _selectedTemplate = template),
      backgroundColor: FluxForgeTheme.bgSurface,
      selectedColor: FluxForgeTheme.accentBlue,
      labelStyle: TextStyle(
        color: isSelected ? FluxForgeTheme.textPrimary : FluxForgeTheme.textPrimary,
        fontSize: 12,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    );
  }
}
