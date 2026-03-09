/// UCS Naming Panel — FabFilter-style DAW Lower Zone EDIT tab
///
/// Universal Category System naming tool for game audio assets.
/// Format: CATsub_VENdor_Project_Descriptor_####
///
/// Features:
/// - Category/subcategory browser with full UCS database
/// - Vendor + project fields (saved per session)
/// - Descriptor field for free-form description
/// - Live preview of generated name
/// - Batch rename: apply to selected tracks/clips with sequential numbering
/// - Parse existing name to populate fields
library;

import 'package:flutter/material.dart';
import '../../../../services/ucs_naming_service.dart';
import '../../../fabfilter/fabfilter_theme.dart';
import '../../../fabfilter/fabfilter_widgets.dart';

class UcsNamingPanel extends StatefulWidget {
  final int? selectedTrackId;
  final String? selectedTrackName;
  final void Function(String action, Map<String, dynamic>? params)? onAction;

  const UcsNamingPanel({
    super.key,
    this.selectedTrackId,
    this.selectedTrackName,
    this.onAction,
  });

  @override
  State<UcsNamingPanel> createState() => _UcsNamingPanelState();
}

class _UcsNamingPanelState extends State<UcsNamingPanel> {
  final _service = UcsNamingService.instance;

  late TextEditingController _vendorController;
  late TextEditingController _projectController;
  late TextEditingController _descriptorController;
  late TextEditingController _numberController;
  late FocusNode _vendorFocus;
  late FocusNode _projectFocus;
  late FocusNode _descriptorFocus;
  late FocusNode _numberFocus;

  bool _showAllCategories = false;

  @override
  void initState() {
    super.initState();
    _vendorController = TextEditingController(text: _service.vendor);
    _projectController = TextEditingController(text: _service.project);
    _descriptorController = TextEditingController(text: _service.descriptor);
    _numberController = TextEditingController(text: '${_service.startNumber}');
    _vendorFocus = FocusNode();
    _projectFocus = FocusNode();
    _descriptorFocus = FocusNode();
    _numberFocus = FocusNode();
    _service.addListener(_onServiceChanged);
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceChanged);
    _vendorController.dispose();
    _projectController.dispose();
    _descriptorController.dispose();
    _numberController.dispose();
    _vendorFocus.dispose();
    _projectFocus.dispose();
    _descriptorFocus.dispose();
    _numberFocus.dispose();
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: FabFilterColors.bgDeep),
      child: Column(
        children: [
          _buildHeader(),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HEADER
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildHeader() {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: FabFilterColors.bgDeep,
        border: Border(
            bottom: BorderSide(
                color: FabFilterColors.cyan.withValues(alpha: 0.3))),
      ),
      child: Row(
        children: [
          Text('FF UCS',
              style: FabFilterText.sectionHeader.copyWith(
                color: FabFilterColors.cyan,
                fontSize: 10,
                letterSpacing: 1.2,
              )),
          const SizedBox(width: 8),
          // Preview badge
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: FabFilterColors.bgMid,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: FabFilterColors.border),
              ),
              child: Text(
                _service.generateString(),
                style: FabFilterText.paramValue(FabFilterColors.green)
                    .copyWith(fontSize: 9),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Close
          GestureDetector(
            onTap: () => widget.onAction?.call('close', null),
            child: const Icon(Icons.close,
                size: 14, color: FabFilterColors.textTertiary),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CONTENT
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildContent() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left: Category browser
          SizedBox(
            width: 180,
            child: _buildCategoryBrowser(),
          ),
          const SizedBox(width: 8),
          // Right: Fields + actions
          Expanded(child: _buildFieldsAndActions()),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CATEGORY BROWSER — scrollable list of UCS categories
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildCategoryBrowser() {
    return Container(
      decoration: FabFilterDecorations.display(),
      child: Column(
        children: [
          // Category header
          Container(
            height: 22,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: FabFilterColors.bgMid,
              border: Border(
                  bottom: BorderSide(color: FabFilterColors.border)),
            ),
            child: Row(
              children: [
                Text('CATEGORY',
                    style: FabFilterText.paramLabel
                        .copyWith(fontSize: 8, letterSpacing: 0.8)),
                const Spacer(),
                GestureDetector(
                  onTap: () =>
                      setState(() => _showAllCategories = !_showAllCategories),
                  child: Text(_showAllCategories ? 'LESS' : 'ALL',
                      style: TextStyle(
                        fontSize: 7,
                        color: FabFilterColors.cyan,
                        fontWeight: FontWeight.bold,
                      )),
                ),
              ],
            ),
          ),
          // Category list
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: UcsNamingService.categories.length,
              itemBuilder: (context, index) {
                final cat = UcsNamingService.categories[index];
                final isSelected = index == _service.selectedCategoryIndex;
                final isExpanded = isSelected;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Category row
                    GestureDetector(
                      onTap: () => _service.setSelectedCategory(index),
                      child: Container(
                        height: 22,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        color: isSelected
                            ? FabFilterColors.cyan.withValues(alpha: 0.12)
                            : null,
                        child: Row(
                          children: [
                            Text(cat.id,
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: isSelected
                                      ? FabFilterColors.cyan
                                      : FabFilterColors.textSecondary,
                                  fontFamily: 'monospace',
                                )),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(cat.name,
                                  style: TextStyle(
                                    fontSize: 8,
                                    color: isSelected
                                        ? FabFilterColors.textPrimary
                                        : FabFilterColors.textTertiary,
                                  ),
                                  overflow: TextOverflow.ellipsis),
                            ),
                            if (cat.subCategories.isNotEmpty)
                              Icon(
                                isExpanded
                                    ? Icons.expand_less
                                    : Icons.expand_more,
                                size: 10,
                                color: FabFilterColors.textTertiary,
                              ),
                          ],
                        ),
                      ),
                    ),
                    // Subcategories (when expanded)
                    if (isExpanded && cat.subCategories.isNotEmpty)
                      ...cat.subCategories.asMap().entries.map((entry) {
                        final subIndex = entry.key;
                        final sub = entry.value;
                        final isSubSelected =
                            subIndex == _service.selectedSubCategoryIndex;

                        return GestureDetector(
                          onTap: () =>
                              _service.setSelectedSubCategory(subIndex),
                          child: Container(
                            height: 20,
                            padding: const EdgeInsets.only(left: 24, right: 6),
                            color: isSubSelected
                                ? FabFilterColors.cyan.withValues(alpha: 0.08)
                                : null,
                            child: Row(
                              children: [
                                Text(sub.id,
                                    style: TextStyle(
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                      color: isSubSelected
                                          ? FabFilterColors.cyan
                                          : FabFilterColors.textTertiary,
                                      fontFamily: 'monospace',
                                    )),
                                const SizedBox(width: 4),
                                Text(sub.name,
                                    style: TextStyle(
                                      fontSize: 8,
                                      color: isSubSelected
                                          ? FabFilterColors.textPrimary
                                          : FabFilterColors.textTertiary,
                                    )),
                              ],
                            ),
                          ),
                        );
                      }),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FIELDS & ACTIONS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildFieldsAndActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Vendor + Project row
        Row(
          children: [
            Expanded(child: _buildTextField(
              label: 'VENDOR',
              controller: _vendorController,
              focusNode: _vendorFocus,
              hint: 'FF',
              onChanged: (v) => _service.setVendor(v),
              color: FabFilterColors.orange,
            )),
            const SizedBox(width: 6),
            Expanded(child: _buildTextField(
              label: 'PROJECT',
              controller: _projectController,
              focusNode: _projectFocus,
              hint: 'MyGame',
              onChanged: (v) => _service.setProject(v),
              color: FabFilterColors.orange,
            )),
          ],
        ),
        const SizedBox(height: 6),
        // Descriptor
        _buildTextField(
          label: 'DESCRIPTOR',
          controller: _descriptorController,
          focusNode: _descriptorFocus,
          hint: 'Heavy-Impact-Ground',
          onChanged: (v) => _service.setDescriptor(v),
          color: FabFilterColors.yellow,
        ),
        const SizedBox(height: 6),
        // Number row
        Row(
          children: [
            SizedBox(
              width: 80,
              child: _buildTextField(
                label: '#',
                controller: _numberController,
                focusNode: _numberFocus,
                hint: '1',
                onChanged: (v) {
                  final n = int.tryParse(v);
                  if (n != null) _service.setStartNumber(n);
                },
                color: FabFilterColors.green,
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 6),
            FabCompactToggle(
              label: '####',
              active: _service.includeNumber,
              onToggle: () =>
                  _service.setIncludeNumber(!_service.includeNumber),
              color: FabFilterColors.green,
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Preview display
        _buildPreview(),
        const Spacer(),
        // Action buttons
        _buildActions(),
      ],
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hint,
    required ValueChanged<String> onChanged,
    required Color color,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: FabFilterText.paramLabel.copyWith(
              fontSize: 7,
              letterSpacing: 0.8,
              color: color.withValues(alpha: 0.7),
            )),
        const SizedBox(height: 2),
        Container(
          height: 24,
          decoration: BoxDecoration(
            color: FabFilterColors.bgMid,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: FabFilterColors.border),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            keyboardType: keyboardType,
            style: TextStyle(
              fontSize: 10,
              color: FabFilterColors.textPrimary,
              fontFamily: 'monospace',
            ),
            decoration: InputDecoration(
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 6),
              hintText: hint,
              hintStyle: TextStyle(
                fontSize: 10,
                color: FabFilterColors.textDisabled,
                fontFamily: 'monospace',
              ),
            ),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PREVIEW
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildPreview() {
    final preview = _service.generateString();
    final parts = preview.split('_');

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: FabFilterDecorations.display(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('PREVIEW',
              style: FabFilterText.paramLabel.copyWith(
                fontSize: 7,
                letterSpacing: 0.8,
              )),
          const SizedBox(height: 4),
          // Colored parts display
          Wrap(
            spacing: 0,
            children: [
              for (int i = 0; i < parts.length; i++) ...[
                if (i > 0)
                  Text('_',
                      style: TextStyle(
                        fontSize: 12,
                        color: FabFilterColors.textTertiary,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                      )),
                Text(parts[i],
                    style: TextStyle(
                      fontSize: 12,
                      color: _partColor(i, parts.length),
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                    )),
              ],
            ],
          ),
          const SizedBox(height: 4),
          // Part labels
          Text(
            _partLabels(parts.length),
            style: TextStyle(
              fontSize: 7,
              color: FabFilterColors.textDisabled,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Color _partColor(int index, int total) {
    if (index == 0) return FabFilterColors.cyan;       // CATsub
    if (index == 1) return FabFilterColors.orange;     // Vendor
    if (index == 2) return FabFilterColors.orange;     // Project
    if (index == total - 1 && _service.includeNumber) {
      return FabFilterColors.green;                     // Number
    }
    return FabFilterColors.yellow;                      // Descriptor
  }

  String _partLabels(int count) {
    final labels = <String>[];
    labels.add('CATsub');
    if (count > 1) labels.add('Vendor');
    if (count > 2) labels.add('Project');
    if (count > 3) {
      if (_service.includeNumber && count > 4) {
        labels.add('Descriptor');
        labels.add('####');
      } else if (_service.includeNumber) {
        labels.add('####');
      } else {
        labels.add('Descriptor');
      }
    }
    return labels.join('  _  ');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTIONS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildActions() {
    final hasTrack = widget.selectedTrackId != null &&
        widget.selectedTrackId! > 0;

    return Row(
      children: [
        // Parse from current name
        if (hasTrack)
          _buildActionButton(
            label: 'PARSE',
            icon: Icons.auto_fix_high,
            color: FabFilterColors.purple,
            onTap: _parseFromTrack,
          ),
        if (hasTrack) const SizedBox(width: 6),
        // Auto-detect category
        if (hasTrack)
          _buildActionButton(
            label: 'DETECT',
            icon: Icons.search,
            color: FabFilterColors.yellow,
            onTap: _autoDetect,
          ),
        const Spacer(),
        // Apply to track
        _buildActionButton(
          label: 'RENAME TRACK',
          icon: Icons.check,
          color: FabFilterColors.green,
          filled: true,
          onTap: hasTrack ? _applyToTrack : null,
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required Color color,
    bool filled = false,
    VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    final effectiveColor = enabled ? color : FabFilterColors.textDisabled;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: filled && enabled
              ? color.withValues(alpha: 0.25)
              : FabFilterColors.bgSurface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: enabled
                ? (filled
                    ? color.withValues(alpha: 0.6)
                    : FabFilterColors.borderMedium)
                : FabFilterColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: effectiveColor),
            const SizedBox(width: 4),
            Text(label,
                style: FabFilterText.button.copyWith(
                  fontSize: 9,
                  color: effectiveColor,
                )),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTIONS — implementation
  // ═══════════════════════════════════════════════════════════════════════════

  void _parseFromTrack() {
    final name = widget.selectedTrackName;
    if (name == null || name.isEmpty) return;

    final parsed = UcsNamingService.parse(name);
    if (parsed == null) return;

    // Populate fields from parsed name
    final catIndex = UcsNamingService.findCategoryIndex(parsed.catId);
    _service.setSelectedCategory(catIndex);

    if (parsed.subId.isNotEmpty) {
      final subIndex = UcsNamingService.findSubCategoryIndex(
          catIndex, parsed.subId);
      _service.setSelectedSubCategory(subIndex);
    }

    if (parsed.vendor.isNotEmpty) {
      _service.setVendor(parsed.vendor);
      _vendorController.text = parsed.vendor;
    }
    if (parsed.project.isNotEmpty) {
      _service.setProject(parsed.project);
      _projectController.text = parsed.project;
    }
    if (parsed.descriptor.isNotEmpty) {
      _service.setDescriptor(parsed.descriptor);
      _descriptorController.text = parsed.descriptor;
    }
    if (parsed.number != null) {
      _service.setStartNumber(parsed.number!);
      _numberController.text = '${parsed.number}';
    }
  }

  void _autoDetect() {
    final name = widget.selectedTrackName;
    if (name == null || name.isEmpty) return;

    final catIndex = UcsNamingService.detectCategoryIndex(name);
    _service.setSelectedCategory(catIndex);
  }

  void _applyToTrack() {
    final trackId = widget.selectedTrackId;
    if (trackId == null || trackId <= 0) return;

    final newName = _service.generateString();
    widget.onAction?.call('ucsRename', {
      'trackId': trackId,
      'newName': newName,
    });
  }
}
