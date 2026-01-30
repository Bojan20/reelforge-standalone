/// Feature Template Browser
///
/// UI for browsing, previewing, and instantiating feature templates.
///
/// Part of P1-12: Feature Template Library
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/feature_template.dart';
import '../../services/feature_template_service.dart';

class FeatureTemplateBrowser extends StatefulWidget {
  const FeatureTemplateBrowser({super.key});

  @override
  State<FeatureTemplateBrowser> createState() => _FeatureTemplateBrowserState();
}

class _FeatureTemplateBrowserState extends State<FeatureTemplateBrowser> {
  FeatureType? _selectedType;
  FeatureTemplate? _selectedTemplate;
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: FeatureTemplateService.instance,
      child: Consumer<FeatureTemplateService>(
        builder: (context, service, _) {
          final templates = _filterTemplates(service.templates);

          return Column(
            children: [
              _buildHeader(),
              const Divider(height: 1),
              Expanded(
                child: Row(
                  children: [
                    SizedBox(
                      width: 280,
                      child: _buildTemplateList(templates),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: _selectedTemplate != null
                          ? _buildTemplateDetail(_selectedTemplate!)
                          : _buildEmptyState(),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ==========================================================================
  // HEADER
  // ==========================================================================

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(12),
      color: const Color(0xFF1a1a20),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.folder_special, size: 20, color: Color(0xFF4A9EFF)),
              const SizedBox(width: 8),
              const Text(
                'Feature Templates',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              _buildTypeFilter(),
            ],
          ),
          const SizedBox(height: 8),
          _buildSearchBar(),
        ],
      ),
    );
  }

  Widget _buildTypeFilter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF242430),
        borderRadius: BorderRadius.circular(4),
      ),
      child: DropdownButton<FeatureType?>(
        value: _selectedType,
        hint: const Text('All Types', style: TextStyle(fontSize: 12)),
        underline: const SizedBox(),
        style: const TextStyle(fontSize: 12, color: Colors.white),
        dropdownColor: const Color(0xFF242430),
        items: [
          const DropdownMenuItem<FeatureType?>(
            value: null,
            child: Text('All Types'),
          ),
          ...FeatureType.values.map((type) => DropdownMenuItem(
            value: type,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(type.icon, size: 14, color: type.color),
                const SizedBox(width: 6),
                Text(type.displayName),
              ],
            ),
          )),
        ],
        onChanged: (value) {
          setState(() {
            _selectedType = value;
          });
        },
      ),
    );
  }

  Widget _buildSearchBar() {
    return TextField(
      decoration: InputDecoration(
        hintText: 'Search templates...',
        prefixIcon: const Icon(Icons.search, size: 18),
        filled: true,
        fillColor: const Color(0xFF242430),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      ),
      style: const TextStyle(fontSize: 13),
      onChanged: (value) {
        setState(() {
          _searchQuery = value;
        });
      },
    );
  }

  // ==========================================================================
  // TEMPLATE LIST
  // ==========================================================================

  Widget _buildTemplateList(List<FeatureTemplate> templates) {
    if (templates.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox, size: 48, color: Colors.grey.shade600),
            const SizedBox(height: 8),
            Text(
              'No templates found',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: templates.length,
      itemBuilder: (context, index) {
        final template = templates[index];
        final isSelected = _selectedTemplate?.id == template.id;

        return _TemplateListItem(
          template: template,
          isSelected: isSelected,
          onTap: () {
            setState(() {
              _selectedTemplate = template;
            });
          },
        );
      },
    );
  }

  // ==========================================================================
  // TEMPLATE DETAIL
  // ==========================================================================

  Widget _buildTemplateDetail(FeatureTemplate template) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDetailHeader(template),
          const SizedBox(height: 16),
          if (template.description != null) ...[
            Text(
              template.description!,
              style: TextStyle(color: Colors.grey.shade400),
            ),
            const SizedBox(height: 16),
          ],
          _buildPhasesList(template),
          const SizedBox(height: 16),
          if (template.parameters.isNotEmpty) ...[
            _buildParametersList(template),
            const SizedBox(height: 16),
          ],
          _buildActions(template),
        ],
      ),
    );
  }

  Widget _buildDetailHeader(FeatureTemplate template) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: template.type.color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(template.type.icon, color: template.type.color, size: 32),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                template.name,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                template.type.displayName,
                style: TextStyle(color: template.type.color, fontSize: 13),
              ),
            ],
          ),
        ),
        if (template.isBuiltIn)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF40FF90).withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              'Built-in',
              style: TextStyle(color: Color(0xFF40FF90), fontSize: 11),
            ),
          ),
      ],
    );
  }

  Widget _buildPhasesList(FeatureTemplate template) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Phases',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ...template.phases.map((phase) => _PhaseCard(phase: phase)),
      ],
    );
  }

  Widget _buildParametersList(FeatureTemplate template) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Parameters',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ...template.parameters.map((param) => _ParameterCard(parameter: param)),
      ],
    );
  }

  Widget _buildActions(FeatureTemplate template) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => _instantiateTemplate(template),
            icon: const Icon(Icons.add),
            label: const Text('Use Template'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4A9EFF),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: () => _exportTemplate(template),
          icon: const Icon(Icons.file_download, size: 18),
          label: const Text('Export'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_special, size: 64, color: Colors.grey.shade700),
          const SizedBox(height: 16),
          Text(
            'Select a template',
            style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          Text(
            'Choose a template from the list to see details',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // HELPERS
  // ==========================================================================

  List<FeatureTemplate> _filterTemplates(List<FeatureTemplate> templates) {
    var filtered = templates;

    // Filter by type
    if (_selectedType != null) {
      filtered = filtered.where((t) => t.type == _selectedType).toList();
    }

    // Filter by search query
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((t) {
        return t.name.toLowerCase().contains(query) ||
               t.type.displayName.toLowerCase().contains(query) ||
               (t.description?.toLowerCase().contains(query) ?? false);
      }).toList();
    }

    return filtered;
  }

  void _instantiateTemplate(FeatureTemplate template) {
    showDialog(
      context: context,
      builder: (context) => _InstantiateTemplateDialog(template: template),
    );
  }

  void _exportTemplate(FeatureTemplate template) {
    // TODO: Export to JSON file
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Export feature coming soon')),
    );
  }
}

// =============================================================================
// TEMPLATE LIST ITEM
// =============================================================================

class _TemplateListItem extends StatelessWidget {
  final FeatureTemplate template;
  final bool isSelected;
  final VoidCallback onTap;

  const _TemplateListItem({
    required this.template,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? const Color(0xFF242430) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: isSelected ? template.type.color : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(template.type.icon, color: template.type.color, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      template.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${template.phases.length} phases • ${template.allAudioSlots.length} slots',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
              if (template.isBuiltIn)
                Icon(Icons.verified, size: 16, color: Colors.grey.shade600),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// PHASE CARD
// =============================================================================

class _PhaseCard extends StatelessWidget {
  final FeaturePhase phase;

  const _PhaseCard({required this.phase});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: const Color(0xFF1a1a20),
      child: ExpansionTile(
        title: Text(
          '${phase.order + 1}. ${phase.name}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: phase.description != null
            ? Text(phase.description!, style: TextStyle(fontSize: 12, color: Colors.grey.shade500))
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (phase.canSkip)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF9040).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'Optional',
                  style: TextStyle(color: Color(0xFFFF9040), fontSize: 10),
                ),
              ),
            const SizedBox(width: 8),
            Text(
              '${phase.audioSlots.length} slots',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.expand_more),
          ],
        ),
        children: phase.audioSlots.map((slot) => _AudioSlotItem(slot: slot)).toList(),
      ),
    );
  }
}

// =============================================================================
// AUDIO SLOT ITEM
// =============================================================================

class _AudioSlotItem extends StatelessWidget {
  final AudioSlotDef slot;

  const _AudioSlotItem({required this.slot});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: Icon(
        slot.looping ? Icons.loop : Icons.audiotrack,
        size: 18,
        color: slot.required ? const Color(0xFFFF4040) : Colors.grey.shade600,
      ),
      title: Text(
        slot.label,
        style: const TextStyle(fontSize: 13),
      ),
      subtitle: slot.description != null
          ? Text(slot.description!, style: TextStyle(fontSize: 11, color: Colors.grey.shade600))
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (slot.defaultBus != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF4A9EFF).withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                slot.defaultBus!,
                style: const TextStyle(color: Color(0xFF4A9EFF), fontSize: 10),
              ),
            ),
          if (slot.required) ...[
            const SizedBox(width: 6),
            const Icon(Icons.star, size: 14, color: Color(0xFFFF4040)),
          ],
        ],
      ),
    );
  }
}

// =============================================================================
// PARAMETER CARD
// =============================================================================

class _ParameterCard extends StatelessWidget {
  final ParameterDef parameter;

  const _ParameterCard({required this.parameter});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: const Color(0xFF1a1a20),
      child: ListTile(
        leading: Icon(
          _getIconForType(parameter.type),
          size: 20,
          color: Colors.grey.shade600,
        ),
        title: Text(
          parameter.label,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (parameter.description != null)
              Text(parameter.description!, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            const SizedBox(height: 2),
            Text(
              'Default: ${parameter.defaultValue}',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
          ],
        ),
        trailing: parameter.required
            ? const Icon(Icons.star, size: 14, color: Color(0xFFFF4040))
            : null,
      ),
    );
  }

  IconData _getIconForType(ParameterType type) {
    return switch (type) {
      ParameterType.integer => Icons.tag,
      ParameterType.float => Icons.straighten,
      ParameterType.boolean => Icons.toggle_on,
      ParameterType.string => Icons.text_fields,
      ParameterType.list => Icons.list,
    };
  }
}

// =============================================================================
// INSTANTIATE TEMPLATE DIALOG
// =============================================================================

class _InstantiateTemplateDialog extends StatefulWidget {
  final FeatureTemplate template;

  const _InstantiateTemplateDialog({required this.template});

  @override
  State<_InstantiateTemplateDialog> createState() => _InstantiateTemplateDialogState();
}

class _InstantiateTemplateDialogState extends State<_InstantiateTemplateDialog> {
  late final TextEditingController _nameController;
  final Map<String, dynamic> _paramValues = {};

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: 'New ${widget.template.name}');

    // Initialize parameter values with defaults
    for (final param in widget.template.parameters) {
      _paramValues[param.id] = param.defaultValue;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Use Template: ${widget.template.name}'),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(),
                ),
              ),
              if (widget.template.parameters.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  'Parameters',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ...widget.template.parameters.map((param) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildParameterInput(param),
                  );
                }),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _create,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4A9EFF),
          ),
          child: const Text('Create'),
        ),
      ],
    );
  }

  Widget _buildParameterInput(ParameterDef param) {
    switch (param.type) {
      case ParameterType.boolean:
        return CheckboxListTile(
          title: Text(param.label),
          value: _paramValues[param.id] as bool,
          onChanged: (value) {
            setState(() {
              _paramValues[param.id] = value ?? false;
            });
          },
        );

      case ParameterType.integer:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(param.label),
            const SizedBox(height: 4),
            TextField(
              decoration: const InputDecoration(border: OutlineInputBorder()),
              keyboardType: TextInputType.number,
              controller: TextEditingController(
                text: _paramValues[param.id].toString(),
              ),
              onChanged: (value) {
                _paramValues[param.id] = int.tryParse(value) ?? param.defaultValue;
              },
            ),
          ],
        );

      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(param.label),
            const SizedBox(height: 4),
            TextField(
              decoration: const InputDecoration(border: OutlineInputBorder()),
              controller: TextEditingController(
                text: _paramValues[param.id].toString(),
              ),
              onChanged: (value) {
                _paramValues[param.id] = value;
              },
            ),
          ],
        );
    }
  }

  void _create() {
    final service = FeatureTemplateService.instance;
    final instance = service.createInstance(
      templateId: widget.template.id,
      name: _nameController.text,
      parameterValues: _paramValues,
    );

    Navigator.pop(context);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Created: ${instance.name}'),
        action: SnackBarAction(
          label: 'Assign Audio',
          onPressed: () {
            // TODO: Open audio assignment UI
          },
        ),
      ),
    );
  }
}
