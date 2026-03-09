/// Auto-Color Service — Track name pattern matching → color/icon assignment
///
/// Singleton service that manages auto-color rules and applies them
/// when tracks are created or batch-applied to existing tracks.
///
/// Built-in presets cover common audio production naming conventions:
/// drums, bass, guitar, vocals, synth, keys, strings, brass, FX, bus, etc.
library;

import 'package:flutter/material.dart';
import '../models/auto_color_rule.dart';

/// Central auto-color rules service — singleton
class AutoColorService extends ChangeNotifier {
  AutoColorService._() {
    _rules = List.of(_builtInRules);
  }
  static final AutoColorService instance = AutoColorService._();

  late List<AutoColorRule> _rules;

  /// All rules sorted by priority
  List<AutoColorRule> get rules => List.unmodifiable(_rules);

  /// Number of rules
  int get count => _rules.length;

  /// Whether auto-color is enabled globally
  bool _enabled = true;
  bool get enabled => _enabled;
  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MATCHING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Find the first matching rule for a track name
  AutoColorResult match(String trackName) {
    if (!_enabled || trackName.isEmpty) {
      return const AutoColorResult(color: Color(0xFF5B9BD5));
    }

    for (final rule in _rules) {
      if (rule.matches(trackName)) {
        return AutoColorResult(
          rule: rule,
          color: rule.color,
          icon: rule.icon,
        );
      }
    }

    return const AutoColorResult(color: Color(0xFF5B9BD5));
  }

  /// Test a pattern against a track name (for rule editor preview)
  bool testPattern(String pattern, String trackName) {
    if (pattern.isEmpty || trackName.isEmpty) return false;
    try {
      return RegExp(pattern, caseSensitive: false).hasMatch(trackName);
    } catch (_) {
      return false;
    }
  }

  /// Validate a regex pattern
  String? validatePattern(String pattern) {
    if (pattern.isEmpty) return 'Pattern cannot be empty';
    try {
      RegExp(pattern);
      return null;
    } catch (e) {
      return 'Invalid regex: $e';
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CRUD
  // ═══════════════════════════════════════════════════════════════════════════

  /// Add a new rule
  void addRule(AutoColorRule rule) {
    _rules.add(rule);
    _sortRules();
    notifyListeners();
  }

  /// Update an existing rule
  void updateRule(AutoColorRule rule) {
    final idx = _rules.indexWhere((r) => r.id == rule.id);
    if (idx >= 0) {
      _rules[idx] = rule;
      _sortRules();
      notifyListeners();
    }
  }

  /// Remove a rule by ID
  void removeRule(String id) {
    _rules.removeWhere((r) => r.id == id);
    notifyListeners();
  }

  /// Reorder rule (drag & drop)
  void reorderRule(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) newIndex--;
    final rule = _rules.removeAt(oldIndex);
    _rules.insert(newIndex, rule);
    // Update priorities to match new order
    for (int i = 0; i < _rules.length; i++) {
      _rules[i] = _rules[i].copyWith(priority: i);
    }
    notifyListeners();
  }

  /// Toggle a rule's enabled state
  void toggleRule(String id) {
    final idx = _rules.indexWhere((r) => r.id == id);
    if (idx >= 0) {
      _rules[idx] = _rules[idx].copyWith(enabled: !_rules[idx].enabled);
      notifyListeners();
    }
  }

  /// Reset to built-in defaults
  void resetToDefaults() {
    _rules = List.of(_builtInRules);
    notifyListeners();
  }

  void _sortRules() {
    _rules.sort((a, b) => a.priority.compareTo(b.priority));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // IMPORT / EXPORT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Export current rules to JSON string
  String exportRules() => AutoColorRuleSet.toJsonString(_rules);

  /// Import rules from JSON string (replaces current rules)
  bool importRules(String json) {
    try {
      final imported = AutoColorRuleSet.fromJsonString(json);
      if (imported.isEmpty) return false;
      _rules = imported;
      _sortRules();
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Merge imported rules (adds to existing, skips duplicates by ID)
  int mergeRules(String json) {
    try {
      final imported = AutoColorRuleSet.fromJsonString(json);
      final existingIds = _rules.map((r) => r.id).toSet();
      int added = 0;
      for (final rule in imported) {
        if (!existingIds.contains(rule.id)) {
          _rules.add(rule.copyWith(priority: _rules.length));
          added++;
        }
      }
      if (added > 0) notifyListeners();
      return added;
    } catch (_) {
      return 0;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILT-IN PRESETS — industry-standard audio naming conventions
  // ═══════════════════════════════════════════════════════════════════════════

  static const List<AutoColorRule> _builtInRules = [
    // ─── DRUMS ─────────────────────────────────────────────────────────
    AutoColorRule(
      id: 'builtin.drums',
      name: 'Drums',
      pattern: r'^(drum|kit|oh|room|snr?|sn|kick|kik|bd|hh|hat|tom|cym|crash|ride|clap|perc)',
      color: Color(0xFFFF4040), // Red
      icon: Icons.radio_button_checked,
      priority: 0,
    ),
    // ─── BASS ──────────────────────────────────────────────────────────
    AutoColorRule(
      id: 'builtin.bass',
      name: 'Bass',
      pattern: r'^(bass|bas|sub|low.?end|808)',
      color: Color(0xFFFF9040), // Orange
      icon: Icons.graphic_eq,
      priority: 1,
    ),
    // ─── GUITAR ────────────────────────────────────────────────────────
    AutoColorRule(
      id: 'builtin.guitar',
      name: 'Guitar',
      pattern: r'(guitar|gtr|guit|acou?st|elec.*gtr|strat|tele|les.?paul)',
      color: Color(0xFFFFD040), // Yellow
      icon: Icons.music_note,
      priority: 2,
    ),
    // ─── KEYS / PIANO ──────────────────────────────────────────────────
    AutoColorRule(
      id: 'builtin.keys',
      name: 'Keys',
      pattern: r'(keys?|piano|pno|organ|rhodes|wurli|clav|epiano|e.?piano)',
      color: Color(0xFF90FF40), // Lime
      icon: Icons.piano,
      priority: 3,
    ),
    // ─── VOCALS ────────────────────────────────────────────────────────
    AutoColorRule(
      id: 'builtin.vocals',
      name: 'Vocals',
      pattern: r'(vox|vocal|voice|voc|sing|lead.?v|back.?v|bgv|bv|choir|harmony|adlib)',
      color: Color(0xFF40D0FF), // Cyan
      icon: Icons.mic,
      priority: 4,
    ),
    // ─── SYNTH ─────────────────────────────────────────────────────────
    AutoColorRule(
      id: 'builtin.synth',
      name: 'Synth',
      pattern: r'(synth|pad|lead|arp|seq|saw|square|analog|poly)',
      color: Color(0xFF9040FF), // Violet
      icon: Icons.waves,
      priority: 5,
    ),
    // ─── STRINGS ───────────────────────────────────────────────────────
    AutoColorRule(
      id: 'builtin.strings',
      name: 'Strings',
      pattern: r'(string|violin|viola|cello|vlc|vln|orch|ensemble|contrabass)',
      color: Color(0xFF40FF90), // Mint
      icon: Icons.queue_music,
      priority: 6,
    ),
    // ─── BRASS / WINDS ─────────────────────────────────────────────────
    AutoColorRule(
      id: 'builtin.brass',
      name: 'Brass',
      pattern: r'(brass|trumpet|tpt|trombone|tbn|horn|sax|flute|fl|clarinet|oboe|woodwind)',
      color: Color(0xFFD040FF), // Magenta
      icon: Icons.music_note,
      priority: 7,
    ),
    // ─── FX / EFFECTS ──────────────────────────────────────────────────
    AutoColorRule(
      id: 'builtin.fx',
      name: 'FX',
      pattern: r'(fx|sfx|effect|foley|atmo|ambien|noise|riser|impact|whoosh|hit|boom)',
      color: Color(0xFFFF40D0), // Pink
      icon: Icons.blur_on,
      priority: 8,
    ),
    // ─── BUS / GROUP ───────────────────────────────────────────────────
    AutoColorRule(
      id: 'builtin.bus',
      name: 'Bus',
      pattern: r'(bus|grp|group|submix|stem|aux|send|return)',
      color: Color(0xFFB0B0B0), // Gray
      icon: Icons.call_split,
      priority: 9,
    ),
    // ─── MASTER ────────────────────────────────────────────────────────
    AutoColorRule(
      id: 'builtin.master',
      name: 'Master',
      pattern: r'^(master|main|stereo.?out|mix.?bus|2.?bus)',
      color: Color(0xFFF0F0F0), // White
      icon: Icons.speaker,
      priority: 10,
    ),
    // ─── DIALOG / VO ───────────────────────────────────────────────────
    AutoColorRule(
      id: 'builtin.dialog',
      name: 'Dialog',
      pattern: r'(dialog|dialogue|vo|voiceover|narr|narrator|adr)',
      color: Color(0xFF4090FF), // Blue
      icon: Icons.record_voice_over,
      priority: 11,
    ),
  ];
}
