/// Project Settings Screen
///
/// Allows users to configure:
/// - Project name and metadata
/// - Tempo and time signature
/// - Sample rate and bit depth
/// - Author and description

import 'package:flutter/material.dart';
import '../../theme/reelforge_theme.dart';

// Mock types until flutter_rust_bridge generates them
class ProjectInfo {
  final String name;
  final String? author;
  final String? description;
  final int createdAt;
  final int modifiedAt;
  final double durationSec;
  final int sampleRate;
  final double tempo;
  final int timeSigNum;
  final int timeSigDenom;
  final int trackCount;
  final int busCount;
  final bool isModified;
  final String? filePath;

  ProjectInfo({
    required this.name,
    this.author,
    this.description,
    required this.createdAt,
    required this.modifiedAt,
    required this.durationSec,
    required this.sampleRate,
    required this.tempo,
    required this.timeSigNum,
    required this.timeSigDenom,
    required this.trackCount,
    required this.busCount,
    required this.isModified,
    this.filePath,
  });
}

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
      // TODO: Call Rust API
      // _projectInfo = await api.projectGetInfo();

      // Mock data
      _projectInfo = ProjectInfo(
        name: 'Untitled Project',
        author: null,
        description: null,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        modifiedAt: DateTime.now().millisecondsSinceEpoch,
        durationSec: 0.0,
        sampleRate: 48000,
        tempo: 120.0,
        timeSigNum: 4,
        timeSigDenom: 4,
        trackCount: 0,
        busCount: 6,
        isModified: false,
        filePath: null,
      );

      _nameController.text = _projectInfo!.name;
      _authorController.text = _projectInfo!.author ?? '';
      _descriptionController.text = _projectInfo!.description ?? '';
      _tempo = _projectInfo!.tempo;
      _timeSigNum = _projectInfo!.timeSigNum;
      _timeSigDenom = _projectInfo!.timeSigDenom;
      _sampleRate = _projectInfo!.sampleRate;
    } catch (e) {
      debugPrint('Error loading project info: $e');
    }

    setState(() => _isLoading = false);
  }

  void _markChanged() {
    setState(() => _hasChanges = true);
  }

  Future<void> _saveChanges() async {
    // TODO: Call Rust API
    // await api.projectSetName(_nameController.text);
    // await api.projectSetAuthor(_authorController.text);
    // await api.projectSetDescription(_descriptionController.text);
    // await api.projectSetTempo(_tempo);
    // await api.projectSetTimeSignature(_timeSigNum, _timeSigDenom);
    // await api.projectSetSampleRate(_sampleRate);

    setState(() => _hasChanges = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Project settings saved'),
          backgroundColor: ReelForgeTheme.accentGreen,
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
      backgroundColor: ReelForgeTheme.bgDeep,
      appBar: AppBar(
        backgroundColor: ReelForgeTheme.bgMid,
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
                foregroundColor: ReelForgeTheme.accentGreen,
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
                      color: ReelForgeTheme.textSecondary,
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
                          color: ReelForgeTheme.bgSurface,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: ReelForgeTheme.borderSubtle),
                        ),
                        child: Text(
                          _tempo.toStringAsFixed(0),
                          textAlign: TextAlign.center,
                          style: ReelForgeTheme.mono,
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
                color: ReelForgeTheme.textSecondary,
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
          dropdownColor: ReelForgeTheme.bgMid,
          style: TextStyle(color: ReelForgeTheme.textPrimary),
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
              color: ReelForgeTheme.textPrimary,
              fontSize: 20,
            ),
          ),
        ),
        DropdownButton<int>(
          value: _timeSigDenom,
          dropdownColor: ReelForgeTheme.bgMid,
          style: TextStyle(color: ReelForgeTheme.textPrimary),
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
            color: ReelForgeTheme.textSecondary,
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
              backgroundColor: ReelForgeTheme.bgSurface,
              selectedColor: ReelForgeTheme.accentBlue,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : ReelForgeTheme.textPrimary,
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
              color: ReelForgeTheme.accentOrange,
            ),
            const SizedBox(width: 8),
            Text(
              'Changing sample rate will resample all audio',
              style: TextStyle(
                color: ReelForgeTheme.accentOrange,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ],
    );
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
                color: ReelForgeTheme.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: ReelForgeTheme.textPrimary,
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
            color: ReelForgeTheme.textSecondary,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          onChanged: onChanged,
          maxLines: maxLines,
          style: TextStyle(color: ReelForgeTheme.textPrimary),
          decoration: InputDecoration(
            filled: true,
            fillColor: ReelForgeTheme.bgSurface,
            hintText: hintText,
            hintStyle: TextStyle(color: ReelForgeTheme.textTertiary),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: ReelForgeTheme.borderSubtle),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: ReelForgeTheme.borderSubtle),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: ReelForgeTheme.accentBlue),
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
        color: ReelForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ReelForgeTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: ReelForgeTheme.accentBlue, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: ReelForgeTheme.textPrimary,
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
