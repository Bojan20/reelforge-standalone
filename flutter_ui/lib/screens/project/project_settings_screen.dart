/// Project Settings Screen
///
/// Allows users to configure:
/// - Project name and metadata
/// - Tempo and time signature
/// - Sample rate and bit depth
/// - Author and description

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  SrcQuality _srcQuality = SrcQuality.sinc64;
  bool _isLoading = true;
  bool _hasChanges = false;
  Timer? _diagRefreshTimer;

  @override
  void initState() {
    super.initState();
    _loadProjectInfo();
    // Auto-refresh adaptive quality monitor every 500ms
    _diagRefreshTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) { if (mounted) setState(() {}); },
    );
  }

  @override
  void dispose() {
    _diagRefreshTimer?.cancel();
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
        _srcQuality = NativeFFI.instance.getSrcQuality();
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
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          Navigator.of(context).pop();
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
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
                      _buildSrcQualitySection(),
                      const SizedBox(height: 32),
                      _buildAdaptiveQualitySection(),
                      const SizedBox(height: 32),
                      _buildSchemaVersionSection(),
                      const SizedBox(height: 32),
                      _buildInfoSection(),
                    ],
                  ),
                ),
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

  Widget _buildSrcQualitySection() {
    return _buildSection(
      title: 'SRC Quality',
      icon: Icons.tune,
      children: [
        Text(
          'Playback Sample Rate Conversion',
          style: TextStyle(
            color: FluxForgeTheme.textSecondary,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgSurface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: FluxForgeTheme.borderSubtle),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<SrcQuality>(
              value: _srcQuality,
              isExpanded: true,
              dropdownColor: FluxForgeTheme.bgSurface,
              style: const TextStyle(
                fontSize: 13,
                color: FluxForgeTheme.textPrimary,
              ),
              items: SrcQuality.values.map((q) {
                return DropdownMenuItem(
                  value: q,
                  child: Text(q.label),
                );
              }).toList(),
              onChanged: (q) {
                if (q != null) {
                  setState(() => _srcQuality = q);
                  NativeFFI.instance.setSrcQuality(q);
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          switch (_srcQuality) {
            SrcQuality.point => 'Lowest latency, draft quality. Good for editing.',
            SrcQuality.linear => 'Low CPU. Acceptable for previewing.',
            SrcQuality.sinc16 => 'Light Sinc interpolation. Good for playback.',
            SrcQuality.sinc64 => 'Standard quality. Recommended for most work.',
            SrcQuality.sinc192 => 'High quality Blackman-Harris Sinc. For critical listening.',
            SrcQuality.sinc384 => 'Ultra quality. Maximum fidelity, higher CPU.',
            SrcQuality.r8brain => 'Offline r8brain SRC. Best quality, not for real-time.',
          },
          style: TextStyle(
            color: FluxForgeTheme.textTertiary,
            fontSize: 11,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }

  Widget _buildAdaptiveQualitySection() {
    final stats = NativeFFI.instance.getAdaptiveQualityStats();
    return _buildSection(
      title: 'Adaptive Quality Monitor',
      icon: Icons.speed,
      children: [
        _buildDiagRow('Active Voices', '${stats.activeVoices}'),
        _buildDiagRow('Degraded Voices', '${stats.degradedVoices}',
          highlight: stats.hasDegradedVoices),
        _buildDiagRow('Voice CPU Load', '${stats.cpuLoadPct}%',
          highlight: stats.isOverBudget),
        _buildDiagRow('Global SRC', stats.srcModeLabel),
        const SizedBox(height: 8),
        // CPU load bar
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: (stats.cpuLoadPct / 100.0).clamp(0.0, 2.0) / 2.0,
            minHeight: 6,
            backgroundColor: FluxForgeTheme.bgSurface,
            valueColor: AlwaysStoppedAnimation(
              stats.cpuLoadPct > 100
                  ? FluxForgeTheme.accentRed
                  : stats.cpuLoadPct > 75
                      ? FluxForgeTheme.accentOrange
                      : FluxForgeTheme.accentGreen,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          stats.isOverBudget
              ? 'Over budget — background voices degraded to Sinc 16'
              : 'Within CPU budget — all voices at full quality',
          style: TextStyle(
            color: stats.isOverBudget
                ? FluxForgeTheme.accentOrange
                : FluxForgeTheme.textTertiary,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _buildDiagRow(String label, String value, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: FluxForgeTheme.textTertiary,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'JetBrains Mono',
              color: highlight
                  ? FluxForgeTheme.accentOrange
                  : FluxForgeTheme.textSecondary,
              fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
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
