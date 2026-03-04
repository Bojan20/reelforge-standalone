/// P-PPL-8: Publish Pipeline UI Panel
///
/// One-click publish button with live pipeline progress.
/// Shows per-step status, error details, rollback option,
/// and publish history log.
library;

import 'package:flutter/material.dart';
import '../../services/publish_pipeline_service.dart';
import '../../theme/fluxforge_theme.dart';

class PublishPipelinePanel extends StatefulWidget {
  const PublishPipelinePanel({super.key});

  @override
  State<PublishPipelinePanel> createState() => _PublishPipelinePanelState();
}

class _PublishPipelinePanelState extends State<PublishPipelinePanel> {
  final _service = PublishPipelineService.instance;

  // Config state
  String _outputPath = '';
  final Set<PublishTarget> _selectedTargets = {PublishTarget.wasm};
  VersionBump _versionBump = VersionBump.patch;
  bool _pushToRemote = false;

  late final TextEditingController _outputPathCtrl;

  @override
  void initState() {
    super.initState();
    _outputPathCtrl = TextEditingController(text: _outputPath);
    _service.addListener(_onServiceUpdate);
  }

  @override
  void dispose() {
    _outputPathCtrl.dispose();
    _service.removeListener(_onServiceUpdate);
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.bgElevated),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!_service.isRunning) ...[
                    _buildTargetSelector(),
                    const SizedBox(height: 12),
                    _buildVersionConfig(),
                    const SizedBox(height: 12),
                    _buildOutputConfig(),
                    const SizedBox(height: 12),
                    _buildOptions(),
                    const SizedBox(height: 16),
                    _buildPublishButton(),
                  ],
                  if (_service.stepResults.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _buildPipelineProgress(),
                  ],
                  if (_service.publishHistory.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _buildHistory(),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── HEADER ─────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
      ),
      child: Row(
        children: [
          Icon(
            _service.isRunning ? Icons.rocket_launch : Icons.publish,
            size: 16,
            color: _service.isRunning ? Colors.amber : Colors.cyan.withValues(alpha: 0.8),
          ),
          const SizedBox(width: 8),
          Text(
            'Publish Pipeline',
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          if (_service.isRunning)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                value: _service.progress,
                color: Colors.cyan,
              ),
            )
          else
            Text(
              'v${_service.currentVersion}',
              style: TextStyle(
                color: FluxForgeTheme.textTertiary,
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
        ],
      ),
    );
  }

  // ─── TARGET SELECTOR ────────────────────────────────────────────────────────

  Widget _buildTargetSelector() {
    return _section('Targets', [
      Wrap(
        spacing: 6,
        runSpacing: 4,
        children: PublishTarget.values.map((target) {
          final selected = _selectedTargets.contains(target);
          return InkWell(
            onTap: () => setState(() {
              if (selected) {
                _selectedTargets.remove(target);
              } else {
                _selectedTargets.add(target);
              }
            }),
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: selected ? Colors.cyan.withValues(alpha: 0.15) : FluxForgeTheme.bgSurface,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: selected ? Colors.cyan.withValues(alpha: 0.5) : FluxForgeTheme.bgElevated,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (selected)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(Icons.check, size: 12, color: Colors.cyan),
                    ),
                  Text(
                    target.label,
                    style: TextStyle(
                      color: selected ? Colors.cyan : FluxForgeTheme.textTertiary,
                      fontSize: 10,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    ]);
  }

  // ─── VERSION CONFIG ─────────────────────────────────────────────────────────

  Widget _buildVersionConfig() {
    return _section('Version', [
      Row(
        children: VersionBump.values.map((bump) {
          final selected = bump == _versionBump;
          final label = switch (bump) {
            VersionBump.patch => 'Patch',
            VersionBump.minor => 'Minor',
            VersionBump.major => 'Major',
          };
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: InkWell(
                onTap: () => setState(() => _versionBump = bump),
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.cyan.withValues(alpha: 0.2)
                        : FluxForgeTheme.bgSurface.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: selected ? Colors.cyan : FluxForgeTheme.bgElevated,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: selected ? Colors.cyan : FluxForgeTheme.textTertiary,
                        fontSize: 10,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    ]);
  }

  // ─── OUTPUT CONFIG ──────────────────────────────────────────────────────────

  Widget _buildOutputConfig() {
    return _section('Output Path', [
      TextField(
        controller: _outputPathCtrl,
        onChanged: (v) => _outputPath = v,
        style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 11),
        decoration: InputDecoration(
          hintText: '/path/to/publish/output...',
          hintStyle: TextStyle(color: FluxForgeTheme.textTertiary.withValues(alpha: 0.5)),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          isDense: true,
        ),
      ),
    ]);
  }

  // ─── OPTIONS ────────────────────────────────────────────────────────────────

  Widget _buildOptions() {
    return _section('Options', [
      Row(
        children: [
          _toggleChip('Push to Remote', _pushToRemote, (v) => setState(() => _pushToRemote = v)),
        ],
      ),
    ]);
  }

  // ─── PUBLISH BUTTON ─────────────────────────────────────────────────────────

  Widget _buildPublishButton() {
    final canPublish = _selectedTargets.isNotEmpty && _outputPath.isNotEmpty;

    return ElevatedButton.icon(
      onPressed: canPublish
          ? () async {
              final config = PublishConfig(
                outputPath: _outputPath,
                targets: _selectedTargets.toList(),
                versionBump: _versionBump,
                pushToRemote: _pushToRemote,
              );
              await _service.publish(config);
            }
          : null,
      icon: const Icon(Icons.rocket_launch, size: 16),
      label: const Text('Publish', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      style: ElevatedButton.styleFrom(
        backgroundColor: canPublish ? Colors.cyan : FluxForgeTheme.bgElevated,
        foregroundColor: canPublish ? Colors.white : FluxForgeTheme.textTertiary,
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
    );
  }

  // ─── PIPELINE PROGRESS ──────────────────────────────────────────────────────

  Widget _buildPipelineProgress() {
    return _section('Pipeline Progress', [
      ...(_service.stepResults).map((step) {
        final icon = switch (step.status) {
          PipelineStepStatus.success => Icons.check_circle,
          PipelineStepStatus.failed => Icons.error,
          PipelineStepStatus.running => Icons.refresh,
          PipelineStepStatus.skipped => Icons.skip_next,
          PipelineStepStatus.pending => Icons.circle_outlined,
        };
        final color = switch (step.status) {
          PipelineStepStatus.success => Colors.green,
          PipelineStepStatus.failed => Colors.red,
          PipelineStepStatus.running => Colors.amber,
          PipelineStepStatus.skipped => FluxForgeTheme.textTertiary,
          PipelineStepStatus.pending => FluxForgeTheme.textTertiary,
        };

        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: color.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 8),
                Text(
                  step.stepName,
                  style: TextStyle(
                    color: FluxForgeTheme.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                if (step.duration != null)
                  Text(
                    '${step.duration!.inMilliseconds}ms',
                    style: TextStyle(
                      color: FluxForgeTheme.textTertiary,
                      fontSize: 9,
                      fontFamily: 'monospace',
                    ),
                  ),
                if (step.message != null) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      step.message!,
                      style: TextStyle(
                        color: color.withValues(alpha: 0.8),
                        fontSize: 10,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      }),
      // Error detail
      if (_service.lastError != null)
        Container(
          margin: const EdgeInsets.only(top: 4),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
          ),
          child: Text(
            _service.lastError!,
            style: TextStyle(color: Colors.red, fontSize: 10),
          ),
        ),
    ]);
  }

  // ─── HISTORY ────────────────────────────────────────────────────────────────

  Widget _buildHistory() {
    return _section('Publish History', [
      ...(_service.publishHistory.reversed.take(5)).map((entry) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgSurface.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle_outline, size: 12, color: Colors.green.withValues(alpha: 0.6)),
                const SizedBox(width: 6),
                Text(
                  'v${entry['version']}',
                  style: TextStyle(
                    color: FluxForgeTheme.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    (entry['targets'] as List).join(', '),
                    style: TextStyle(
                      color: FluxForgeTheme.textTertiary,
                      fontSize: 10,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${entry['duration']}s',
                  style: TextStyle(
                    color: FluxForgeTheme.textTertiary,
                    fontSize: 9,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    ]);
  }

  // ─── HELPERS ────────────────────────────────────────────────────────────────

  Widget _section(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: TextStyle(
            color: FluxForgeTheme.textTertiary,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        ...children,
      ],
    );
  }

  Widget _toggleChip(String label, bool value, void Function(bool) onChanged) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: value ? Colors.cyan.withValues(alpha: 0.15) : FluxForgeTheme.bgSurface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: value ? Colors.cyan.withValues(alpha: 0.5) : FluxForgeTheme.bgElevated,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: value ? Colors.cyan : FluxForgeTheme.textTertiary,
            fontSize: 10,
            fontWeight: value ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
