import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../providers/slot_export_provider.dart';

/// UCP Export™ Panel — Universal Compliance Package Export Dashboard.
///
/// Real-time export control powered by rf-slot-export Rust engine via FFI.
/// Shows available formats, batch export, per-format results.
class UcpExportPanel extends StatefulWidget {
  const UcpExportPanel({super.key});

  @override
  State<UcpExportPanel> createState() => _UcpExportPanelState();
}

class _UcpExportPanelState extends State<UcpExportPanel> {
  late final SlotExportProvider _provider;
  String? _selectedFormat;

  @override
  void initState() {
    super.initState();
    _provider = GetIt.instance<SlotExportProvider>();
    _provider.addListener(_onUpdate);
    _provider.loadFormats();
  }

  @override
  void dispose() {
    _provider.removeListener(_onUpdate);
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF3A3A5C), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 8),
          _buildFormatGrid(),
          const SizedBox(height: 8),
          Expanded(child: _buildResults()),
          const SizedBox(height: 6),
          _buildActions(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(Icons.file_download, size: 14, color: Color(0xFF40C8FF)),
        const SizedBox(width: 4),
        Text(
          'UCP Export™',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.9),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFF2A2A4A),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            '${_provider.availableFormats.length} formats',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 9,
            ),
          ),
        ),
        const Spacer(),
        if (_provider.isExporting)
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              valueColor: AlwaysStoppedAnimation<Color>(
                  Colors.white.withValues(alpha: 0.5)),
            ),
          ),
      ],
    );
  }

  Widget _buildFormatGrid() {
    final formats = _provider.availableFormats;
    if (formats.isEmpty) {
      return Text(
        'Loading formats...',
        style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 10),
      );
    }

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: formats.map((fmt) {
        final name = fmt['name'] as String? ?? '?';
        final version = fmt['version'] as String? ?? '';
        final isSelected = _selectedFormat == name.toLowerCase();

        return GestureDetector(
          onTap: () => setState(() {
            _selectedFormat = isSelected ? null : name.toLowerCase();
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFF40C8FF).withValues(alpha: 0.15)
                  : const Color(0xFF1E1E36),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isSelected
                    ? const Color(0xFF40C8FF).withValues(alpha: 0.5)
                    : const Color(0xFF3A3A5C),
                width: isSelected ? 1.0 : 0.5,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    color: isSelected
                        ? const Color(0xFF40C8FF)
                        : Colors.white.withValues(alpha: 0.8),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (version.isNotEmpty)
                  Text(
                    'v$version',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.3),
                      fontSize: 8,
                    ),
                  ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildResults() {
    final results = _provider.lastExportResults;
    if (results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.file_download_outlined,
                size: 32, color: Colors.white.withValues(alpha: 0.15)),
            const SizedBox(height: 8),
            Text(
              'No export results yet.\nSelect a format and export.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.35), fontSize: 11),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, index) {
        final r = results[index];
        final format = r['format'] as String? ?? '?';
        final success = r['success'] as bool? ?? false;
        final eventCount = r['event_count'] ?? 0;
        final fileCount = r['file_count'] ?? 0;
        final error = r['error'] as String?;

        return Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E36),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: (success ? const Color(0xFF4CAF50) : const Color(0xFFFF5252))
                  .withValues(alpha: 0.3),
              width: 0.5,
            ),
          ),
          child: Row(
            children: [
              Icon(
                success ? Icons.check_circle : Icons.error,
                size: 14,
                color: success ? const Color(0xFF4CAF50) : const Color(0xFFFF5252),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      format,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (success)
                      Text(
                        '$eventCount events, $fileCount files',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5), fontSize: 9),
                      ),
                    if (error != null)
                      Text(
                        error,
                        style: const TextStyle(
                            color: Color(0xFFFF5252), fontSize: 9),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActions() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _provider.isExporting ? null : _exportAll,
            icon: const Icon(Icons.file_download, size: 14),
            label: const Text('Export All', style: TextStyle(fontSize: 10)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF40C8FF),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 6),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4)),
            ),
          ),
        ),
        if (_selectedFormat != null) ...[
          const SizedBox(width: 6),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _provider.isExporting ? null : _exportSingle,
              icon: const Icon(Icons.file_download_outlined, size: 14),
              label: Text('Export ${_selectedFormat!.toUpperCase()}',
                  style: const TextStyle(fontSize: 10)),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF40C8FF),
                side: const BorderSide(color: Color(0xFF40C8FF)),
                padding: const EdgeInsets.symmetric(vertical: 6),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4)),
              ),
            ),
          ),
        ],
      ],
    );
  }

  void _exportAll() {
    _provider.exportAll({
      'game_id': 'demo_slot',
      'events': [],
    });
  }

  void _exportSingle() {
    if (_selectedFormat == null) return;
    _provider.exportSingle({
      'game_id': 'demo_slot',
      'events': [],
    }, _selectedFormat!);
  }
}
