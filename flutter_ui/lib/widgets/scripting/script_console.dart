/// FluxForge Studio Script Console
///
/// Lua REPL console with:
/// - Interactive code execution
/// - Output/error display
/// - Script browser
/// - History navigation
/// - Syntax highlighting (basic)

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../theme/fluxforge_theme.dart';
import '../../providers/script_provider.dart';

/// Script Console Widget
class ScriptConsole extends StatefulWidget {
  final VoidCallback? onClose;

  const ScriptConsole({super.key, this.onClose});

  @override
  State<ScriptConsole> createState() => _ScriptConsoleState();
}

class _ScriptConsoleState extends State<ScriptConsole> with SingleTickerProviderStateMixin {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final _inputFocusNode = FocusNode();
  final List<_ConsoleEntry> _history = [];
  final List<String> _commandHistory = [];
  int _historyIndex = -1;
  late TabController _tabController;
  bool _isInitializing = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initEngine();
  }

  Future<void> _initEngine() async {
    setState(() => _isInitializing = true);
    final provider = context.read<ScriptProvider>();
    await provider.initialize();
    setState(() => _isInitializing = false);
    _addSystemMessage('Script engine ready. Type Lua code or use rf.* API.');
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _addSystemMessage(String message) {
    setState(() {
      _history.add(_ConsoleEntry(
        text: message,
        type: _EntryType.system,
      ));
    });
    _scrollToBottom();
  }

  void _addInput(String input) {
    setState(() {
      _history.add(_ConsoleEntry(
        text: '> $input',
        type: _EntryType.input,
      ));
    });
  }

  void _addOutput(String output) {
    if (output.isEmpty) return;
    setState(() {
      _history.add(_ConsoleEntry(
        text: output,
        type: _EntryType.output,
      ));
    });
  }

  void _addError(String error) {
    setState(() {
      _history.add(_ConsoleEntry(
        text: error,
        type: _EntryType.error,
      ));
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _executeCode(String code) async {
    if (code.trim().isEmpty) return;

    // Add to command history
    if (_commandHistory.isEmpty || _commandHistory.last != code) {
      _commandHistory.add(code);
    }
    _historyIndex = -1;

    _addInput(code);
    _inputController.clear();

    final provider = context.read<ScriptProvider>();
    final result = await provider.execute(code);

    if (result.success) {
      if (result.output != null && result.output!.isNotEmpty) {
        _addOutput(result.output!);
      }
      _addSystemMessage('Executed in ${result.durationMs}ms');
    } else {
      _addError(result.error ?? 'Unknown error');
    }

    _scrollToBottom();
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    // Up arrow - previous command
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (_commandHistory.isNotEmpty) {
        if (_historyIndex < _commandHistory.length - 1) {
          _historyIndex++;
          _inputController.text = _commandHistory[_commandHistory.length - 1 - _historyIndex];
          _inputController.selection = TextSelection.collapsed(
            offset: _inputController.text.length,
          );
        }
      }
    }

    // Down arrow - next command
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_historyIndex > 0) {
        _historyIndex--;
        _inputController.text = _commandHistory[_commandHistory.length - 1 - _historyIndex];
        _inputController.selection = TextSelection.collapsed(
          offset: _inputController.text.length,
        );
      } else if (_historyIndex == 0) {
        _historyIndex = -1;
        _inputController.clear();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ScriptProvider>(
      builder: (context, provider, _) {
        return Container(
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgDeepest.withValues(alpha: 0.98),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: FluxForgeTheme.accentCyan.withValues(alpha: 0.3)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Column(
            children: [
              _buildHeader(provider),
              _buildTabBar(),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildConsoleTab(provider),
                    _buildScriptsTab(provider),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(ScriptProvider provider) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.terminal,
            color: FluxForgeTheme.accentCyan,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            'SCRIPT CONSOLE',
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 12,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 12),
          // Status indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: provider.isInitialized
                  ? FluxForgeTheme.accentGreen.withValues(alpha: 0.2)
                  : FluxForgeTheme.accentOrange.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: provider.isInitialized
                        ? FluxForgeTheme.accentGreen
                        : FluxForgeTheme.accentOrange,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  provider.isInitialized ? 'Ready' : 'Initializing...',
                  style: TextStyle(
                    color: provider.isInitialized
                        ? FluxForgeTheme.accentGreen
                        : FluxForgeTheme.accentOrange,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          // Clear button
          IconButton(
            icon: Icon(Icons.delete_outline, size: 16, color: FluxForgeTheme.textSecondary),
            onPressed: () => setState(() => _history.clear()),
            tooltip: 'Clear',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          // Close button
          if (widget.onClose != null)
            IconButton(
              icon: Icon(Icons.close, size: 16, color: FluxForgeTheme.textSecondary),
              onPressed: widget.onClose,
              tooltip: 'Close',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: FluxForgeTheme.bgDeep,
      child: TabBar(
        controller: _tabController,
        indicatorColor: FluxForgeTheme.accentCyan,
        labelColor: FluxForgeTheme.accentCyan,
        unselectedLabelColor: FluxForgeTheme.textSecondary,
        labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
        tabs: const [
          Tab(text: 'CONSOLE', height: 32),
          Tab(text: 'SCRIPTS', height: 32),
        ],
      ),
    );
  }

  Widget _buildConsoleTab(ScriptProvider provider) {
    return Column(
      children: [
        // Output area
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(12),
            itemCount: _history.length,
            itemBuilder: (context, index) {
              final entry = _history[index];
              return _buildEntry(entry);
            },
          ),
        ),
        // Input area
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgMid,
            border: Border(
              top: BorderSide(color: FluxForgeTheme.borderSubtle),
            ),
          ),
          child: Row(
            children: [
              Text(
                'lua>',
                style: TextStyle(
                  color: FluxForgeTheme.accentCyan,
                  fontFamily: 'JetBrains Mono',
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: KeyboardListener(
                  focusNode: _inputFocusNode,
                  onKeyEvent: _handleKeyEvent,
                  child: TextField(
                    controller: _inputController,
                    style: TextStyle(
                      color: FluxForgeTheme.textPrimary,
                      fontFamily: 'JetBrains Mono',
                      fontSize: 12,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Enter Lua code...',
                      hintStyle: TextStyle(
                        color: FluxForgeTheme.textSecondary.withValues(alpha: 0.5),
                        fontFamily: 'JetBrains Mono',
                        fontSize: 12,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onSubmitted: _executeCode,
                    enabled: provider.isInitialized && !provider.isRunning,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  provider.isRunning ? Icons.hourglass_empty : Icons.play_arrow,
                  size: 18,
                  color: provider.isInitialized
                      ? FluxForgeTheme.accentGreen
                      : FluxForgeTheme.textSecondary,
                ),
                onPressed: provider.isInitialized && !provider.isRunning
                    ? () => _executeCode(_inputController.text)
                    : null,
                tooltip: 'Execute (Enter)',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEntry(_ConsoleEntry entry) {
    Color textColor;
    switch (entry.type) {
      case _EntryType.input:
        textColor = FluxForgeTheme.accentCyan;
      case _EntryType.output:
        textColor = FluxForgeTheme.textPrimary;
      case _EntryType.error:
        textColor = FluxForgeTheme.accentRed;
      case _EntryType.system:
        textColor = FluxForgeTheme.textSecondary;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: SelectableText(
        entry.text,
        style: TextStyle(
          color: textColor,
          fontFamily: 'JetBrains Mono',
          fontSize: 11,
        ),
      ),
    );
  }

  Widget _buildScriptsTab(ScriptProvider provider) {
    final scripts = provider.scripts;

    return Column(
      children: [
        // Toolbar
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  style: TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 11),
                  decoration: InputDecoration(
                    hintText: 'Search scripts...',
                    hintStyle: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 11),
                    prefixIcon: Icon(Icons.search, size: 16, color: FluxForgeTheme.textSecondary),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: FluxForgeTheme.borderSubtle),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: FluxForgeTheme.borderSubtle),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: FluxForgeTheme.accentCyan),
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(Icons.folder_open, size: 18, color: FluxForgeTheme.textSecondary),
                onPressed: () {
                  // TODO: Open file picker to load script
                },
                tooltip: 'Load Script',
              ),
              IconButton(
                icon: Icon(Icons.refresh, size: 18, color: FluxForgeTheme.textSecondary),
                onPressed: () => provider.refreshScripts(),
                tooltip: 'Refresh',
              ),
            ],
          ),
        ),
        // Script list
        Expanded(
          child: scripts.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.code_off,
                        size: 48,
                        color: FluxForgeTheme.textSecondary.withValues(alpha: 0.3),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No scripts loaded',
                        style: TextStyle(
                          color: FluxForgeTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: scripts.length,
                  itemBuilder: (context, index) {
                    final script = scripts[index];
                    return _buildScriptTile(script, provider);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildScriptTile(LoadedScript script, ScriptProvider provider) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: ListTile(
        dense: true,
        leading: Icon(
          script.isBuiltin ? Icons.star : Icons.description,
          size: 18,
          color: script.isBuiltin
              ? FluxForgeTheme.accentOrange
              : FluxForgeTheme.accentCyan,
        ),
        title: Text(
          script.name,
          style: TextStyle(
            color: FluxForgeTheme.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: script.description.isNotEmpty
            ? Text(
                script.description,
                style: TextStyle(
                  color: FluxForgeTheme.textSecondary,
                  fontSize: 10,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (script.isBuiltin)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: FluxForgeTheme.accentOrange.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'BUILTIN',
                  style: TextStyle(
                    color: FluxForgeTheme.accentOrange,
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(
                Icons.play_arrow,
                size: 18,
                color: FluxForgeTheme.accentGreen,
              ),
              onPressed: () async {
                _tabController.animateTo(0);
                _addSystemMessage('Running script: ${script.name}');
                final result = await provider.runScript(script.name);
                if (result.success) {
                  _addSystemMessage('Script completed in ${result.durationMs}ms');
                } else {
                  _addError(result.error ?? 'Script failed');
                }
                _scrollToBottom();
              },
              tooltip: 'Run',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
          ],
        ),
        onTap: () {
          // Show script code preview
          _inputController.text = '-- Run: ${script.name}\nrf.action("${script.name}", "")';
        },
      ),
    );
  }
}

// Internal types
enum _EntryType { input, output, error, system }

class _ConsoleEntry {
  final String text;
  final _EntryType type;
  final DateTime timestamp;

  _ConsoleEntry({
    required this.text,
    required this.type,
  }) : timestamp = DateTime.now();
}
