// Schema Migration Panel
//
// UI for viewing and managing project schema migrations:
// - Current schema version display
// - Migration history view
// - Manual migration trigger
// - Migration preview before applying

import 'package:flutter/material.dart';

import '../../services/schema_migration.dart';

/// Schema Migration Panel
class SchemaMigrationPanel extends StatefulWidget {
  final Map<String, dynamic>? projectData;
  final void Function(Map<String, dynamic> migratedData)? onMigrationComplete;

  const SchemaMigrationPanel({
    super.key,
    this.projectData,
    this.onMigrationComplete,
  });

  @override
  State<SchemaMigrationPanel> createState() => _SchemaMigrationPanelState();
}

class _SchemaMigrationPanelState extends State<SchemaMigrationPanel> {
  bool _isMigrating = false;
  MigrationResult? _lastResult;
  bool _showHistory = false;

  int get _currentProjectVersion {
    if (widget.projectData == null) return currentSchemaVersion;
    return widget.projectData!['schema_version'] as int? ??
        widget.projectData!['version'] as int? ??
        1;
  }

  bool get _needsMigration {
    return widget.projectData != null &&
        SchemaMigrationService.needsMigration(widget.projectData!);
  }

  List<Map<String, dynamic>> get _migrationHistory {
    if (widget.projectData == null) return [];
    final history = widget.projectData!['_migration_history'] as List?;
    if (history == null) return [];
    return history.cast<Map<String, dynamic>>();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0D0D12),
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const Divider(height: 1, color: Color(0xFF2A2A35)),
          _buildVersionInfo(),
          if (_needsMigration) ...[
            const Divider(height: 1, color: Color(0xFF2A2A35)),
            _buildMigrationPreview(),
          ],
          if (_lastResult != null) ...[
            const Divider(height: 1, color: Color(0xFF2A2A35)),
            _buildMigrationResult(),
          ],
          if (_migrationHistory.isNotEmpty) ...[
            const Divider(height: 1, color: Color(0xFF2A2A35)),
            _buildHistorySection(),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF121218),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(8),
          topRight: Radius.circular(8),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.upgrade, color: Color(0xFF4A9EFF), size: 20),
          const SizedBox(width: 10),
          const Text(
            'SCHEMA VERSION',
            style: TextStyle(
              color: Color(0xFF4A9EFF),
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
            ),
          ),
          const Spacer(),
          // Current version badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _needsMigration
                  ? const Color(0xFFFF9040).withValues(alpha: 0.2)
                  : const Color(0xFF40FF90).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _needsMigration
                    ? const Color(0xFFFF9040)
                    : const Color(0xFF40FF90),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _needsMigration ? Icons.warning_amber : Icons.check_circle,
                  size: 14,
                  color: _needsMigration
                      ? const Color(0xFFFF9040)
                      : const Color(0xFF40FF90),
                ),
                const SizedBox(width: 6),
                Text(
                  'v$_currentProjectVersion',
                  style: TextStyle(
                    color: _needsMigration
                        ? const Color(0xFFFF9040)
                        : const Color(0xFF40FF90),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVersionInfo() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _buildVersionCard(
                  'Project Version',
                  'v$_currentProjectVersion',
                  _needsMigration
                      ? const Color(0xFFFF9040)
                      : const Color(0xFF808090),
                  _needsMigration ? Icons.update : Icons.inventory_2,
                ),
              ),
              const SizedBox(width: 12),
              const Icon(
                Icons.arrow_forward,
                color: Color(0xFF606070),
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildVersionCard(
                  'Current Version',
                  'v$currentSchemaVersion',
                  const Color(0xFF40FF90),
                  Icons.new_releases,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Status message
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _needsMigration
                  ? const Color(0xFFFF9040).withValues(alpha: 0.1)
                  : const Color(0xFF40FF90).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _needsMigration
                    ? const Color(0xFFFF9040).withValues(alpha: 0.3)
                    : const Color(0xFF40FF90).withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _needsMigration ? Icons.info_outline : Icons.check,
                  color: _needsMigration
                      ? const Color(0xFFFF9040)
                      : const Color(0xFF40FF90),
                  size: 18,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _needsMigration
                        ? 'This project uses an older schema version and needs migration.'
                        : 'Project is using the latest schema version.',
                    style: TextStyle(
                      color: _needsMigration
                          ? const Color(0xFFFF9040)
                          : const Color(0xFF40FF90),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVersionCard(String label, String version, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A22),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF2A2A35)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF808090),
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            version,
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMigrationPreview() {
    final migrationPath = SchemaMigrationService.getMigrationPath(_currentProjectVersion);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'MIGRATION PREVIEW',
            style: TextStyle(
              color: Color(0xFF808090),
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 12),
          // Migration steps
          ...migrationPath.asMap().entries.map((entry) {
            final index = entry.key;
            final step = entry.value;
            final isLast = index == migrationPath.length - 1;

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: const Color(0xFF4A9EFF).withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFF4A9EFF)),
                      ),
                      child: Center(
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(
                            color: Color(0xFF4A9EFF),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    if (!isLast)
                      Container(
                        width: 2,
                        height: 24,
                        color: const Color(0xFF2A2A35),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      step,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            );
          }),
          const SizedBox(height: 8),
          // Migrate button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isMigrating ? null : _performMigration,
              icon: _isMigrating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upgrade, size: 18),
              label: Text(_isMigrating ? 'Migrating...' : 'Migrate Now'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4A9EFF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMigrationResult() {
    final result = _lastResult!;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                result.success ? Icons.check_circle : Icons.error,
                color: result.success
                    ? const Color(0xFF40FF90)
                    : const Color(0xFFFF4040),
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                result.success ? 'Migration Successful' : 'Migration Failed',
                style: TextStyle(
                  color: result.success
                      ? const Color(0xFF40FF90)
                      : const Color(0xFFFF4040),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (result.success) ...[
            Text(
              'Migrated from v${result.fromVersion} to v${result.toVersion}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            if (result.stepsApplied.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '${result.stepsApplied.length} migration step(s) applied',
                style: const TextStyle(color: Color(0xFF808090), fontSize: 11),
              ),
            ],
          ] else if (result.error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFF4040).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                result.error!,
                style: const TextStyle(color: Color(0xFFFF4040), fontSize: 11),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHistorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with toggle
        InkWell(
          onTap: () => setState(() => _showHistory = !_showHistory),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  _showHistory ? Icons.expand_less : Icons.expand_more,
                  color: const Color(0xFF808090),
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Text(
                  'MIGRATION HISTORY',
                  style: TextStyle(
                    color: Color(0xFF808090),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A35),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${_migrationHistory.length}',
                    style: const TextStyle(
                      color: Color(0xFF808090),
                      fontSize: 9,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_showHistory)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              children: _migrationHistory.map((entry) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A22),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF2A2A35)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF4A9EFF).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'v${entry['from_version']} → v${entry['to_version']}',
                              style: const TextStyle(
                                color: Color(0xFF4A9EFF),
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            _formatDate(entry['applied_at'] as String?),
                            style: const TextStyle(
                              color: Color(0xFF606070),
                              fontSize: 9,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        entry['description'] as String? ?? '',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                      ),
                      if ((entry['changes'] as List?)?.isNotEmpty == true) ...[
                        const SizedBox(height: 8),
                        ...((entry['changes'] as List?) ?? []).map((change) {
                          return Padding(
                            padding: const EdgeInsets.only(left: 8, top: 2),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.circle,
                                  size: 4,
                                  color: Color(0xFF606070),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  change.toString(),
                                  style: const TextStyle(
                                    color: Color(0xFF808090),
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  String _formatDate(String? isoDate) {
    if (isoDate == null) return '';
    try {
      final date = DateTime.parse(isoDate);
      return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return isoDate;
    }
  }

  Future<void> _performMigration() async {
    if (widget.projectData == null) return;

    setState(() => _isMigrating = true);

    // Small delay for UI feedback
    await Future.delayed(const Duration(milliseconds: 300));

    final result = SchemaMigrationService.migrate(widget.projectData!);

    setState(() {
      _isMigrating = false;
      _lastResult = result;
    });

    if (result.success && result.migratedData != null) {
      widget.onMigrationComplete?.call(result.migratedData!);
    }
  }
}

/// Compact version indicator widget
class SchemaVersionIndicator extends StatelessWidget {
  final int version;
  final bool needsMigration;
  final VoidCallback? onTap;

  const SchemaVersionIndicator({
    super.key,
    required this.version,
    this.needsMigration = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: needsMigration
              ? const Color(0xFFFF9040).withValues(alpha: 0.2)
              : const Color(0xFF2A2A35),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: needsMigration
                ? const Color(0xFFFF9040)
                : const Color(0xFF3A3A45),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (needsMigration) ...[
              const Icon(
                Icons.warning_amber,
                size: 12,
                color: Color(0xFFFF9040),
              ),
              const SizedBox(width: 4),
            ],
            Text(
              'Schema v$version',
              style: TextStyle(
                color: needsMigration
                    ? const Color(0xFFFF9040)
                    : const Color(0xFF808090),
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (needsMigration) ...[
              const SizedBox(width: 4),
              const Icon(
                Icons.arrow_forward,
                size: 10,
                color: Color(0xFFFF9040),
              ),
              const SizedBox(width: 2),
              Text(
                'v$currentSchemaVersion',
                style: const TextStyle(
                  color: Color(0xFF40FF90),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
