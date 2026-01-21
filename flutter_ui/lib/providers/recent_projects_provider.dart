// Recent Projects Provider
//
// Manages recently opened projects list with:
// - FFI integration with Rust backend
// - Persistent storage across sessions
// - Project path validation

import 'dart:io';
import 'package:flutter/foundation.dart';
import '../src/rust/native_ffi.dart';

/// Recent project entry
class RecentProject {
  final String path;
  final String name;
  final DateTime? lastOpened;

  const RecentProject({
    required this.path,
    required this.name,
    this.lastOpened,
  });

  /// Create from file path
  factory RecentProject.fromPath(String path) {
    final file = File(path);
    final name = file.uri.pathSegments.lastOrNull ?? path;
    final baseName = name.replaceAll(RegExp(r'\.(rfp|json)$'), '');
    return RecentProject(
      path: path,
      name: baseName,
      lastOpened: file.existsSync() ? file.lastModifiedSync() : null,
    );
  }

  /// Check if file exists
  bool get exists => File(path).existsSync();
}

// ============ Provider ============

class RecentProjectsProvider extends ChangeNotifier {
  List<RecentProject> _projects = [];

  List<RecentProject> get projects => _projects;
  int get count => _projects.length;
  bool get isEmpty => _projects.isEmpty;
  bool get isNotEmpty => _projects.isNotEmpty;

  /// Initialize and load recent projects from Rust
  void initialize() {
    _loadFromRust();
  }

  /// Load recent projects from Rust backend
  void _loadFromRust() {
    final ffi = NativeFFI.instance;
    if (!ffi.isLoaded) return;

    final paths = ffi.recentProjectsGetAll();
    _projects = paths
        .map((path) => RecentProject.fromPath(path))
        .where((p) => p.exists) // Filter out deleted projects
        .toList();

    notifyListeners();
  }

  /// Add project to recent list
  void addProject(String path) {
    final ffi = NativeFFI.instance;
    if (ffi.isLoaded) {
      ffi.recentProjectsAdd(path);
    }

    // Update local list
    _projects.removeWhere((p) => p.path == path);
    _projects.insert(0, RecentProject.fromPath(path));

    // Keep max 20
    if (_projects.length > 20) {
      _projects = _projects.take(20).toList();
    }

    notifyListeners();
  }

  /// Remove project from recent list
  void removeProject(String path) {
    final ffi = NativeFFI.instance;
    if (ffi.isLoaded) {
      ffi.recentProjectsRemove(path);
    }

    _projects.removeWhere((p) => p.path == path);
    notifyListeners();
  }

  /// Clear all recent projects
  void clearAll() {
    final ffi = NativeFFI.instance;
    if (ffi.isLoaded) {
      ffi.recentProjectsClear();
    }

    _projects.clear();
    notifyListeners();
  }

  /// Refresh list (remove non-existent files)
  void refresh() {
    _projects = _projects.where((p) => p.exists).toList();
    notifyListeners();
  }

  /// Get project by index
  RecentProject? getAt(int index) {
    if (index < 0 || index >= _projects.length) return null;
    return _projects[index];
  }

}
