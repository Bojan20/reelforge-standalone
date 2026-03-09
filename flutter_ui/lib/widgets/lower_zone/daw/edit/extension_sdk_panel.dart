/// Extension SDK Panel (#34)
/// 3-column UI: extensions list + docs nav | SDK docs / code viewer | extension details
library;

import 'package:flutter/material.dart';
import '../../lower_zone_types.dart';
import '../../../../services/extension_sdk_service.dart';

class ExtensionSdkPanel extends StatefulWidget {
  final void Function(String action, Map<String, dynamic>? params)? onAction;

  const ExtensionSdkPanel({super.key, this.onAction});

  @override
  State<ExtensionSdkPanel> createState() => _ExtensionSdkPanelState();
}

class _ExtensionSdkPanelState extends State<ExtensionSdkPanel> {
  bool _showDocs = false; // false = extensions list, true = SDK docs

  @override
  void initState() {
    super.initState();
    ExtensionSdkService.instance.loadFactoryData();
  }

  @override
  void dispose() {
    ExtensionSdkService.instance.selectExtension(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ExtensionSdkService.instance,
      builder: (context, _) {
        final svc = ExtensionSdkService.instance;
        return Row(
          children: [
            // Left: Extensions + Doc Nav
            SizedBox(width: 220, child: _buildLeftColumn(svc)),
            const VerticalDivider(width: 1, color: LowerZoneColors.border),
            // Center: Content
            Expanded(child: _showDocs ? _buildDocsContent(svc) : _buildExtensionsList(svc)),
            const VerticalDivider(width: 1, color: LowerZoneColors.border),
            // Right: Details
            SizedBox(width: 260, child: _buildRightColumn(svc)),
          ],
        );
      },
    );
  }

  // ─── Left Column ───────────────────────────────────────────────────────────

  Widget _buildLeftColumn(ExtensionSdkService svc) {
    return Container(
      color: LowerZoneColors.bgDeepest,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.extension, size: 14, color: LowerZoneColors.dawAccent),
                const SizedBox(width: 6),
                const Text('EXTENSION SDK', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold,
                  color: LowerZoneColors.dawAccent, letterSpacing: 1.0)),
                const Spacer(),
                if (svc.activeCount > 0) _buildBadge('${svc.activeCount}', Colors.green),
                if (svc.errorCount > 0) ...[
                  const SizedBox(width: 4),
                  _buildBadge('${svc.errorCount}!', Colors.red),
                ],
              ],
            ),
          ),
          const Divider(height: 1, color: LowerZoneColors.border),

          // Mode toggle
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                _buildModeTab('Extensions', !_showDocs, () => setState(() => _showDocs = false)),
                const SizedBox(width: 4),
                _buildModeTab('SDK Docs', _showDocs, () => setState(() => _showDocs = true)),
              ],
            ),
          ),
          const Divider(height: 1, color: LowerZoneColors.border),

          if (_showDocs) ...[
            // Doc sections nav
            ...SdkDocSection.values.map((section) => _buildDocNavItem(svc, section)),
          ] else ...[
            // Extension items
            ...svc.extensions.map((ext) => _buildExtensionItem(svc, ext)),
            const SizedBox(height: 8),
            // Templates section
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: const Text('TEMPLATES', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold,
                color: LowerZoneColors.textMuted, letterSpacing: 1.0)),
            ),
            ...svc.templates.map((tpl) => _buildTemplateItem(tpl)),
          ],
        ],
      ),
    );
  }

  Widget _buildModeTab(String label, bool active, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 5),
          decoration: BoxDecoration(
            color: active ? LowerZoneColors.dawAccent.withValues(alpha: 0.15) : LowerZoneColors.bgSurface,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: active ? LowerZoneColors.dawAccent : LowerZoneColors.border),
          ),
          child: Text(label, textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10, fontWeight: active ? FontWeight.w600 : FontWeight.normal,
              color: active ? LowerZoneColors.dawAccent : LowerZoneColors.textSecondary)),
        ),
      ),
    );
  }

  Widget _buildExtensionItem(ExtensionSdkService svc, ExtensionInstance ext) {
    final isSelected = svc.selectedExtensionId == ext.id;
    final stateColor = switch (ext.state) {
      ExtensionState.active => Colors.green,
      ExtensionState.error => Colors.red,
      ExtensionState.loading => Colors.orange,
      ExtensionState.disabled => LowerZoneColors.textMuted,
      ExtensionState.unloaded => LowerZoneColors.textTertiary,
    };
    return GestureDetector(
      onTap: () => svc.selectExtension(ext.id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? LowerZoneColors.dawAccent.withValues(alpha: 0.1) : null,
        ),
        child: Row(
          children: [
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(shape: BoxShape.circle, color: stateColor),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(ext.manifest.name, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500,
                    color: isSelected ? LowerZoneColors.dawAccent : LowerZoneColors.textPrimary),
                    overflow: TextOverflow.ellipsis),
                  Text('${ext.manifest.language.label} • v${ext.manifest.version}',
                    style: const TextStyle(fontSize: 8, color: LowerZoneColors.textMuted)),
                ],
              ),
            ),
            Text(ext.state.label, style: TextStyle(fontSize: 8, color: stateColor)),
          ],
        ),
      ),
    );
  }

  Widget _buildTemplateItem(ExtensionTemplate tpl) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Icon(Icons.description, size: 12, color: _langColor(tpl.language)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tpl.name, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500,
                  color: LowerZoneColors.textPrimary), overflow: TextOverflow.ellipsis),
                Text(tpl.language.label, style: const TextStyle(fontSize: 8, color: LowerZoneColors.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocNavItem(ExtensionSdkService svc, SdkDocSection section) {
    final isActive = svc.activeDocSection == section;
    return GestureDetector(
      onTap: () => svc.setActiveDocSection(section),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? LowerZoneColors.dawAccent.withValues(alpha: 0.1) : null,
          border: Border(left: BorderSide(
            color: isActive ? LowerZoneColors.dawAccent : Colors.transparent, width: 3)),
        ),
        child: Text(section.label, style: TextStyle(fontSize: 10,
          fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
          color: isActive ? LowerZoneColors.dawAccent : LowerZoneColors.textSecondary)),
      ),
    );
  }

  // ─── Center: Content ───────────────────────────────────────────────────────

  Widget _buildExtensionsList(ExtensionSdkService svc) {
    final exts = svc.extensions;
    if (exts.isEmpty) {
      return const Center(child: Text('No extensions loaded', style: TextStyle(fontSize: 11, color: LowerZoneColors.textMuted)));
    }

    return Column(
      children: [
        // Header bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: LowerZoneColors.bgMid,
          child: Row(
            children: [
              const Text('LOADED EXTENSIONS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold,
                color: LowerZoneColors.textSecondary, letterSpacing: 1.0)),
              const Spacer(),
              Text('${exts.length} extensions • ${svc.activeCount} active',
                style: const TextStyle(fontSize: 9, color: LowerZoneColors.textMuted)),
            ],
          ),
        ),
        const Divider(height: 1, color: LowerZoneColors.border),
        Expanded(
          child: ListView.builder(
            itemCount: exts.length,
            itemBuilder: (context, index) => _buildExtensionRow(svc, exts[index]),
          ),
        ),
      ],
    );
  }

  Widget _buildExtensionRow(ExtensionSdkService svc, ExtensionInstance ext) {
    final isSelected = svc.selectedExtensionId == ext.id;
    final stateColor = switch (ext.state) {
      ExtensionState.active => Colors.green,
      ExtensionState.error => Colors.red,
      ExtensionState.loading => Colors.orange,
      ExtensionState.disabled => LowerZoneColors.textMuted,
      ExtensionState.unloaded => LowerZoneColors.textTertiary,
    };

    return GestureDetector(
      onTap: () => svc.selectExtension(ext.id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? LowerZoneColors.dawAccent.withValues(alpha: 0.08) : null,
          border: Border(bottom: BorderSide(color: LowerZoneColors.border.withValues(alpha: 0.3))),
        ),
        child: Row(
          children: [
            // Language icon
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: _langColor(ext.manifest.language).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(ext.manifest.language.fileExtension,
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: _langColor(ext.manifest.language))),
              ),
            ),
            const SizedBox(width: 10),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(ext.manifest.name, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                          color: isSelected ? LowerZoneColors.dawAccent : LowerZoneColors.textPrimary),
                          overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 6),
                      Text('v${ext.manifest.version}', style: const TextStyle(fontSize: 8, color: LowerZoneColors.textMuted)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(ext.manifest.description, style: const TextStyle(fontSize: 9, color: LowerZoneColors.textSecondary),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  // Capabilities
                  Wrap(spacing: 4,
                    children: ext.manifest.capabilities.map((c) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: LowerZoneColors.bgSurface,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(c.label, style: const TextStyle(fontSize: 7, color: LowerZoneColors.textMuted)),
                    )).toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Resource usage
            if (ext.state == ExtensionState.active) Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('CPU ${ext.cpuPercent.toStringAsFixed(1)}%',
                  style: const TextStyle(fontSize: 8, color: LowerZoneColors.textMuted)),
                Text(ext.memoryLabel,
                  style: const TextStyle(fontSize: 8, color: LowerZoneColors.textMuted)),
              ],
            ),
            const SizedBox(width: 8),
            // State toggle
            if (ext.state == ExtensionState.loading)
              const SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.orange))
            else
              GestureDetector(
                onTap: () => svc.toggleExtension(ext.id),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: stateColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: stateColor.withValues(alpha: 0.3)),
                  ),
                  child: Text(ext.state == ExtensionState.active ? 'Disable' : 'Enable',
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.w500, color: stateColor)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDocsContent(ExtensionSdkService svc) {
    final section = svc.activeDocSection;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: LowerZoneColors.bgMid,
          child: Row(
            children: [
              const Icon(Icons.menu_book, size: 12, color: LowerZoneColors.dawAccent),
              const SizedBox(width: 6),
              Text(section.label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold,
                color: LowerZoneColors.textSecondary, letterSpacing: 1.0)),
            ],
          ),
        ),
        const Divider(height: 1, color: LowerZoneColors.border),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SelectableText(section.content,
              style: const TextStyle(fontSize: 11, color: LowerZoneColors.textPrimary,
                fontFamily: 'monospace', height: 1.5)),
          ),
        ),
      ],
    );
  }

  // ─── Right Column ──────────────────────────────────────────────────────────

  Widget _buildRightColumn(ExtensionSdkService svc) {
    final ext = svc.selectedExtension;
    if (ext == null) {
      return Container(
        color: LowerZoneColors.bgDeepest,
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.extension, size: 32, color: LowerZoneColors.textMuted),
              SizedBox(height: 8),
              Text('Select an extension', style: TextStyle(fontSize: 11, color: LowerZoneColors.textMuted)),
            ],
          ),
        ),
      );
    }

    final stateColor = switch (ext.state) {
      ExtensionState.active => Colors.green,
      ExtensionState.error => Colors.red,
      ExtensionState.loading => Colors.orange,
      ExtensionState.disabled => LowerZoneColors.textMuted,
      ExtensionState.unloaded => LowerZoneColors.textTertiary,
    };

    return Container(
      color: LowerZoneColors.bgDeepest,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: _langColor(ext.manifest.language).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.extension, size: 18, color: _langColor(ext.manifest.language)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(ext.manifest.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold,
                        color: LowerZoneColors.textPrimary)),
                      Text('by ${ext.manifest.author}', style: const TextStyle(fontSize: 10, color: LowerZoneColors.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Status badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: stateColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: stateColor.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: stateColor)),
                  const SizedBox(width: 6),
                  Text(ext.state.label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: stateColor)),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Action buttons
            Row(
              children: [
                if (ext.state == ExtensionState.active)
                  _buildActionBtn('Disable', Icons.pause, Colors.orange, () => svc.deactivateExtension(ext.id))
                else if (ext.state == ExtensionState.error)
                  _buildActionBtn('Reload', Icons.refresh, Colors.orange, () => svc.reloadExtension(ext.id))
                else
                  _buildActionBtn('Activate', Icons.play_arrow, Colors.green, () => svc.activateExtension(ext.id)),
                const SizedBox(width: 6),
                _buildActionBtn('Remove', Icons.delete_outline, Colors.red, () => svc.removeExtension(ext.id)),
              ],
            ),

            if (ext.errorMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline, size: 12, color: Colors.red),
                    const SizedBox(width: 6),
                    Expanded(child: Text(ext.errorMessage!, style: const TextStyle(fontSize: 9, color: Colors.red))),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),

            // Description
            Text(ext.manifest.description, style: const TextStyle(fontSize: 10, color: LowerZoneColors.textSecondary, height: 1.4)),
            const SizedBox(height: 16),

            // Info grid
            _buildInfoRow('Version', ext.manifest.version),
            _buildInfoRow('Language', ext.manifest.language.label),
            _buildInfoRow('Entry Point', ext.manifest.entryPoint),
            _buildInfoRow('API Version', 'v${ext.manifest.minApiVersion}'),
            if (ext.manifest.license != null) _buildInfoRow('License', ext.manifest.license!),
            if (ext.state == ExtensionState.active) ...[
              _buildInfoRow('CPU Usage', '${ext.cpuPercent.toStringAsFixed(2)}%'),
              _buildInfoRow('Memory', ext.memoryLabel),
            ],
            const SizedBox(height: 12),

            // Capabilities
            const Text('CAPABILITIES', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold,
              color: LowerZoneColors.textMuted, letterSpacing: 1.0)),
            const SizedBox(height: 6),
            Wrap(spacing: 4, runSpacing: 4,
              children: ext.manifest.capabilities.map((c) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: LowerZoneColors.bgSurface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(c.label, style: const TextStyle(fontSize: 8, color: LowerZoneColors.textSecondary)),
              )).toList(),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────

  Widget _buildActionBtn(String label, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 80,
            child: Text(label, style: const TextStyle(fontSize: 9, color: LowerZoneColors.textMuted))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w500,
            color: LowerZoneColors.textPrimary))),
        ],
      ),
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: color)),
    );
  }

  Color _langColor(ExtensionLanguage lang) => switch (lang) {
    ExtensionLanguage.rust => const Color(0xFFCE422B),
    ExtensionLanguage.lua => const Color(0xFF5B7FDE),
    ExtensionLanguage.wasm => const Color(0xFF654FF0),
    ExtensionLanguage.jsfx => const Color(0xFF4EC9B0),
  };
}
