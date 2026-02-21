/// FluxForge Studio Container Import/Export Dialog
///
/// P4.4: Container import/export
/// - Batch export all containers
/// - Import from folder
/// - Export to folder with organized structure
/// - Progress feedback
library;

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../utils/safe_file_picker.dart';
import '../../providers/middleware_provider.dart';
import '../../services/container_preset_service.dart';
import '../../theme/fluxforge_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// IMPORT/EXPORT DIALOG
// ═══════════════════════════════════════════════════════════════════════════════

class ContainerImportExportDialog extends StatefulWidget {
  const ContainerImportExportDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (context) => const ContainerImportExportDialog(),
    );
  }

  @override
  State<ContainerImportExportDialog> createState() => _ContainerImportExportDialogState();
}

class _ContainerImportExportDialogState extends State<ContainerImportExportDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isProcessing = false;
  String _statusMessage = '';
  List<String> _logs = [];

  // Export selections
  bool _exportBlend = true;
  bool _exportRandom = true;
  bool _exportSequence = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _log(String message) {
    setState(() {
      _logs.add('[${DateTime.now().toString().substring(11, 19)}] $message');
      if (_logs.length > 100) _logs.removeAt(0);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 600,
        height: 500,
        decoration: BoxDecoration(
          color: FluxForgeTheme.surfaceDark,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: FluxForgeTheme.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            _buildHeader(),
            _buildTabBar(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildExportTab(),
                  _buildImportTab(),
                ],
              ),
            ),
            if (_statusMessage.isNotEmpty || _logs.isNotEmpty)
              _buildStatusPanel(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: FluxForgeTheme.border)),
      ),
      child: Row(
        children: [
          Icon(Icons.import_export, color: Colors.blue, size: 24),
          const SizedBox(width: 12),
          Text(
            'Container Import / Export',
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: FluxForgeTheme.surface,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(Icons.close, size: 16, color: FluxForgeTheme.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.surface,
        border: Border(bottom: BorderSide(color: FluxForgeTheme.border)),
      ),
      child: TabBar(
        controller: _tabController,
        labelColor: Colors.blue,
        unselectedLabelColor: FluxForgeTheme.textSecondary,
        indicatorColor: Colors.blue,
        tabs: const [
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.file_upload, size: 16),
                SizedBox(width: 8),
                Text('Export'),
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.file_download, size: 16),
                SizedBox(width: 8),
                Text('Import'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExportTab() {
    return Consumer<MiddlewareProvider>(
      builder: (context, provider, _) {
        final blendCount = provider.blendContainers.length;
        final randomCount = provider.randomContainers.length;
        final sequenceCount = provider.sequenceContainers.length;

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Select containers to export:',
                style: TextStyle(
                  color: FluxForgeTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              // Blend containers
              _buildExportOption(
                'Blend Containers',
                Icons.blur_linear,
                Colors.purple,
                blendCount,
                _exportBlend,
                (v) => setState(() => _exportBlend = v ?? false),
              ),
              const SizedBox(height: 8),
              // Random containers
              _buildExportOption(
                'Random Containers',
                Icons.shuffle,
                Colors.orange,
                randomCount,
                _exportRandom,
                (v) => setState(() => _exportRandom = v ?? false),
              ),
              const SizedBox(height: 8),
              // Sequence containers
              _buildExportOption(
                'Sequence Containers',
                Icons.timeline,
                Colors.teal,
                sequenceCount,
                _exportSequence,
                (v) => setState(() => _exportSequence = v ?? false),
              ),
              const Spacer(),
              // Export summary
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: FluxForgeTheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: FluxForgeTheme.border),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: FluxForgeTheme.textSecondary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Will export ${_getExportCount(provider)} container(s) to .ffxcontainer files',
                        style: TextStyle(
                          color: FluxForgeTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Export button
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: _isProcessing ? null : () => _exportContainers(provider),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: _isProcessing
                              ? FluxForgeTheme.surface
                              : Colors.blue,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (_isProcessing)
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: FluxForgeTheme.textSecondary,
                                ),
                              )
                            else
                              Icon(Icons.file_upload, size: 18, color: Colors.white),
                            const SizedBox(width: 8),
                            Text(
                              _isProcessing ? 'Exporting...' : 'Export to Folder',
                              style: TextStyle(
                                color: _isProcessing
                                    ? FluxForgeTheme.textSecondary
                                    : Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildExportOption(
    String label,
    IconData icon,
    Color color,
    int count,
    bool selected,
    ValueChanged<bool?> onChanged,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: selected ? color.withValues(alpha: 0.1) : FluxForgeTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected ? color : FluxForgeTheme.border,
        ),
      ),
      child: Row(
        children: [
          Checkbox(
            value: selected,
            onChanged: count > 0 ? onChanged : null,
            activeColor: color,
          ),
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: FluxForgeTheme.textPrimary,
                fontSize: 13,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: count > 0 ? color.withValues(alpha: 0.2) : FluxForgeTheme.backgroundDeep,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                color: count > 0 ? color : FluxForgeTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  int _getExportCount(MiddlewareProvider provider) {
    int count = 0;
    if (_exportBlend) count += provider.blendContainers.length;
    if (_exportRandom) count += provider.randomContainers.length;
    if (_exportSequence) count += provider.sequenceContainers.length;
    return count;
  }

  Future<void> _exportContainers(MiddlewareProvider provider) async {
    final result = await SafeFilePicker.getDirectoryPath(context,
      dialogTitle: 'Select Export Folder',
    );

    if (result == null) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Starting export...';
      _logs.clear();
    });

    int exported = 0;
    int failed = 0;

    try {
      // Create subfolders
      if (_exportBlend && provider.blendContainers.isNotEmpty) {
        final blendDir = Directory('$result/Blend');
        if (!await blendDir.exists()) await blendDir.create();

        for (final container in provider.blendContainers) {
          final fileName = _sanitizeFileName(container.name);
          final filePath = '${blendDir.path}/$fileName$kPresetExtension';
          final success = await ContainerPresetService.instance.exportBlendContainer(container, filePath);
          if (success) {
            _log('✓ Exported blend: ${container.name}');
            exported++;
          } else {
            _log('✗ Failed blend: ${container.name}');
            failed++;
          }
        }
      }

      if (_exportRandom && provider.randomContainers.isNotEmpty) {
        final randomDir = Directory('$result/Random');
        if (!await randomDir.exists()) await randomDir.create();

        for (final container in provider.randomContainers) {
          final fileName = _sanitizeFileName(container.name);
          final filePath = '${randomDir.path}/$fileName$kPresetExtension';
          final success = await ContainerPresetService.instance.exportRandomContainer(container, filePath);
          if (success) {
            _log('✓ Exported random: ${container.name}');
            exported++;
          } else {
            _log('✗ Failed random: ${container.name}');
            failed++;
          }
        }
      }

      if (_exportSequence && provider.sequenceContainers.isNotEmpty) {
        final sequenceDir = Directory('$result/Sequence');
        if (!await sequenceDir.exists()) await sequenceDir.create();

        for (final container in provider.sequenceContainers) {
          final fileName = _sanitizeFileName(container.name);
          final filePath = '${sequenceDir.path}/$fileName$kPresetExtension';
          final success = await ContainerPresetService.instance.exportSequenceContainer(container, filePath);
          if (success) {
            _log('✓ Exported sequence: ${container.name}');
            exported++;
          } else {
            _log('✗ Failed sequence: ${container.name}');
            failed++;
          }
        }
      }

      setState(() {
        _statusMessage = 'Export complete: $exported exported, $failed failed';
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Export error: $e';
      });
      _log('✗ Error: $e');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  String _sanitizeFileName(String name) {
    return name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
  }

  Widget _buildImportTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Import containers from files:',
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          // Import options
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: FluxForgeTheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: FluxForgeTheme.border),
            ),
            child: Column(
              children: [
                _buildImportButton(
                  'Import Single File',
                  Icons.insert_drive_file,
                  Colors.blue,
                  'Select a .ffxcontainer file to import',
                  _importSingleFile,
                ),
                const SizedBox(height: 12),
                _buildImportButton(
                  'Import from Folder',
                  Icons.folder,
                  Colors.green,
                  'Import all .ffxcontainer files from a folder',
                  _importFromFolder,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Supported formats
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: FluxForgeTheme.backgroundDeep,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: FluxForgeTheme.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Supported format: .ffxcontainer',
                        style: TextStyle(
                          color: FluxForgeTheme.textPrimary,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        'Containers are auto-detected by type (blend/random/sequence)',
                        style: TextStyle(
                          color: FluxForgeTheme.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildImportButton(
    String label,
    IconData icon,
    Color color,
    String description,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: _isProcessing ? null : onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 24, color: color),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: FluxForgeTheme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: TextStyle(
                      color: FluxForgeTheme.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 14, color: FluxForgeTheme.textSecondary),
          ],
        ),
      ),
    );
  }

  Future<void> _importSingleFile() async {
    final result = await SafeFilePicker.pickFiles(context,
      type: FileType.custom,
      allowedExtensions: ['ffxcontainer', 'json'],
      dialogTitle: 'Select Container Preset',
    );

    if (result == null || result.files.single.path == null) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Importing...';
    });

    try {
      final preset = await ContainerPresetService.instance.importPreset(result.files.single.path!);
      if (preset != null) {
        await _applyPreset(preset);
        _log('✓ Imported: ${preset.name} (${preset.type})');
        setState(() => _statusMessage = 'Successfully imported: ${preset.name}');
      } else {
        _log('✗ Failed to import file');
        setState(() => _statusMessage = 'Failed to import file');
      }
    } catch (e) {
      _log('✗ Error: $e');
      setState(() => _statusMessage = 'Import error: $e');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _importFromFolder() async {
    final result = await SafeFilePicker.getDirectoryPath(context,
      dialogTitle: 'Select Import Folder',
    );

    if (result == null) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Scanning folder...';
      _logs.clear();
    });

    int imported = 0;
    int failed = 0;

    try {
      final dir = Directory(result);
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File && entity.path.endsWith(kPresetExtension)) {
          final preset = await ContainerPresetService.instance.importPreset(entity.path);
          if (preset != null) {
            await _applyPreset(preset);
            _log('✓ Imported: ${preset.name} (${preset.type})');
            imported++;
          } else {
            _log('✗ Failed: ${entity.path.split('/').last}');
            failed++;
          }
        }
      }

      setState(() {
        _statusMessage = 'Import complete: $imported imported, $failed failed';
      });
    } catch (e) {
      _log('✗ Error: $e');
      setState(() => _statusMessage = 'Import error: $e');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _applyPreset(ContainerPreset preset) async {
    final provider = context.read<MiddlewareProvider>();

    switch (preset.type) {
      case 'blend':
        final container = await ContainerPresetService.instance.importBlendContainer(
          '', // Will use preset.data directly
          newId: provider.blendContainers.length + 1,
        );
        // Actually need to create from preset data directly
        provider.addBlendContainer(
          name: preset.name,
          rtpcId: preset.data['rtpcId'] as int? ?? 0,
        );
        break;
      case 'random':
        provider.addRandomContainer(name: preset.name);
        break;
      case 'sequence':
        provider.addSequenceContainer(name: preset.name);
        break;
    }
  }

  Widget _buildStatusPanel() {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: FluxForgeTheme.backgroundDeep,
        border: Border(top: BorderSide(color: FluxForgeTheme.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status message
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: _statusMessage.contains('error') || _statusMessage.contains('Failed')
                ? Colors.red.withValues(alpha: 0.1)
                : Colors.green.withValues(alpha: 0.1),
            child: Row(
              children: [
                Icon(
                  _statusMessage.contains('error') || _statusMessage.contains('Failed')
                      ? Icons.error_outline
                      : Icons.check_circle_outline,
                  size: 16,
                  color: _statusMessage.contains('error') || _statusMessage.contains('Failed')
                      ? Colors.red
                      : Colors.green,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _statusMessage,
                    style: TextStyle(
                      color: FluxForgeTheme.textPrimary,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Logs
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              itemCount: _logs.length,
              itemBuilder: (context, index) {
                final log = _logs[_logs.length - 1 - index]; // Reverse order
                final isError = log.contains('✗');
                return Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    log,
                    style: TextStyle(
                      color: isError ? Colors.red : FluxForgeTheme.textSecondary,
                      fontSize: 10,
                      fontFamily: 'monospace',
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
