/// Smart Tab Organization Service
///
/// Provides intelligent tab suggestions and organization based on:
/// - User workflow patterns
/// - Task context (what they're currently doing)
/// - Frequently accessed tabs
/// - Related tab groupings
///
/// Features:
/// - Tab usage analytics
/// - Context-aware suggestions
/// - Auto-organization of tab order
/// - Quick-access tab sets for common tasks

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

/// Tab usage record
class TabUsageRecord {
  final String tabId;
  final DateTime timestamp;
  final String context; // What user was doing (e.g., 'editing_event', 'mixing')
  final Duration duration;

  TabUsageRecord({
    required this.tabId,
    required this.timestamp,
    required this.context,
    required this.duration,
  });

  Map<String, dynamic> toJson() => {
    'tabId': tabId,
    'timestamp': timestamp.toIso8601String(),
    'context': context,
    'duration': duration.inSeconds,
  };

  factory TabUsageRecord.fromJson(Map<String, dynamic> json) => TabUsageRecord(
    tabId: json['tabId'],
    timestamp: DateTime.parse(json['timestamp']),
    context: json['context'],
    duration: Duration(seconds: json['duration']),
  );
}

/// Tab set for common workflows
class TabSet {
  final String id;
  final String name;
  final String description;
  final List<String> tabIds;
  final String icon;

  const TabSet({
    required this.id,
    required this.name,
    required this.description,
    required this.tabIds,
    required this.icon,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'tabIds': tabIds,
    'icon': icon,
  };

  factory TabSet.fromJson(Map<String, dynamic> json) => TabSet(
    id: json['id'],
    name: json['name'],
    description: json['description'],
    tabIds: List<String>.from(json['tabIds']),
    icon: json['icon'],
  );
}

/// Built-in tab sets for common workflows
class BuiltInTabSets {
  static const audioDesign = TabSet(
    id: 'audio_design',
    name: 'Audio Design',
    description: 'Core audio authoring workflow',
    tabIds: ['eventList', 'commandBuilder', 'timeline', 'meters'],
    icon: '🎨',
  );

  static const mixing = TabSet(
    id: 'mixing',
    name: 'Mixing',
    description: 'Bus routing and mixing',
    tabIds: ['meters', 'dspCompressor', 'dspLimiter', 'busHierarchy'],
    icon: '🎛️',
  );

  static const debugging = TabSet(
    id: 'debugging',
    name: 'Debugging',
    description: 'Performance analysis and troubleshooting',
    tabIds: ['timeline', 'profiler', 'eventLog', 'rtpcDebugger'],
    icon: '🐛',
  );

  static const qa = TabSet(
    id: 'qa',
    name: 'QA Testing',
    description: 'Quality assurance workflow',
    tabIds: ['forcedOutcome', 'eventLog', 'profiler', 'validation'],
    icon: '✅',
  );

  static const production = TabSet(
    id: 'production',
    name: 'Production',
    description: 'Final export and packaging',
    tabIds: ['batchExport', 'validation', 'package', 'stems'],
    icon: '📦',
  );

  static List<TabSet> get all => [
    audioDesign,
    mixing,
    debugging,
    qa,
    production,
  ];
}

/// Smart tab organization service
class SmartTabService extends ChangeNotifier {
  static final SmartTabService instance = SmartTabService._();

  SmartTabService._();

  final List<TabUsageRecord> _usageHistory = [];
  final Map<String, int> _tabAccessCount = {};
  final Map<String, Duration> _totalDuration = {};
  final List<TabSet> _customTabSets = [];

  String? _currentContext;
  DateTime? _currentTabStartTime;
  String? _currentTabId;

  static const int _maxHistorySize = 1000;

  /// Initialize from SharedPreferences
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();

    // Load usage history
    final historyJson = prefs.getString('tab_usage_history');
    if (historyJson != null) {
      try {
        final List<dynamic> decoded = jsonDecode(historyJson);
        _usageHistory.clear();
        _usageHistory.addAll(decoded.map((e) => TabUsageRecord.fromJson(e)));

        // Rebuild stats
        _rebuildStats();
      } catch (e) { /* ignored */ }
    }

    // Load custom tab sets
    final setsJson = prefs.getString('custom_tab_sets');
    if (setsJson != null) {
      try {
        final List<dynamic> decoded = jsonDecode(setsJson);
        _customTabSets.clear();
        _customTabSets.addAll(decoded.map((e) => TabSet.fromJson(e)));
      } catch (e) { /* ignored */ }
    }

    notifyListeners();
  }

  /// Record tab switch
  void recordTabSwitch(String tabId, {String? context}) {
    // Record end of previous tab
    if (_currentTabId != null && _currentTabStartTime != null) {
      final duration = DateTime.now().difference(_currentTabStartTime!);
      final record = TabUsageRecord(
        tabId: _currentTabId!,
        timestamp: _currentTabStartTime!,
        context: _currentContext ?? 'unknown',
        duration: duration,
      );

      _usageHistory.add(record);

      // Trim history if too large
      if (_usageHistory.length > _maxHistorySize) {
        _usageHistory.removeAt(0);
      }

      // Update stats
      _tabAccessCount[_currentTabId!] = (_tabAccessCount[_currentTabId!] ?? 0) + 1;
      _totalDuration[_currentTabId!] = (_totalDuration[_currentTabId!] ?? Duration.zero) + duration;
    }

    // Start new tab
    _currentTabId = tabId;
    _currentTabStartTime = DateTime.now();
    _currentContext = context;

    _persist();
    notifyListeners();
  }

  /// Set current workflow context
  void setContext(String context) {
    _currentContext = context;
  }

  /// Get most frequently accessed tabs
  List<String> getMostFrequentTabs({int limit = 5}) {
    final sorted = _tabAccessCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sorted.take(limit).map((e) => e.key).toList();
  }

  /// Get tabs with most time spent
  List<String> getMostUsedTabs({int limit = 5}) {
    final sorted = _totalDuration.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sorted.take(limit).map((e) => e.key).toList();
  }

  /// Get tab suggestions based on current context
  List<String> getSuggestedTabs({String? context, int limit = 3}) {
    context ??= _currentContext ?? 'unknown';

    // Find tabs commonly used in this context
    final contextRecords = _usageHistory.where((r) => r.context == context).toList();

    if (contextRecords.isEmpty) {
      // No context data, return most frequent
      return getMostFrequentTabs(limit: limit);
    }

    final contextTabCounts = <String, int>{};
    for (final record in contextRecords) {
      contextTabCounts[record.tabId] = (contextTabCounts[record.tabId] ?? 0) + 1;
    }

    final sorted = contextTabCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sorted.take(limit).map((e) => e.key).toList();
  }

  /// Get related tabs (often accessed together)
  List<String> getRelatedTabs(String tabId, {int limit = 3}) {
    // Find sessions where this tab was used
    final sessions = <String, int>{};

    for (int i = 0; i < _usageHistory.length; i++) {
      if (_usageHistory[i].tabId == tabId) {
        // Look at tabs used within 5 minutes
        final sessionStart = _usageHistory[i].timestamp;
        final sessionEnd = sessionStart.add(const Duration(minutes: 5));

        for (int j = i; j < _usageHistory.length; j++) {
          final otherRecord = _usageHistory[j];
          if (otherRecord.timestamp.isAfter(sessionEnd)) break;
          if (otherRecord.tabId != tabId) {
            sessions[otherRecord.tabId] = (sessions[otherRecord.tabId] ?? 0) + 1;
          }
        }
      }
    }

    final sorted = sessions.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sorted.take(limit).map((e) => e.key).toList();
  }

  /// Get recommended tab set for current workflow
  TabSet? getRecommendedTabSet() {
    final context = _currentContext;
    if (context == null) return null;

    // Map contexts to tab sets
    final Map<String, TabSet> contextToSet = {
      'editing_event': BuiltInTabSets.audioDesign,
      'creating_event': BuiltInTabSets.audioDesign,
      'mixing': BuiltInTabSets.mixing,
      'testing': BuiltInTabSets.qa,
      'debugging': BuiltInTabSets.debugging,
      'exporting': BuiltInTabSets.production,
    };

    return contextToSet[context];
  }

  /// Create custom tab set
  void createTabSet(TabSet tabSet) {
    _customTabSets.add(tabSet);
    _persist();
    notifyListeners();
  }

  /// Delete custom tab set
  void deleteTabSet(String id) {
    _customTabSets.removeWhere((s) => s.id == id);
    _persist();
    notifyListeners();
  }

  /// Get all tab sets (built-in + custom)
  List<TabSet> getAllTabSets() {
    return [...BuiltInTabSets.all, ..._customTabSets];
  }

  /// Get tab usage stats
  Map<String, dynamic> getTabStats(String tabId) {
    return {
      'access_count': _tabAccessCount[tabId] ?? 0,
      'total_duration': _totalDuration[tabId]?.inSeconds ?? 0,
      'avg_duration': (_totalDuration[tabId]?.inSeconds ?? 0) / (_tabAccessCount[tabId] ?? 1),
      'related_tabs': getRelatedTabs(tabId, limit: 5),
    };
  }

  /// Clear all usage history
  void clearHistory() {
    _usageHistory.clear();
    _tabAccessCount.clear();
    _totalDuration.clear();
    _persist();
    notifyListeners();
  }

  void _rebuildStats() {
    _tabAccessCount.clear();
    _totalDuration.clear();

    for (final record in _usageHistory) {
      _tabAccessCount[record.tabId] = (_tabAccessCount[record.tabId] ?? 0) + 1;
      _totalDuration[record.tabId] = (_totalDuration[record.tabId] ?? Duration.zero) + record.duration;
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Save history (last 1000 records)
      final historyJson = jsonEncode(_usageHistory.map((r) => r.toJson()).toList());
      await prefs.setString('tab_usage_history', historyJson);

      // Save custom tab sets
      final setsJson = jsonEncode(_customTabSets.map((s) => s.toJson()).toList());
      await prefs.setString('custom_tab_sets', setsJson);
    } catch (e) { /* ignored */ }
  }
}
