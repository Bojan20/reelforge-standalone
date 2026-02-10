/// P3-05: Git Provider for Version Control State Management
///
/// ChangeNotifier wrapper around VersionControlService for reactive UI updates.
/// Provides state management for GitPanel integration in SlotLab Lower Zone.

import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/version_control_service.dart';

/// Git repository state for UI consumption
class GitRepoState {
  final bool isRepo;
  final bool isLoading;
  final String? error;
  final List<GitStatusEntry> stagedFiles;
  final List<GitStatusEntry> unstagedFiles;
  final List<GitCommit> history;
  final List<GitBranch> branches;
  final String? currentBranch;
  final GitRepoInfo? repoInfo;

  const GitRepoState({
    this.isRepo = false,
    this.isLoading = false,
    this.error,
    this.stagedFiles = const [],
    this.unstagedFiles = const [],
    this.history = const [],
    this.branches = const [],
    this.currentBranch,
    this.repoInfo,
  });

  GitRepoState copyWith({
    bool? isRepo,
    bool? isLoading,
    String? error,
    List<GitStatusEntry>? stagedFiles,
    List<GitStatusEntry>? unstagedFiles,
    List<GitCommit>? history,
    List<GitBranch>? branches,
    String? currentBranch,
    GitRepoInfo? repoInfo,
  }) {
    return GitRepoState(
      isRepo: isRepo ?? this.isRepo,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      stagedFiles: stagedFiles ?? this.stagedFiles,
      unstagedFiles: unstagedFiles ?? this.unstagedFiles,
      history: history ?? this.history,
      branches: branches ?? this.branches,
      currentBranch: currentBranch ?? this.currentBranch,
      repoInfo: repoInfo ?? this.repoInfo,
    );
  }

  /// Total number of changes (staged + unstaged)
  int get totalChanges => stagedFiles.length + unstagedFiles.length;

  /// Whether there are any staged changes ready to commit
  bool get hasStaged => stagedFiles.isNotEmpty;

  /// Whether there are any unstaged changes
  bool get hasUnstaged => unstagedFiles.isNotEmpty;

  /// Whether there are any changes at all
  bool get hasChanges => hasStaged || hasUnstaged;
}

/// Git Provider - ChangeNotifier for reactive git state management
class GitProvider extends ChangeNotifier {
  GitProvider._();
  static final instance = GitProvider._();

  final _service = VersionControlService.instance;
  StreamSubscription<List<GitStatusEntry>>? _statusSubscription;

  String? _repoPath;
  GitRepoState _state = const GitRepoState();

  /// Current repository path
  String? get repoPath => _repoPath;

  /// Current git state
  GitRepoState get state => _state;

  /// Whether provider is initialized with a repo
  bool get isInitialized => _repoPath != null;

  // ═══════════════════════════════════════════════════════════════════════════
  // INITIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Initialize provider with repository path
  Future<void> init(String repoPath) async {
    _repoPath = repoPath;
    _state = _state.copyWith(isLoading: true);
    notifyListeners();

    try {
      // Initialize service
      await _service.init(repoPath);

      // Subscribe to status updates
      _statusSubscription?.cancel();
      _statusSubscription = _service.statusStream.listen(_onStatusUpdate);

      // Load initial state
      await refresh();
    } catch (e) {
      _state = _state.copyWith(
        isLoading: false,
        error: 'Failed to initialize git: $e',
      );
      notifyListeners();
    }
  }

  /// Refresh all git state
  Future<void> refresh() async {
    if (_repoPath == null) return;

    _state = _state.copyWith(isLoading: true, error: null);
    notifyListeners();

    try {
      // Check if valid repo
      final repoInfo = await _service.getRepoInfo();
      if (!repoInfo.isRepo) {
        _state = _state.copyWith(
          isRepo: false,
          isLoading: false,
        );
        notifyListeners();
        return;
      }

      // Load all data in parallel
      final results = await Future.wait([
        _service.getStatus(),
        _service.getHistory(limit: 50),
        _service.getBranches(),
      ]);

      final status = results[0] as List<GitStatusEntry>;
      final history = results[1] as List<GitCommit>;
      final branches = results[2] as List<GitBranch>;

      // Separate staged and unstaged (use .staged field, not .isStaged)
      final staged = status.where((e) => e.staged).toList();
      final unstaged = status.where((e) => !e.staged).toList();

      // Find current branch
      final currentBranch = branches.firstWhere(
        (b) => b.isCurrent,
        orElse: () => const GitBranch(name: 'unknown', isCurrent: true),
      ).name;

      _state = GitRepoState(
        isRepo: true,
        isLoading: false,
        stagedFiles: staged,
        unstagedFiles: unstaged,
        history: history,
        branches: branches,
        currentBranch: currentBranch,
        repoInfo: repoInfo,
      );
      notifyListeners();
    } catch (e) {
      _state = _state.copyWith(
        isLoading: false,
        error: 'Failed to refresh: $e',
      );
      notifyListeners();
    }
  }

  void _onStatusUpdate(List<GitStatusEntry> status) {
    final staged = status.where((e) => e.staged).toList();
    final unstaged = status.where((e) => !e.staged).toList();

    _state = _state.copyWith(
      stagedFiles: staged,
      unstagedFiles: unstaged,
    );
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STAGING OPERATIONS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Stage specific files
  Future<bool> stageFiles(List<String> paths) async {
    try {
      await _service.stageFiles(paths);
      await _refreshStatus();
      return true;
    } catch (e) {
      _state = _state.copyWith(error: 'Failed to stage files: $e');
      notifyListeners();
      return false;
    }
  }

  /// Stage all changes
  Future<bool> stageAll() async {
    try {
      await _service.stageAll();
      await _refreshStatus();
      return true;
    } catch (e) {
      _state = _state.copyWith(error: 'Failed to stage all: $e');
      notifyListeners();
      return false;
    }
  }

  /// Unstage specific files
  Future<bool> unstageFiles(List<String> paths) async {
    try {
      await _service.unstageFiles(paths);
      await _refreshStatus();
      return true;
    } catch (e) {
      _state = _state.copyWith(error: 'Failed to unstage files: $e');
      notifyListeners();
      return false;
    }
  }

  /// Unstage all files
  Future<bool> unstageAll() async {
    try {
      await _service.unstageAll();
      await _refreshStatus();
      return true;
    } catch (e) {
      _state = _state.copyWith(error: 'Failed to unstage all: $e');
      notifyListeners();
      return false;
    }
  }

  /// Discard changes in specific files
  Future<bool> discardChanges(List<String> paths) async {
    try {
      await _service.discardChanges(paths);
      await _refreshStatus();
      return true;
    } catch (e) {
      _state = _state.copyWith(error: 'Failed to discard changes: $e');
      notifyListeners();
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // COMMIT OPERATIONS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create a commit with staged changes
  Future<bool> commit(String message) async {
    if (!_state.hasStaged) {
      _state = _state.copyWith(error: 'No staged changes to commit');
      notifyListeners();
      return false;
    }

    try {
      await _service.commit(message);
      await refresh();
      return true;
    } catch (e) {
      _state = _state.copyWith(error: 'Failed to commit: $e');
      notifyListeners();
      return false;
    }
  }

  /// Create a commit with all changes (stage all first)
  Future<bool> commitAll(String message) async {
    if (!_state.hasChanges) {
      _state = _state.copyWith(error: 'No changes to commit');
      notifyListeners();
      return false;
    }

    try {
      // Stage all first
      await _service.stageAll();
      await _service.commit(message);
      await refresh();
      return true;
    } catch (e) {
      _state = _state.copyWith(error: 'Failed to commit all: $e');
      notifyListeners();
      return false;
    }
  }

  /// Auto-commit with generated message (for project save)
  Future<bool> autoCommit({String? customMessage}) async {
    if (!_state.hasChanges) return true; // Nothing to commit

    final message = customMessage ?? _generateAutoCommitMessage();
    return commitAll(message);
  }

  String _generateAutoCommitMessage() {
    final now = DateTime.now();
    final timestamp = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final total = _state.totalChanges;
    final staged = _state.stagedFiles.length;
    final unstaged = _state.unstagedFiles.length;

    if (staged > 0 && unstaged > 0) {
      return 'Auto-save: $total changes ($staged staged, $unstaged unstaged) - $timestamp';
    } else if (staged > 0) {
      return 'Auto-save: $staged staged changes - $timestamp';
    } else {
      return 'Auto-save: $unstaged changes - $timestamp';
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BRANCH OPERATIONS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create a new branch
  Future<bool> createBranch(String name, {bool checkout = true}) async {
    try {
      await _service.createBranch(name, checkout: checkout);
      await _refreshBranches();
      return true;
    } catch (e) {
      _state = _state.copyWith(error: 'Failed to create branch: $e');
      notifyListeners();
      return false;
    }
  }

  /// Checkout/switch to a branch
  Future<bool> checkoutBranch(String name) async {
    try {
      await _service.switchBranch(name);
      await refresh();
      return true;
    } catch (e) {
      _state = _state.copyWith(error: 'Failed to checkout branch: $e');
      notifyListeners();
      return false;
    }
  }

  /// Delete a branch
  Future<bool> deleteBranch(String name, {bool force = false}) async {
    try {
      await _service.deleteBranch(name, force: force);
      await _refreshBranches();
      return true;
    } catch (e) {
      _state = _state.copyWith(error: 'Failed to delete branch: $e');
      notifyListeners();
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // REMOTE OPERATIONS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Push to remote
  Future<bool> push({String? remote, String? branch}) async {
    _state = _state.copyWith(isLoading: true);
    notifyListeners();

    try {
      await _service.push(remote: remote, branch: branch);
      _state = _state.copyWith(isLoading: false);
      notifyListeners();
      return true;
    } catch (e) {
      _state = _state.copyWith(
        isLoading: false,
        error: 'Failed to push: $e',
      );
      notifyListeners();
      return false;
    }
  }

  /// Pull from remote
  Future<bool> pull({String? remote, String? branch}) async {
    _state = _state.copyWith(isLoading: true);
    notifyListeners();

    try {
      await _service.pull(remote: remote, branch: branch);
      await refresh();
      return true;
    } catch (e) {
      _state = _state.copyWith(
        isLoading: false,
        error: 'Failed to pull: $e',
      );
      notifyListeners();
      return false;
    }
  }

  /// Fetch from remote
  Future<bool> fetch({String? remote}) async {
    try {
      await _service.fetch(remote: remote);
      await _refreshBranches();
      return true;
    } catch (e) {
      _state = _state.copyWith(error: 'Failed to fetch: $e');
      notifyListeners();
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STASH OPERATIONS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Stash changes
  Future<bool> stash({String? message}) async {
    try {
      await _service.stash(message: message);
      await _refreshStatus();
      return true;
    } catch (e) {
      _state = _state.copyWith(error: 'Failed to stash: $e');
      notifyListeners();
      return false;
    }
  }

  /// Pop stash
  Future<bool> stashPop() async {
    try {
      await _service.stashPop();
      await _refreshStatus();
      return true;
    } catch (e) {
      _state = _state.copyWith(error: 'Failed to pop stash: $e');
      notifyListeners();
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DIFF OPERATIONS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get diff for a specific file
  Future<GitFileDiff?> getDiff(String path, {bool staged = false}) async {
    try {
      return await _service.getDiff(path, staged: staged);
    } catch (e) {
      _state = _state.copyWith(error: 'Failed to get diff: $e');
      notifyListeners();
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // REPOSITORY INITIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Initialize a new git repository
  Future<bool> initRepo() async {
    if (_repoPath == null) return false;

    try {
      await _service.initRepo(_repoPath!);
      await refresh();
      return true;
    } catch (e) {
      _state = _state.copyWith(error: 'Failed to initialize repository: $e');
      notifyListeners();
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PRIVATE HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _refreshStatus() async {
    try {
      final status = await _service.getStatus();
      final staged = status.where((e) => e.staged).toList();
      final unstaged = status.where((e) => !e.staged).toList();

      _state = _state.copyWith(
        stagedFiles: staged,
        unstagedFiles: unstaged,
      );
      notifyListeners();
    } catch (e) { /* ignored */ }
  }

  Future<void> _refreshBranches() async {
    try {
      final branches = await _service.getBranches();
      final currentBranch = branches.firstWhere(
        (b) => b.isCurrent,
        orElse: () => const GitBranch(name: 'unknown', isCurrent: true),
      ).name;

      _state = _state.copyWith(
        branches: branches,
        currentBranch: currentBranch,
      );
      notifyListeners();
    } catch (e) { /* ignored */ }
  }

  /// Clear any error state
  void clearError() {
    if (_state.error != null) {
      _state = _state.copyWith(error: null);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    super.dispose();
  }
}
