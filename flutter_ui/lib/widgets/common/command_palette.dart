/// Command Palette (P1.2)
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../lower_zone/lower_zone_types.dart';

class Command {
  final String label;
  final String? description;
  final IconData? icon;
  final VoidCallback onExecute;
  final List<String> keywords;

  Command({
    required this.label,
    this.description,
    this.icon,
    required this.onExecute,
    this.keywords = const [],
  });
}

class CommandPalette extends StatefulWidget {
  final List<Command> commands;

  const CommandPalette({super.key, required this.commands});

  static Future<void> show(BuildContext context, List<Command> commands) {
    return showDialog(context: context, builder: (_) => CommandPalette(commands: commands));
  }

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  final _searchController = TextEditingController();
  List<Command> _filteredCommands = [];
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _filteredCommands = widget.commands;
    _searchController.addListener(_filterCommands);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterCommands() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredCommands = query.isEmpty ? widget.commands : widget.commands.where((cmd) {
        return cmd.label.toLowerCase().contains(query) ||
            (cmd.description?.toLowerCase().contains(query) ?? false) ||
            cmd.keywords.any((k) => k.toLowerCase().contains(query));
      }).toList();
      _selectedIndex = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Center(
        child: Container(
          width: 600,
          constraints: const BoxConstraints(maxHeight: 500),
          decoration: BoxDecoration(
            color: LowerZoneColors.bgDeep,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: LowerZoneColors.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  style: const TextStyle(fontSize: 14, color: LowerZoneColors.textPrimary),
                  decoration: const InputDecoration(
                    hintText: 'Search commands...',
                    hintStyle: TextStyle(color: LowerZoneColors.textMuted),
                    prefixIcon: Icon(Icons.search, color: LowerZoneColors.dawAccent),
                  ),
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _filteredCommands.length,
                  itemBuilder: (context, index) {
                    final cmd = _filteredCommands[index];
                    final isSelected = index == _selectedIndex;
                    return GestureDetector(
                      onTap: () {
                        cmd.onExecute();
                        Navigator.pop(context);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        color: isSelected ? LowerZoneColors.dawAccent.withValues(alpha: 0.2) : null,
                        child: Row(
                          children: [
                            if (cmd.icon != null) Icon(cmd.icon, size: 16, color: LowerZoneColors.dawAccent),
                            if (cmd.icon != null) const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(cmd.label, style: const TextStyle(fontSize: 13, color: LowerZoneColors.textPrimary)),
                                  if (cmd.description != null)
                                    Text(cmd.description!, style: const TextStyle(fontSize: 11, color: LowerZoneColors.textTertiary)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
