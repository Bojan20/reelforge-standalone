/// Project Settings Screen
///
/// Allows users to configure:
/// - Project name and metadata
/// - Tempo and time signature
/// - Sample rate and bit depth
/// - Author and description

import 'package:flutter/material.dart';
import '../../src/rust/native_ffi.dart';
import '../../theme/fluxforge_theme.dart';
import '../../widgets/project/schema_migration_panel.dart';
import '../../services/schema_migration.dart';

class ProjectSettingsScreen extends StatefulWidget {
  const ProjectSettingsScreen({super.key});

  @override
  State<ProjectSettingsScreen> createState() => _ProjectSettingsScreenState();
}

class _ProjectSettingsScreenState extends State<ProjectSettingsScreen> {
  final _nameController = TextEditingController();
  final _authorController = TextEditingController();
  final _descriptionController = TextEditingController();

  ProjectInfo? _projectInfo;
  double _tempo = 120.0;
  int _timeSigNum = 4;
  int _timeSigDenom = 4;
  int _sampleRate = 48000;
  bool _isLoading = true;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _loadProjectInfo();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _authorController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadProjectInfo() async {
    setState(() => _isLoading = true);

    try {
      // Call Rust API to get project info
      _projectInfo = NativeFFI.instance.projectGetInfo();

      if (_projectInfo != null) {
        _nameController.text = _projectInfo!.name;
        _authorController.text = _projectInfo!.author ?? '';
        _descriptionController.text = _projectInfo!.description ?? '';
        _tempo = _projectInfo!.tempo;
        _timeSigNum = _projectInfo!.timeSigNum;
        _timeSigDenom = _projectInfo!.timeSigDenom;
        _sampleRate = _projectInfo!.sampleRate;
      } else {
        // Fallback defaults if no project loaded
        _nameController.text = 'Untitled Project';
        _tempo = 120.0;
        _timeSigNum = 4;
        _timeSigDenom = 4;
        _sampleRate = 48000;
      }
    } catch (e) { /* ignored */ }

    setState(() => _isLoading = false);
  }

  void _markChanged() {
    setState(() => _hasChanges = true);
  }

  Future<void> _saveChanges() async {
    // Call Rust API to save all settings
    NativeFFI.instance.projectSetName(_nameController.text);
    NativeFFI.instance.projectSetAuthor(_authorController.text);
    NativeFFI.instance.projectSetDescription(_descriptionController.text);
    NativeFFI.instance.projectSetTempo(_tempo);
    NativeFFI.instance.projectSetTimeSignature(_timeSigNum, _timeSigDenom);
    NativeFFI.instance.projectSetSampleRate(_sampleRate);
    NativeFFI.instance.projectMarkDirty();

    setState(() => _hasChanges = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Project settings saved'),
          backgroundColor: FluxForgeTheme.accentGreen,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  String _formatDuration(double seconds) {
    final hours = (seconds / 3600).floor();
    final minutes = ((seconds % 3600) / 60).floor();
    final secs = (seconds % 60).floor();

    if (hours > 0) {
      return '${hours}h ${minutes}m ${secs}s';
    } else if (minutes > 0) {
      return '${minutes}m ${secs}s';
    } else {
      return '${secs}s';
    }
  }

  String _formatDate(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FluxForgeTheme.bgDeep,
      appBar: AppBar(
        backgroundColor: FluxForgeTheme.bgMid,
        title: const Text('Project Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (_hasChanges)
            TextButton.icon(
              onPressed: _saveChanges,
              icon: const Icon(Icons.save, size: 18),
              label: const Text('Save'),
              style: TextButton.styleFrom(
                foregroundColor: FluxForgeTheme.accentGreen,
              ),
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
                  _buildMetadataSection(),
                  const SizedBox(height: 32),
                  _buildTempoSection(),
                  const SizedBox(height: 32),
                  _buildAudioSection(),
                  const SizedBox(height: 32),
                  _buildSchemaVersionSection(),
                  const SizedBox(height: 32),
                  _buildInfoSection(),
                ],
              ),
            ),
    );
  }

  Widget _buildMetadataSection() {
    return _buildSection(
      title: 'Project Information',
      icon: Icons.folder_open,
      children: [
        _buildTextField(
          label: 'Project Name',
          controller: _nameController,
          onChanged: (_) => _markChanged(),
        ),
        const SizedBox(height: 16),
        _buildTextField(
          label: 'Author',
          controller: _authorController,
          onChanged: (_) => _markChanged(),
          hintText: 'Optional',
        ),
        const SizedBox(height: 16),
        _buildTextField(
          label: 'Description',
          controller: _descriptionController,
          onChanged: (_) => _markChanged(),
          hintText: 'Optional',
          maxLines: 3,
        ),
      ],
    );
  }

  Widget _buildTempoSection() {
    return _buildSection(
      title: 'Tempo & Time Signature',
      icon: Icons.music_note,
      children: [
        Row(
          children: [
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
                  Row(
                    children: [
                      Expanded(
                        child: Slider(
                          value: _tempo,
                          min: 20,
                          max: 300,
                          divisions: 280,
                          onChanged: (value) {
                            setState(() => _tempo = value);
                            _markChanged();
                          },
                        ),
                      ),
                      Container(
                        width: 60,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: FluxForgeTheme.bgSurface,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: FluxForgeTheme.borderSubtle),
                        ),
                        child: Text(
                          _tempo.toStringAsFixed(0),
                          textAlign: TextAlign.center,
                          style: FluxForgeTheme.mono,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Text(
              'Time Signature',
              style: TextStyle(
                color: FluxForgeTheme.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 16),
            _buildTimeSigPicker(),
          ],
        ),
      ],
    );
  }

  Widget _buildTimeSigPicker() {
    return Row(
      children: [
        DropdownButton<int>(
          value: _timeSigNum,
          dropdownColor: FluxForgeTheme.bgMid,
          style: TextStyle(color: FluxForgeTheme.textPrimary),
          items: [1, 2, 3, 4, 5, 6, 7, 8, 9, 12, 16].map((num) {
            return DropdownMenuItem(
              value: num,
              child: Text('$num'),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) {
              setState(() => _timeSigNum = value);
              _markChanged();
            }
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            '/',
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 20,
            ),
          ),
        ),
        DropdownButton<int>(
          value: _timeSigDenom,
          dropdownColor: FluxForgeTheme.bgMid,
          style: TextStyle(color: FluxForgeTheme.textPrimary),
          items: [2, 4, 8, 16].map((num) {
            return DropdownMenuItem(
              value: num,
              child: Text('$num'),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) {
              setState(() => _timeSigDenom = value);
              _markChanged();
            }
          },
        ),
      ],
    );
  }

  Widget _buildAudioSection() {
    return _buildSection(
      title: 'Audio Settings',
      icon: Icons.audiotrack,
      children: [
        Text(
          'Project Sample Rate',
          style: TextStyle(
            color: FluxForgeTheme.textSecondary,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [44100, 48000, 88200, 96000, 176400, 192000].map((rate) {
            final isSelected = rate == _sampleRate;
            return ChoiceChip(
              label: Text('${rate ~/ 1000}.${(rate % 1000) ~/ 100} kHz'),
              selected: isSelected,
              onSelected: (_) {
                setState(() => _sampleRate = rate);
                _markChanged();
              },
              backgroundColor: FluxForgeTheme.bgSurface,
              selectedColor: FluxForgeTheme.accentBlue,
              labelStyle: TextStyle(
                color: isSelected ? FluxForgeTheme.textPrimary : FluxForgeTheme.textPrimary,
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(
              Icons.warning_amber,
              size: 14,
              color: FluxForgeTheme.accentOrange,
            ),
            const SizedBox(width: 8),
            Text(
              'Changing sample rate will resample all audio',
              style: TextStyle(
                color: FluxForgeTheme.accentOrange,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSchemaVersionSection() {
    return _buildSection(
      title: 'Schema Version',
      icon: Icons.upgrade,
      children: [
        SchemaMigrationPanel(
          projectData: _getMockProjectData(),
          onMigrationComplete: (migratedData) {
            // Handle migrated data
            setState(() {
              _hasChanges = true;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Project migrated successfully'),
                backgroundColor: FluxForgeTheme.accentGreen,
              ),
            );
          },
        ),
      ],
    );
  }

  Map<String, dynamic> _getMockProjectData() {
    // Mock project data for demo - in real app, this comes from loaded project
    return {
      'schema_version': currentSchemaVersion, // Current version for demo
      'name': _nameController.text.isNotEmpty ? _nameController.text : 'Untitled',
      'tracks': [],
      'bus_hierarchy': {'buses': []},
    };
  }

  Widget _buildInfoSection() {
    if (_projectInfo == null) return const SizedBox.shrink();

    return _buildSection(
      title: 'Project Statistics',
      icon: Icons.info_outline,
      children: [
        _buildInfoRow('Duration', _formatDuration(_projectInfo!.durationSec)),
        _buildInfoRow('Tracks', '${_projectInfo!.trackCount}'),
        _buildInfoRow('Buses', '${_projectInfo!.busCount}'),
        _buildInfoRow('Created', _formatDate(_projectInfo!.createdAt)),
        _buildInfoRow('Modified', _formatDate(_projectInfo!.modifiedAt)),
        if (_projectInfo!.filePath != null)
          _buildInfoRow('Location', _projectInfo!.filePath!),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                color: FluxForgeTheme.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: FluxForgeTheme.textPrimary,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    required Function(String) onChanged,
    String? hintText,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: FluxForgeTheme.textSecondary,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          onChanged: onChanged,
          maxLines: maxLines,
          style: TextStyle(color: FluxForgeTheme.textPrimary),
          decoration: InputDecoration(
            filled: true,
            fillColor: FluxForgeTheme.bgSurface,
            hintText: hintText,
            hintStyle: TextStyle(color: FluxForgeTheme.textTertiary),
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
        ),
      ],
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Column(
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
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}
