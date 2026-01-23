// ═══════════════════════════════════════════════════════════════════════════════
// JSON PATH EXPLORER — Visual tool for discovering JSON paths in samples
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Known path types for ingest configuration
enum JsonPathType {
  events,
  eventName,
  timestamp,
  winAmount,
  betAmount,
  reelData,
  feature,
  symbol,
  reels,
  win,
  featureActive,
  balance,
}

/// Visual explorer for discovering JSON paths in sample data
class JsonPathExplorer extends StatefulWidget {
  final Map<String, dynamic>? sampleData;
  final Function(JsonPathType type, String path)? onPathSelected;

  const JsonPathExplorer({
    super.key,
    this.sampleData,
    this.onPathSelected,
  });

  @override
  State<JsonPathExplorer> createState() => _JsonPathExplorerState();
}

class _JsonPathExplorerState extends State<JsonPathExplorer> {
  final _controller = TextEditingController();
  Map<String, dynamic>? _parsedData;
  String? _error;
  final Set<String> _expandedPaths = {};
  String? _selectedPath;

  @override
  void initState() {
    super.initState();
    if (widget.sampleData != null) {
      _parsedData = widget.sampleData;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _parseJson() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() {
        _error = 'Enter JSON data';
        _parsedData = null;
      });
      return;
    }

    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) {
        setState(() {
          _parsedData = decoded;
          _error = null;
        });
      } else if (decoded is List && decoded.isNotEmpty && decoded.first is Map) {
        setState(() {
          _parsedData = decoded.first as Map<String, dynamic>;
          _error = null;
        });
      } else {
        setState(() {
          _error = 'Expected JSON object or array of objects';
          _parsedData = null;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Invalid JSON: ${e.toString().split(':').last}';
        _parsedData = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF3a3a44)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          if (widget.sampleData == null) ...[
            _buildJsonInput(),
            const Divider(color: Color(0xFF3a3a44), height: 1),
          ],
          Expanded(
            child: _parsedData != null ? _buildTree() : _buildEmpty(),
          ),
          if (_selectedPath != null) _buildPathActions(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF242430),
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      child: Row(
        children: [
          const Icon(Icons.account_tree, color: Color(0xFF4a9eff), size: 18),
          const SizedBox(width: 8),
          Text(
            'JSON Path Explorer',
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          if (_parsedData != null)
            TextButton.icon(
              onPressed: () => setState(() {
                _expandedPaths.clear();
                _selectedPath = null;
              }),
              icon: const Icon(Icons.unfold_less, size: 14),
              label: const Text('Collapse All'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white.withOpacity(0.6),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildJsonInput() {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFF121216),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _error != null
                    ? const Color(0xFFff4040)
                    : const Color(0xFF3a3a44),
              ),
            ),
            child: TextField(
              controller: _controller,
              maxLines: null,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
              decoration: InputDecoration(
                hintText: '{"events": [...], "balance": 1000}',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(8),
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _error!,
                style: const TextStyle(color: Color(0xFFff4040), fontSize: 10),
              ),
            ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: _parseJson,
            icon: const Icon(Icons.search, size: 16),
            label: const Text('Explore'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4a9eff),
              padding: const EdgeInsets.symmetric(vertical: 8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.code, size: 48, color: Colors.white.withOpacity(0.2)),
          const SizedBox(height: 12),
          Text(
            'No JSON data loaded',
            style: TextStyle(color: Colors.white.withOpacity(0.5)),
          ),
          const SizedBox(height: 4),
          Text(
            'Paste JSON to explore its structure',
            style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildTree() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: _buildNode('', _parsedData!, 0),
    );
  }

  Widget _buildNode(String path, dynamic value, int depth) {
    final isRoot = path.isEmpty;
    final key = isRoot ? 'root' : path.split('.').last;

    if (value is Map<String, dynamic>) {
      return _buildMapNode(path, key, value, depth);
    } else if (value is List) {
      return _buildArrayNode(path, key, value, depth);
    } else {
      return _buildValueNode(path, key, value, depth);
    }
  }

  Widget _buildMapNode(String path, String key, Map<String, dynamic> map, int depth) {
    final isExpanded = _expandedPaths.contains(path) || path.isEmpty;
    final isSelected = _selectedPath == path;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildNodeHeader(
          path: path,
          key: key,
          icon: Icons.data_object,
          color: const Color(0xFF4a9eff),
          suffix: '{${map.length}}',
          depth: depth,
          isExpanded: isExpanded,
          isSelected: isSelected,
          onTap: path.isEmpty ? null : () => _toggleExpanded(path),
          onSelect: path.isEmpty ? null : () => _selectPath(path),
        ),
        if (isExpanded)
          Padding(
            padding: EdgeInsets.only(left: depth > 0 ? 16 : 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: map.entries.map((e) {
                final childPath = path.isEmpty ? e.key : '$path.${e.key}';
                return _buildNode(childPath, e.value, depth + 1);
              }).toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildArrayNode(String path, String key, List array, int depth) {
    final isExpanded = _expandedPaths.contains(path);
    final isSelected = _selectedPath == path;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildNodeHeader(
          path: path,
          key: key,
          icon: Icons.data_array,
          color: const Color(0xFFff9040),
          suffix: '[${array.length}]',
          depth: depth,
          isExpanded: isExpanded,
          isSelected: isSelected,
          onTap: () => _toggleExpanded(path),
          onSelect: () => _selectPath(path),
        ),
        if (isExpanded && array.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: array.asMap().entries.take(5).map((e) {
                final childPath = '$path[${e.key}]';
                return _buildNode(childPath, e.value, depth + 1);
              }).toList()
                ..addAll(array.length > 5
                    ? [
                        Padding(
                          padding: const EdgeInsets.only(left: 16, top: 4),
                          child: Text(
                            '... and ${array.length - 5} more items',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.4),
                              fontSize: 10,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ]
                    : []),
            ),
          ),
      ],
    );
  }

  Widget _buildValueNode(String path, String key, dynamic value, int depth) {
    final isSelected = _selectedPath == path;
    final typeColor = _getTypeColor(value);

    return _buildNodeHeader(
      path: path,
      key: key,
      icon: _getTypeIcon(value),
      color: typeColor,
      suffix: _formatValue(value),
      depth: depth,
      isSelected: isSelected,
      onSelect: () => _selectPath(path),
    );
  }

  Widget _buildNodeHeader({
    required String path,
    required String key,
    required IconData icon,
    required Color color,
    required String suffix,
    required int depth,
    bool isExpanded = false,
    bool isSelected = false,
    VoidCallback? onTap,
    VoidCallback? onSelect,
  }) {
    return GestureDetector(
      onTap: onTap ?? onSelect,
      onDoubleTap: onSelect,
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF4a9eff).withOpacity(0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: isSelected
              ? Border.all(color: const Color(0xFF4a9eff).withOpacity(0.4))
              : null,
        ),
        child: Row(
          children: [
            if (onTap != null)
              Icon(
                isExpanded ? Icons.expand_more : Icons.chevron_right,
                size: 16,
                color: Colors.white.withOpacity(0.5),
              ),
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              key,
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              suffix,
              style: TextStyle(
                color: color.withOpacity(0.7),
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPathActions() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: const BoxDecoration(
        color: Color(0xFF242430),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Selected: ',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 11,
                ),
              ),
              Expanded(
                child: Text(
                  _selectedPath!,
                  style: const TextStyle(
                    color: Color(0xFF4a9eff),
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy, size: 14),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _selectedPath!));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Path copied')),
                  );
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(maxWidth: 24),
                color: Colors.white.withOpacity(0.5),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _buildPathTypeButton(JsonPathType.events, 'Events'),
              _buildPathTypeButton(JsonPathType.eventName, 'Event Name'),
              _buildPathTypeButton(JsonPathType.timestamp, 'Timestamp'),
              _buildPathTypeButton(JsonPathType.winAmount, 'Win'),
              _buildPathTypeButton(JsonPathType.reelData, 'Reels'),
              _buildPathTypeButton(JsonPathType.balance, 'Balance'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPathTypeButton(JsonPathType type, String label) {
    return OutlinedButton(
      onPressed: () {
        widget.onPathSelected?.call(type, _selectedPath!);
      },
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF4a9eff),
        side: const BorderSide(color: Color(0xFF4a9eff)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: Size.zero,
      ),
      child: Text(label, style: const TextStyle(fontSize: 10)),
    );
  }

  void _toggleExpanded(String path) {
    setState(() {
      if (_expandedPaths.contains(path)) {
        _expandedPaths.remove(path);
      } else {
        _expandedPaths.add(path);
      }
    });
  }

  void _selectPath(String path) {
    setState(() {
      _selectedPath = _selectedPath == path ? null : path;
    });
  }

  IconData _getTypeIcon(dynamic value) {
    if (value is String) return Icons.text_fields;
    if (value is num) return Icons.numbers;
    if (value is bool) return Icons.toggle_on;
    if (value == null) return Icons.do_not_disturb;
    return Icons.help_outline;
  }

  Color _getTypeColor(dynamic value) {
    if (value is String) return const Color(0xFF40ff90);
    if (value is num) return const Color(0xFF40c8ff);
    if (value is bool) return const Color(0xFFff9040);
    if (value == null) return Colors.grey;
    return Colors.white;
  }

  String _formatValue(dynamic value) {
    if (value is String) {
      return '"${value.length > 20 ? '${value.substring(0, 20)}...' : value}"';
    }
    if (value == null) return 'null';
    return value.toString();
  }
}
