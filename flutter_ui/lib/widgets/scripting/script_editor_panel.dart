// Script Editor Panel — Lua Script Editor for FluxForge
//
// Features:
// - Code editor with syntax highlighting (simulated)
// - Built-in script templates
// - Execution with result display
// - Available API functions reference
// - Script history
//
// Usage:
//   ScriptEditorPanel()

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/scripting/lua_bridge.dart';
import '../../services/scripting/json_rpc_server.dart';

class ScriptEditorPanel extends StatefulWidget {
  const ScriptEditorPanel({super.key});

  @override
  State<ScriptEditorPanel> createState() => _ScriptEditorPanelState();
}

class _ScriptEditorPanelState extends State<ScriptEditorPanel> {
  final _scriptController = TextEditingController();
  final _luaBridge = LuaBridge.instance;
  final _jsonRpcServer = JsonRpcServer.instance;

  String _output = '';
  bool _isExecuting = false;
  final List<String> _history = [];
  int _historyIndex = -1;

  @override
  void initState() {
    super.initState();
    _scriptController.text = _getDefaultScript();
  }

  @override
  void dispose() {
    _scriptController.dispose();
    super.dispose();
  }

  String _getDefaultScript() {
    return '''-- FluxForge Lua Script
-- Available functions: fluxforge.createEvent, addLayer, triggerStage, etc.

return fluxforge.getProjectInfo()
''';
  }

  Future<void> _executeScript() async {
    final script = _scriptController.text;
    if (script.isEmpty) return;

    setState(() {
      _isExecuting = true;
      _output = 'Executing...';
    });

    // Add to history
    _history.add(script);
    if (_history.length > 50) _history.removeAt(0);
    _historyIndex = _history.length;

    final result = await _luaBridge.execute(script);

    setState(() {
      _isExecuting = false;
      if (result.success) {
        _output = 'Success (${result.executionTime.inMilliseconds}ms):\n${result.returnValue}';
      } else {
        _output = 'Error:\n${result.error}';
      }
    });
  }

  void _loadTemplate(String template) {
    setState(() {
      _scriptController.text = template;
      _output = '';
    });
  }

  void _clearScript() {
    setState(() {
      _scriptController.clear();
      _output = '';
    });
  }

  void _navigateHistory(bool forward) {
    if (_history.isEmpty) return;

    setState(() {
      if (forward && _historyIndex < _history.length - 1) {
        _historyIndex++;
        _scriptController.text = _history[_historyIndex];
      } else if (!forward && _historyIndex > 0) {
        _historyIndex--;
        _scriptController.text = _history[_historyIndex];
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1a1a20),
            border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.1))),
          ),
          child: Row(
            children: [
              const Icon(Icons.code, color: Color(0xFF4A9EFF), size: 20),
              const SizedBox(width: 8),
              const Text(
                'Lua Script Editor',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              // JSON-RPC Server Toggle
              _buildServerToggle(),
            ],
          ),
        ),

        // Toolbar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF121216),
            border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05))),
          ),
          child: Row(
            children: [
              _buildToolbarButton(
                'Execute',
                Icons.play_arrow,
                _isExecuting ? null : _executeScript,
                color: const Color(0xFF40FF90),
              ),
              const SizedBox(width: 4),
              _buildToolbarButton('Clear', Icons.clear, _clearScript),
              const SizedBox(width: 4),
              _buildToolbarButton('Templates', Icons.library_books, _showTemplates),
              const SizedBox(width: 4),
              _buildToolbarButton('API Ref', Icons.functions, _showApiReference),
              const Spacer(),
              // History navigation
              IconButton(
                icon: const Icon(Icons.arrow_back, size: 16),
                onPressed: _historyIndex > 0 ? () => _navigateHistory(false) : null,
                tooltip: 'Previous script',
                iconSize: 16,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              IconButton(
                icon: const Icon(Icons.arrow_forward, size: 16),
                onPressed: _historyIndex < _history.length - 1
                    ? () => _navigateHistory(true)
                    : null,
                tooltip: 'Next script',
                iconSize: 16,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
        ),

        // Script Editor
        Expanded(
          flex: 3,
          child: Container(
            color: const Color(0xFF0a0a0c),
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _scriptController,
              maxLines: null,
              expands: true,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                color: Colors.white,
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'Enter Lua script...',
                hintStyle: TextStyle(color: Colors.grey),
              ),
            ),
          ),
        ),

        // Output
        Container(
          height: 1,
          color: Colors.white.withOpacity(0.1),
        ),
        Expanded(
          flex: 2,
          child: Container(
            color: const Color(0xFF121216),
            padding: const EdgeInsets.all(12),
            child: SingleChildScrollView(
              child: SelectableText(
                _output.isEmpty ? 'Output will appear here...' : _output,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: _output.contains('Error:')
                      ? const Color(0xFFFF4060)
                      : _output.contains('Success')
                          ? const Color(0xFF40FF90)
                          : Colors.grey,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildServerToggle() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'JSON-RPC Server',
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 12,
          ),
        ),
        const SizedBox(width: 8),
        Switch(
          value: _jsonRpcServer.isRunning,
          onChanged: (value) async {
            if (value) {
              await _jsonRpcServer.start();
            } else {
              await _jsonRpcServer.stop();
            }
            setState(() {});
          },
          activeColor: const Color(0xFF40FF90),
        ),
        if (_jsonRpcServer.isRunning) ...[
          const SizedBox(width: 8),
          Text(
            ':${_jsonRpcServer.port}',
            style: const TextStyle(
              color: Color(0xFF40FF90),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildToolbarButton(
    String label,
    IconData icon,
    VoidCallback? onPressed, {
    Color? color,
  }) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16, color: color),
      label: Text(
        label,
        style: TextStyle(fontSize: 12, color: color),
      ),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  void _showTemplates() {
    showDialog(
      context: context,
      builder: (context) => _TemplateDialog(onSelect: _loadTemplate),
    );
  }

  void _showApiReference() {
    showDialog(
      context: context,
      builder: (context) => _ApiReferenceDialog(),
    );
  }
}

class _TemplateDialog extends StatelessWidget {
  final Function(String) onSelect;

  const _TemplateDialog({required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final templates = {
      'Create Event': '''-- Create a new event
local result = fluxforge.createEvent("MyEvent", "SPIN_START")
return result''',
      'Add Layers to Event': '''-- Add multiple layers to an event
fluxforge.addLayer("evt_123", "/audio/spin.wav", 1.0, 0.0)
fluxforge.addLayer("evt_123", "/audio/whoosh.wav", 0.8, -0.3)
return "Layers added"''',
      'Trigger Multiple Stages': '''-- Trigger a sequence of stages
fluxforge.triggerStage("SPIN_START")
fluxforge.triggerStage("REEL_STOP_0")
fluxforge.triggerStage("REEL_STOP_1")
return "Stages triggered"''',
      'Batch Create Events': '''-- Create multiple events
local events = {}
for i = 1, 5 do
  local name = "Event" .. i
  local result = fluxforge.createEvent(name, "STAGE_" .. i)
  table.insert(events, result.eventId)
end
return events''',
      'Project Info': '''-- Get project information
return fluxforge.getProjectInfo()''',
    };

    return AlertDialog(
      title: const Text('Script Templates'),
      content: SizedBox(
        width: 400,
        child: ListView(
          shrinkWrap: true,
          children: templates.entries.map((entry) {
            return ListTile(
              title: Text(entry.key),
              trailing: const Icon(Icons.arrow_forward),
              onTap: () {
                onSelect(entry.value);
                Navigator.pop(context);
              },
            );
          }).toList(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _ApiReferenceDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final functions = LuaBridge.instance.getAvailableFunctions();

    return AlertDialog(
      title: const Text('FluxForge API Reference'),
      content: SizedBox(
        width: 500,
        height: 400,
        child: ListView.builder(
          itemCount: functions.length,
          itemBuilder: (context, index) {
            return ListTile(
              dense: true,
              title: Text(
                functions[index],
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
              leading: Icon(Icons.functions, size: 16),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
