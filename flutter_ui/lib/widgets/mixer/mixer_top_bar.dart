/// Mixer Top Bar — controls strip for mixer view
///
/// Contains: strip width toggle (N/R), section filters,
/// metering mode, search, Edit button.

import 'package:flutter/material.dart';
import '../../controllers/mixer/mixer_view_controller.dart';
import '../../models/mixer_view_models.dart';

class MixerTopBar extends StatelessWidget {
  final MixerViewController controller;
  final VoidCallback onSwitchToEdit;

  const MixerTopBar({
    super.key,
    required this.controller,
    required this.onSwitchToEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: const Color(0xFF0E0E12),
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.06)),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          // Strip width toggle
          _buildWidthToggle(),
          const SizedBox(width: 8),
          _buildSeparator(),
          const SizedBox(width: 8),
          // Section filters
          ..._buildSectionFilters(),
          const SizedBox(width: 8),
          _buildSeparator(),
          const SizedBox(width: 8),
          // View menu (Mix Window Views)
          _buildViewMenuButton(),
          const SizedBox(width: 4),
          // View Presets
          _buildPresetsDropdown(),
          const SizedBox(width: 8),
          _buildSeparator(),
          const SizedBox(width: 8),
          // Metering mode
          _buildMeteringDropdown(),
          const Spacer(),
          // Search field
          _buildSearchField(),
          const SizedBox(width: 12),
          // Edit button
          _buildEditButton(),
        ],
      ),
    );
  }

  Widget _buildWidthToggle() {
    final mode = controller.stripWidthMode;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildToggleChip(
          'N',
          mode == StripWidthMode.narrow,
          () => controller.setStripWidth(StripWidthMode.narrow),
        ),
        const SizedBox(width: 2),
        _buildToggleChip(
          'R',
          mode == StripWidthMode.regular,
          () => controller.setStripWidth(StripWidthMode.regular),
        ),
      ],
    );
  }

  List<Widget> _buildSectionFilters() {
    return MixerSection.values
        .where((s) => s != MixerSection.master)
        .map((section) {
      final isVisible = controller.isSectionVisible(section);
      return Padding(
        padding: const EdgeInsets.only(right: 4),
        child: _buildToggleChip(
          section.shortLabel,
          isVisible,
          () => controller.toggleSection(section),
          color: _sectionColor(section),
        ),
      );
    }).toList();
  }

  Widget _buildViewMenuButton() {
    return Builder(
      builder: (context) => GestureDetector(
        onTap: () => _showViewMenu(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.view_column, size: 12, color: Colors.white.withOpacity(0.5)),
              const SizedBox(width: 3),
              Text(
                'View',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showViewMenu(BuildContext context) {
    final box = context.findRenderObject() as RenderBox;
    final offset = box.localToGlobal(Offset.zero);
    showMenu<MixerStripSection>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + box.size.height,
        offset.dx + 200,
        offset.dy + box.size.height + 300,
      ),
      color: const Color(0xFF1A1A20),
      items: MixerStripSection.values.map((section) {
        final visible = controller.isStripSectionVisible(section);
        return PopupMenuItem<MixerStripSection>(
          value: section,
          height: 28,
          child: Row(
            children: [
              Icon(
                visible ? Icons.check_box : Icons.check_box_outline_blank,
                size: 14,
                color: visible ? const Color(0xFF4A9EFF) : Colors.white.withOpacity(0.3),
              ),
              const SizedBox(width: 6),
              Text(
                section.label,
                style: TextStyle(
                  color: Colors.white.withOpacity(visible ? 0.9 : 0.5),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    ).then((selected) {
      if (selected != null) {
        controller.toggleStripSection(selected);
      }
    });
  }

  Widget _buildPresetsDropdown() {
    return PopupMenuButton<MixerViewPreset>(
      onSelected: controller.applyPreset,
      offset: const Offset(0, 36),
      color: const Color(0xFF1A1A20),
      itemBuilder: (context) => MixerViewPreset.builtIn.map((preset) {
        return PopupMenuItem(
          value: preset,
          height: 28,
          child: Text(
            preset.name,
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 11,
            ),
          ),
        );
      }).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Presets',
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down,
              size: 14,
              color: Colors.white.withOpacity(0.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMeteringDropdown() {
    return PopupMenuButton<MixerMeteringMode>(
      onSelected: controller.setMeteringMode,
      offset: const Offset(0, 36),
      color: const Color(0xFF1A1A20),
      itemBuilder: (context) => MixerMeteringMode.values.map((mode) {
        return PopupMenuItem(
          value: mode,
          height: 32,
          child: Text(
            mode.label,
            style: TextStyle(
              color: controller.meteringMode == mode
                  ? const Color(0xFF4A9EFF)
                  : Colors.white.withOpacity(0.7),
              fontSize: 11,
            ),
          ),
        );
      }).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              controller.meteringMode.label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down,
              size: 14,
              color: Colors.white.withOpacity(0.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return SizedBox(
      width: 140,
      height: 24,
      child: TextField(
        onChanged: controller.setFilterQuery,
        style: TextStyle(
          color: Colors.white.withOpacity(0.8),
          fontSize: 11,
        ),
        decoration: InputDecoration(
          hintText: 'Filter...',
          hintStyle: TextStyle(
            color: Colors.white.withOpacity(0.2),
            fontSize: 11,
          ),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 6, right: 4),
            child: Icon(
              Icons.search,
              size: 14,
              color: Colors.white.withOpacity(0.3),
            ),
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 24,
            minHeight: 24,
          ),
          filled: true,
          fillColor: Colors.white.withOpacity(0.04),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(3),
            borderSide: BorderSide.none,
          ),
          isDense: true,
        ),
      ),
    );
  }

  Widget _buildEditButton() {
    return GestureDetector(
      onTap: onSwitchToEdit,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF4A9EFF).withOpacity(0.15),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: const Color(0xFF4A9EFF).withOpacity(0.3),
          ),
        ),
        child: const Text(
          'Edit',
          style: TextStyle(
            color: Color(0xFF4A9EFF),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildToggleChip(String label, bool active, VoidCallback onTap, {Color? color}) {
    final activeColor = color ?? const Color(0xFF4A9EFF);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: active
              ? activeColor.withOpacity(0.15)
              : Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(3),
          border: active
              ? Border.all(color: activeColor.withOpacity(0.3))
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active
                ? activeColor
                : Colors.white.withOpacity(0.4),
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildSeparator() {
    return Container(
      width: 1,
      height: 20,
      color: Colors.white.withOpacity(0.08),
    );
  }

  Color _sectionColor(MixerSection section) => switch (section) {
    MixerSection.tracks => const Color(0xFF4A9EFF),
    MixerSection.buses => const Color(0xFF40FF90),
    MixerSection.auxes => const Color(0xFF9370DB),
    MixerSection.vcas => const Color(0xFFFF9040),
    MixerSection.master => const Color(0xFFFFD700),
  };
}
