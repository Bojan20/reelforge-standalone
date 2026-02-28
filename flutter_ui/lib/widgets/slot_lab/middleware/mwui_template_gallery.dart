import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../../providers/slot_lab/feature_composer_provider.dart';
import '../../../theme/fluxforge_theme.dart';

/// MWUI-5: Template Gallery UI — 7 Template Categories
///
/// Grid view of pre-built middleware templates:
/// Standard 5-Reel, Megaways, Hold & Win, Cluster Pays,
/// Jackpot Wheel, Buy Feature, Blank.
class MwuiTemplateGallery extends StatefulWidget {
  const MwuiTemplateGallery({super.key});

  @override
  State<MwuiTemplateGallery> createState() => _MwuiTemplateGalleryState();
}

class _MwuiTemplateGalleryState extends State<MwuiTemplateGallery> {
  FeatureComposerProvider? _composer;
  _TemplateCategory _selectedCategory = _TemplateCategory.all;
  int _selectedTemplateIndex = -1;

  @override
  void initState() {
    super.initState();
    try {
      _composer = GetIt.instance<FeatureComposerProvider>();
      _composer?.addListener(_onUpdate);
    } catch (_) {}
  }

  @override
  void dispose() {
    _composer?.removeListener(_onUpdate);
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        _buildCategoryBar(),
        Expanded(child: _buildGrid()),
        if (_selectedTemplateIndex >= 0) _buildDetailBar(),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        border: Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle)),
      ),
      child: Row(
        children: [
          const Icon(Icons.dashboard, size: 14, color: Color(0xFF7E57C2)),
          const SizedBox(width: 6),
          Text('Template Gallery', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 11, fontWeight: FontWeight.w600)),
          const Spacer(),
          Text('${_templates.length} templates', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 9)),
        ],
      ),
    );
  }

  Widget _buildCategoryBar() {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        border: Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: _TemplateCategory.values.map((cat) {
          final isSelected = _selectedCategory == cat;
          return GestureDetector(
            onTap: () => setState(() {
              _selectedCategory = cat;
              _selectedTemplateIndex = -1;
            }),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF7E57C2).withOpacity(0.15) : Colors.transparent,
                borderRadius: BorderRadius.circular(3),
              ),
              alignment: Alignment.center,
              child: Text(
                cat.displayName,
                style: TextStyle(
                  color: isSelected ? const Color(0xFF7E57C2) : Colors.white.withOpacity(0.4),
                  fontSize: 9,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildGrid() {
    final filtered = _selectedCategory == _TemplateCategory.all
        ? _templates
        : _templates.where((t) => t.category == _selectedCategory).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Text('No templates in this category', style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 11)),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(10),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1.3,
      ),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final tpl = filtered[index];
        final globalIndex = _templates.indexOf(tpl);
        final isSelected = _selectedTemplateIndex == globalIndex;

        return GestureDetector(
          onTap: () => setState(() => _selectedTemplateIndex = globalIndex),
          child: Container(
            decoration: BoxDecoration(
              color: isSelected
                  ? tpl.color.withOpacity(0.12)
                  : Colors.white.withOpacity(0.02),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isSelected ? tpl.color.withOpacity(0.5) : Colors.white.withOpacity(0.08),
                width: isSelected ? 1.5 : 0.5,
              ),
            ),
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(tpl.icon, size: 16, color: tpl.color),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: tpl.color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: Text(
                        tpl.category.shortName,
                        style: TextStyle(color: tpl.color, fontSize: 7, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  tpl.name,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  tpl.description,
                  style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 8),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const Spacer(),
                Row(
                  children: [
                    Text('${tpl.nodeCount} nodes', style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 7)),
                    const Spacer(),
                    Text('${tpl.stageCount} stages', style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 7)),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailBar() {
    final tpl = _templates[_selectedTemplateIndex];
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        border: Border(top: BorderSide(color: FluxForgeTheme.borderSubtle)),
      ),
      child: Row(
        children: [
          Icon(tpl.icon, size: 14, color: tpl.color),
          const SizedBox(width: 6),
          Text(tpl.name, style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(width: 12),
          Text('${tpl.nodeCount} nodes, ${tpl.stageCount} stages',
            style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 9)),
          const Spacer(),
          GestureDetector(
            onTap: () {
              // Template apply
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Applied template: ${tpl.name}', style: const TextStyle(fontSize: 11)),
                  duration: const Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: const Color(0xFF2A2A4A),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: tpl.color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: tpl.color.withOpacity(0.3), width: 0.5),
              ),
              child: Text('Apply Template', style: TextStyle(color: tpl.color, fontSize: 10, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  static const _templates = [
    _Template('Standard 5-Reel', 'Classic 5-reel, 3-row with paylines', _TemplateCategory.standard,
      Icons.grid_view, Color(0xFF42A5F5), 18, 12),
    _Template('Standard 5-Reel Extended', '5-reel with free spins + bonus', _TemplateCategory.standard,
      Icons.grid_view, Color(0xFF42A5F5), 24, 18),
    _Template('Megaways Basic', 'Up to 117,649 ways with cascading', _TemplateCategory.megaways,
      Icons.view_module, Color(0xFF66BB6A), 22, 16),
    _Template('Megaways Premium', 'Megaways with reaction chain + multiplier', _TemplateCategory.megaways,
      Icons.view_module, Color(0xFF66BB6A), 30, 22),
    _Template('Hold & Win Classic', 'Respins with sticky symbols', _TemplateCategory.holdAndWin,
      Icons.push_pin, Color(0xFFFFB74D), 20, 14),
    _Template('Hold & Win Progressive', 'Multi-level jackpots with hold', _TemplateCategory.holdAndWin,
      Icons.push_pin, Color(0xFFFFB74D), 26, 20),
    _Template('Cluster Pays', 'Cluster matching with chain reactions', _TemplateCategory.cluster,
      Icons.bubble_chart, Color(0xFF7E57C2), 20, 15),
    _Template('Jackpot Wheel', 'Wheel bonus with tiered jackpots', _TemplateCategory.jackpot,
      Icons.casino, Color(0xFFEF5350), 24, 18),
    _Template('Jackpot Progressive', 'Progressive jackpot multi-tier', _TemplateCategory.jackpot,
      Icons.casino, Color(0xFFEF5350), 28, 22),
    _Template('Buy Feature', 'Direct feature purchase mechanic', _TemplateCategory.buyFeature,
      Icons.shopping_cart, Color(0xFF26C6DA), 16, 10),
    _Template('Blank Project', 'Empty project with default bus hierarchy', _TemplateCategory.blank,
      Icons.note_add, Color(0xFF78909C), 0, 0),
  ];
}

enum _TemplateCategory {
  all, standard, megaways, holdAndWin, cluster, jackpot, buyFeature, blank;

  String get displayName {
    switch (this) {
      case all: return 'All';
      case standard: return 'Standard';
      case megaways: return 'Megaways';
      case holdAndWin: return 'Hold & Win';
      case cluster: return 'Cluster';
      case jackpot: return 'Jackpot';
      case buyFeature: return 'Buy Feature';
      case blank: return 'Blank';
    }
  }

  String get shortName {
    switch (this) {
      case all: return 'ALL';
      case standard: return 'STD';
      case megaways: return 'MW';
      case holdAndWin: return 'H&W';
      case cluster: return 'CLU';
      case jackpot: return 'JP';
      case buyFeature: return 'BUY';
      case blank: return 'BLK';
    }
  }
}

class _Template {
  final String name;
  final String description;
  final _TemplateCategory category;
  final IconData icon;
  final Color color;
  final int nodeCount;
  final int stageCount;
  const _Template(this.name, this.description, this.category, this.icon, this.color, this.nodeCount, this.stageCount);
}
