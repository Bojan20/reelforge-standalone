/// Debug Console Widget
///
/// Overlay console that captures and displays logs from:
/// - Dart print() statements
/// - Native FFI logs (via callback)
/// - Engine events
///
/// Toggle with Ctrl+Shift+D or from menu

import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/fluxforge_theme.dart';

/// Log entry with timestamp and level
class LogEntry {
  final DateTime timestamp;
  final String message;
  final LogLevel level;
  final String? source;

  LogEntry({
    required this.message,
    this.level = LogLevel.info,
    this.source,
  }) : timestamp = DateTime.now();

  String get formattedTime {
    final t = timestamp;
    return '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}:'
        '${t.second.toString().padLeft(2, '0')}.'
        '${t.millisecond.toString().padLeft(3, '0')}';
  }
}

enum LogLevel { debug, info, warning, error }

/// Global debug log manager
class DebugLog {
  static final DebugLog _instance = DebugLog._();
  static DebugLog get instance => _instance;

  DebugLog._();

  final _logs = Queue<LogEntry>();
  final _controller = StreamController<LogEntry>.broadcast();
  static const int _maxLogs = 500;

  Stream<LogEntry> get stream => _controller.stream;
  List<LogEntry> get logs => _logs.toList();

  void log(String message, {LogLevel level = LogLevel.info, String? source}) {
    final entry = LogEntry(message: message, level: level, source: source);
    _logs.addLast(entry);
    while (_logs.length > _maxLogs) {
      _logs.removeFirst();
    }
    _controller.add(entry);
  }

  void debug(String message, [String? source]) =>
      log(message, level: LogLevel.debug, source: source);
  void info(String message, [String? source]) =>
      log(message, level: LogLevel.info, source: source);
  void warn(String message, [String? source]) =>
      log(message, level: LogLevel.warning, source: source);
  void error(String message, [String? source]) =>
      log(message, level: LogLevel.error, source: source);

  void clear() {
    _logs.clear();
  }

  void dispose() {
    _controller.close();
  }
}

/// Shortcut for logging
void debugLog(String message, {LogLevel level = LogLevel.info, String? source}) {
  DebugLog.instance.log(message, level: level, source: source);
}

/// Debug Console Overlay Widget
class DebugConsole extends StatefulWidget {
  final VoidCallback onClose;

  const DebugConsole({super.key, required this.onClose});

  @override
  State<DebugConsole> createState() => _DebugConsoleState();
}

class _DebugConsoleState extends State<DebugConsole> {
  final _scrollController = ScrollController();
  final _filterController = TextEditingController();
  late StreamSubscription<LogEntry> _subscription;
  List<LogEntry> _filteredLogs = [];
  String _filter = '';
  Set<LogLevel> _enabledLevels = {LogLevel.debug, LogLevel.info, LogLevel.warning, LogLevel.error};
  bool _autoScroll = true;

  @override
  void initState() {
    super.initState();
    _updateFilteredLogs();
    _subscription = DebugLog.instance.stream.listen((entry) {
      _updateFilteredLogs();
      if (_autoScroll) {
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
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    _scrollController.dispose();
    _filterController.dispose();
    super.dispose();
  }

  void _updateFilteredLogs() {
    setState(() {
      _filteredLogs = DebugLog.instance.logs.where((log) {
        if (!_enabledLevels.contains(log.level)) return false;
        if (_filter.isNotEmpty) {
          return log.message.toLowerCase().contains(_filter.toLowerCase()) ||
              (log.source?.toLowerCase().contains(_filter.toLowerCase()) ?? false);
        }
        return true;
      }).toList();
    });
  }

  Color _levelColor(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return Colors.grey;
      case LogLevel.info:
        return FluxForgeTheme.accentBlue;
      case LogLevel.warning:
        return FluxForgeTheme.accentOrange;
      case LogLevel.error:
        return FluxForgeTheme.accentRed;
    }
  }

  String _levelLabel(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return 'DBG';
      case LogLevel.info:
        return 'INF';
      case LogLevel.warning:
        return 'WRN';
      case LogLevel.error:
        return 'ERR';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgDeepest.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: FluxForgeTheme.borderSubtle),
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
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: FluxForgeTheme.bgMid,
                borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.terminal, color: FluxForgeTheme.accentGreen, size: 18),
                  const SizedBox(width: 8),
                  const Text(
                    'DEBUG CONSOLE',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const Spacer(),
                  // Level filters
                  ...LogLevel.values.map((level) => Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: FilterChip(
                      label: Text(_levelLabel(level), style: const TextStyle(fontSize: 10)),
                      selected: _enabledLevels.contains(level),
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _enabledLevels.add(level);
                          } else {
                            _enabledLevels.remove(level);
                          }
                        });
                        _updateFilteredLogs();
                      },
                      selectedColor: _levelColor(level).withValues(alpha: 0.3),
                      checkmarkColor: _levelColor(level),
                      backgroundColor: FluxForgeTheme.bgDeep,
                      labelStyle: TextStyle(
                        color: _enabledLevels.contains(level) ? _levelColor(level) : Colors.white54,
                      ),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: EdgeInsets.zero,
                    ),
                  )),
                  const SizedBox(width: 8),
                  // Auto-scroll toggle
                  IconButton(
                    icon: Icon(
                      _autoScroll ? Icons.vertical_align_bottom : Icons.vertical_align_center,
                      size: 16,
                    ),
                    color: _autoScroll ? FluxForgeTheme.accentGreen : Colors.white54,
                    onPressed: () => setState(() => _autoScroll = !_autoScroll),
                    tooltip: 'Auto-scroll',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  ),
                  // Clear
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 16),
                    color: Colors.white54,
                    onPressed: () {
                      DebugLog.instance.clear();
                      _updateFilteredLogs();
                    },
                    tooltip: 'Clear',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  ),
                  // Close
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    color: Colors.white54,
                    onPressed: widget.onClose,
                    tooltip: 'Close (Ctrl+Shift+D)',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  ),
                ],
              ),
            ),

            // Filter bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: FluxForgeTheme.bgDeep,
              child: Row(
                children: [
                  const Icon(Icons.search, size: 14, color: Colors.white38),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _filterController,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      decoration: const InputDecoration(
                        hintText: 'Filter logs...',
                        hintStyle: TextStyle(color: Colors.white38, fontSize: 12),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onChanged: (value) {
                        _filter = value;
                        _updateFilteredLogs();
                      },
                    ),
                  ),
                  Text(
                    '${_filteredLogs.length} entries',
                    style: const TextStyle(color: Colors.white38, fontSize: 10),
                  ),
                ],
              ),
            ),

            // Log entries
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(8),
                itemCount: _filteredLogs.length,
                itemBuilder: (context, index) {
                  final log = _filteredLogs[index];
                  return _LogEntryWidget(log: log, levelColor: _levelColor(log.level));
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogEntryWidget extends StatelessWidget {
  final LogEntry log;
  final Color levelColor;

  const _LogEntryWidget({required this.log, required this.levelColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timestamp
          Text(
            log.formattedTime,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 10,
              fontFamily: 'JetBrains Mono',
            ),
          ),
          const SizedBox(width: 8),
          // Level badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: levelColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              log.level.name.substring(0, 1).toUpperCase(),
              style: TextStyle(
                color: levelColor,
                fontSize: 9,
                fontWeight: FontWeight.bold,
                fontFamily: 'JetBrains Mono',
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Source (if any)
          if (log.source != null) ...[
            Text(
              '[${log.source}]',
              style: TextStyle(
                color: levelColor.withValues(alpha: 0.7),
                fontSize: 10,
                fontFamily: 'JetBrains Mono',
              ),
            ),
            const SizedBox(width: 4),
          ],
          // Message
          Expanded(
            child: SelectableText(
              log.message,
              style: TextStyle(
                color: log.level == LogLevel.error ? levelColor : Colors.white70,
                fontSize: 11,
                fontFamily: 'JetBrains Mono',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Mixin to add debug console to any screen
mixin DebugConsoleMixin<T extends StatefulWidget> on State<T> {
  bool _showDebugConsole = false;

  void toggleDebugConsole() {
    setState(() => _showDebugConsole = !_showDebugConsole);
  }

  Widget wrapWithDebugConsole(Widget child) {
    return Stack(
      children: [
        child,
        if (_showDebugConsole)
          Positioned.fill(
            child: DebugConsole(onClose: toggleDebugConsole),
          ),
      ],
    );
  }

  KeyEventResult handleDebugShortcut(KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.keyD &&
        HardwareKeyboard.instance.isControlPressed &&
        HardwareKeyboard.instance.isShiftPressed) {
      toggleDebugConsole();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }
}
