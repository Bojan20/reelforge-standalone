/// Auto-Color Rule Model
///
/// Defines rules that automatically assign colors and icons to tracks
/// based on regex pattern matching against track names.
///
/// Rules are ordered by priority — first match wins.
library;

import 'dart:convert';
import 'package:flutter/material.dart';

/// A single auto-color rule: regex pattern → color + optional icon
class AutoColorRule {
  /// Unique identifier
  final String id;

  /// Display name for the rule
  final String name;

  /// Regex pattern to match against track name (case-insensitive)
  final String pattern;

  /// Color to assign when matched
  final Color color;

  /// Optional icon to assign when matched
  final IconData? icon;

  /// Whether this rule is active
  final bool enabled;

  /// Sort priority (lower = checked first)
  final int priority;

  /// Optional icon code point for serialization
  final int? iconCodePoint;

  const AutoColorRule({
    required this.id,
    required this.name,
    required this.pattern,
    required this.color,
    this.icon,
    this.enabled = true,
    this.priority = 0,
    this.iconCodePoint,
  });

  /// Test if a track name matches this rule's pattern
  bool matches(String trackName) {
    if (!enabled || pattern.isEmpty) return false;
    try {
      return RegExp(pattern, caseSensitive: false).hasMatch(trackName);
    } catch (_) {
      return false;
    }
  }

  AutoColorRule copyWith({
    String? id,
    String? name,
    String? pattern,
    Color? color,
    IconData? icon,
    bool? enabled,
    int? priority,
    int? iconCodePoint,
  }) {
    return AutoColorRule(
      id: id ?? this.id,
      name: name ?? this.name,
      pattern: pattern ?? this.pattern,
      color: color ?? this.color,
      icon: icon ?? this.icon,
      enabled: enabled ?? this.enabled,
      priority: priority ?? this.priority,
      iconCodePoint: iconCodePoint ?? this.iconCodePoint,
    );
  }

  /// Serialize to JSON map
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'pattern': pattern,
    'color': color.value,
    'iconCodePoint': icon?.codePoint ?? iconCodePoint,
    'enabled': enabled,
    'priority': priority,
  };

  /// Deserialize from JSON map
  factory AutoColorRule.fromJson(Map<String, dynamic> json) {
    final iconCp = json['iconCodePoint'] as int?;
    return AutoColorRule(
      id: json['id'] as String,
      name: json['name'] as String,
      pattern: json['pattern'] as String,
      color: Color(json['color'] as int),
      icon: iconCp != null
          ? IconData(iconCp, fontFamily: 'MaterialIcons')
          : null,
      enabled: json['enabled'] as bool? ?? true,
      priority: json['priority'] as int? ?? 0,
      iconCodePoint: iconCp,
    );
  }
}

/// Result of applying auto-color rules to a track name
class AutoColorResult {
  /// Matched rule (null if no match)
  final AutoColorRule? rule;

  /// Color to apply (from rule or default)
  final Color color;

  /// Icon to apply (from rule, may be null)
  final IconData? icon;

  const AutoColorResult({
    this.rule,
    required this.color,
    this.icon,
  });

  bool get hasMatch => rule != null;
}

/// Serialization helpers for rule sets
class AutoColorRuleSet {
  AutoColorRuleSet._();

  /// Export rules to JSON string
  static String toJsonString(List<AutoColorRule> rules) {
    return const JsonEncoder.withIndent('  ').convert({
      'version': 1,
      'rules': rules.map((r) => r.toJson()).toList(),
    });
  }

  /// Import rules from JSON string
  static List<AutoColorRule> fromJsonString(String json) {
    final data = jsonDecode(json) as Map<String, dynamic>;
    final version = data['version'] as int? ?? 1;
    if (version != 1) return [];
    final rulesJson = data['rules'] as List<dynamic>;
    return rulesJson
        .map((r) => AutoColorRule.fromJson(r as Map<String, dynamic>))
        .toList();
  }
}
