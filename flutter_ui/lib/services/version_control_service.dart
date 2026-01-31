/// Version Control Service
///
/// Git integration for project version control.
/// Supports commit, branch, diff, and history operations.
///
/// P3-05: Version Control Integration (~550 LOC)
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Git commit information
class GitCommit {
  final String hash;
  final String shortHash;
  final String message;
  final String author;
  final String email;
  final DateTime date;
  final List<String> changedFiles;

  const GitCommit({
    required this.hash,
    required this.shortHash,
    required this.message,
    required this.author,
    required this.email,
    required this.date,
    this.changedFiles = const [],
  });

  factory GitCommit.fromLog(String logEntry) {
    final parts = logEntry.split('|||');
    if (parts.length < 5) {
      throw FormatException('Invalid git log format: $logEntry');
    }
    return GitCommit(
      hash: parts[0],
      shortHash: parts[0].substring(0, 7),
      message: parts[1],
      author: parts[2],
      email: parts[3],
      date: DateTime.tryParse(parts[4]) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'hash': hash,
        'shortHash': shortHash,
        'message': message,
        'author': author,
        'email': email,
        'date': date.toIso8601String(),
        'changedFiles': changedFiles,
      };
}

/// Git branch information
class GitBranch {
  final String name;
  final bool isCurrent;
  final bool isRemote;
  final String? upstream;
  final int? ahead;
  final int? behind;

  const GitBranch({
    required this.name,
    this.isCurrent = false,
    this.isRemote = false,
    this.upstream,
    this.ahead,
    this.behind,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'isCurrent': isCurrent,
        'isRemote': isRemote,
        if (upstream != null) 'upstream': upstream,
        if (ahead != null) 'ahead': ahead,
        if (behind != null) 'behind': behind,
      };
}

/// Git file status
enum GitFileStatus {
  modified,
  added,
  deleted,
  renamed,
  copied,
  untracked,
  ignored,
  conflicted,
}

/// Git status entry
class GitStatusEntry {
  final String path;
  final GitFileStatus status;
  final bool staged;
  final String? oldPath; // For renamed files

  const GitStatusEntry({
    required this.path,
    required this.status,
    this.staged = false,
    this.oldPath,
  });

  Map<String, dynamic> toJson() => {
        'path': path,
        'status': status.name,
        'staged': staged,
        if (oldPath != null) 'oldPath': oldPath,
      };
}

/// Git diff hunk
class GitDiffHunk {
  final int oldStart;
  final int oldCount;
  final int newStart;
  final int newCount;
  final List<String> lines;

  const GitDiffHunk({
    required this.oldStart,
    required this.oldCount,
    required this.newStart,
    required this.newCount,
    required this.lines,
  });
}

/// Git diff for a file
class GitFileDiff {
  final String path;
  final String? oldPath;
  final bool isBinary;
  final List<GitDiffHunk> hunks;

  const GitFileDiff({
    required this.path,
    this.oldPath,
    this.isBinary = false,
    this.hunks = const [],
  });
}

/// Repository information
class GitRepoInfo {
  final String path;
  final bool isRepo;
  final String? currentBranch;
  final String? remoteUrl;
  final int? uncommittedChanges;
  final int? untrackedFiles;

  const GitRepoInfo({
    required this.path,
    required this.isRepo,
    this.currentBranch,
    this.remoteUrl,
    this.uncommittedChanges,
    this.untrackedFiles,
  });

  Map<String, dynamic> toJson() => {
        'path': path,
        'isRepo': isRepo,
        if (currentBranch != null) 'currentBranch': currentBranch,
        if (remoteUrl != null) 'remoteUrl': remoteUrl,
        if (uncommittedChanges != null) 'uncommittedChanges': uncommittedChanges,
        if (untrackedFiles != null) 'untrackedFiles': untrackedFiles,
      };
}

/// Version Control Service
class VersionControlService {
  VersionControlService._();
  static final instance = VersionControlService._();

  String? _repoPath;
  final _statusController = StreamController<List<GitStatusEntry>>.broadcast();

  /// Status stream for real-time updates
  Stream<List<GitStatusEntry>> get statusStream => _statusController.stream;

  /// Initialize with repository path
  Future<GitRepoInfo> init(String path) async {
    _repoPath = path;
    return getRepoInfo();
  }

  /// Check if git is available
  Future<bool> isGitAvailable() async {
    try {
      final result = await Process.run('git', ['--version']);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Get repository information
  Future<GitRepoInfo> getRepoInfo() async {
    if (_repoPath == null) {
      return const GitRepoInfo(path: '', isRepo: false);
    }

    // Check if it's a git repo
    final gitDir = Directory('$_repoPath/.git');
    if (!await gitDir.exists()) {
      return GitRepoInfo(path: _repoPath!, isRepo: false);
    }

    // Get current branch
    String? branch;
    try {
      final branchResult = await _runGit(['rev-parse', '--abbrev-ref', 'HEAD']);
      branch = branchResult.trim();
    } catch (_) {}

    // Get remote URL
    String? remote;
    try {
      final remoteResult = await _runGit(['remote', 'get-url', 'origin']);
      remote = remoteResult.trim();
    } catch (_) {}

    // Get status counts
    int uncommitted = 0;
    int untracked = 0;
    try {
      final status = await getStatus();
      uncommitted = status.where((s) => s.status != GitFileStatus.untracked).length;
      untracked = status.where((s) => s.status == GitFileStatus.untracked).length;
    } catch (_) {}

    return GitRepoInfo(
      path: _repoPath!,
      isRepo: true,
      currentBranch: branch,
      remoteUrl: remote,
      uncommittedChanges: uncommitted,
      untrackedFiles: untracked,
    );
  }

  /// Get current status
  Future<List<GitStatusEntry>> getStatus() async {
    final output = await _runGit(['status', '--porcelain=v1']);
    final entries = <GitStatusEntry>[];

    for (final line in output.split('\n')) {
      if (line.isEmpty) continue;

      final staged = line[0] != ' ' && line[0] != '?';
      final statusChar = staged ? line[0] : line[1];
      final path = line.substring(3);

      entries.add(GitStatusEntry(
        path: path,
        status: _parseStatusChar(statusChar),
        staged: staged,
      ));
    }

    _statusController.add(entries);
    return entries;
  }

  GitFileStatus _parseStatusChar(String char) {
    switch (char) {
      case 'M':
        return GitFileStatus.modified;
      case 'A':
        return GitFileStatus.added;
      case 'D':
        return GitFileStatus.deleted;
      case 'R':
        return GitFileStatus.renamed;
      case 'C':
        return GitFileStatus.copied;
      case '?':
        return GitFileStatus.untracked;
      case '!':
        return GitFileStatus.ignored;
      case 'U':
        return GitFileStatus.conflicted;
      default:
        return GitFileStatus.modified;
    }
  }

  /// Stage files
  Future<void> stageFiles(List<String> paths) async {
    await _runGit(['add', ...paths]);
    await getStatus(); // Update status
  }

  /// Stage all files
  Future<void> stageAll() async {
    await _runGit(['add', '-A']);
    await getStatus();
  }

  /// Unstage files
  Future<void> unstageFiles(List<String> paths) async {
    await _runGit(['reset', 'HEAD', '--', ...paths]);
    await getStatus();
  }

  /// Unstage all files
  Future<void> unstageAll() async {
    await _runGit(['reset', 'HEAD']);
    await getStatus();
  }

  /// Discard changes in files
  Future<void> discardChanges(List<String> paths) async {
    await _runGit(['checkout', '--', ...paths]);
    await getStatus();
  }

  /// Commit staged changes
  Future<GitCommit> commit(String message) async {
    await _runGit(['commit', '-m', message]);

    // Get the commit we just made
    final logOutput = await _runGit([
      'log',
      '-1',
      '--format=%H|||%s|||%an|||%ae|||%aI',
    ]);

    return GitCommit.fromLog(logOutput.trim());
  }

  /// Get commit history
  Future<List<GitCommit>> getHistory({
    int limit = 50,
    String? branch,
    String? path,
  }) async {
    final args = [
      'log',
      '--format=%H|||%s|||%an|||%ae|||%aI',
      '-n',
      limit.toString(),
    ];

    if (branch != null) args.add(branch);
    if (path != null) args.addAll(['--', path]);

    final output = await _runGit(args);
    final commits = <GitCommit>[];

    for (final line in output.split('\n')) {
      if (line.isEmpty) continue;
      try {
        commits.add(GitCommit.fromLog(line));
      } catch (_) {}
    }

    return commits;
  }

  /// Get branches
  Future<List<GitBranch>> getBranches({bool includeRemote = false}) async {
    final args = ['branch', '-vv'];
    if (includeRemote) args.add('-a');

    final output = await _runGit(args);
    final branches = <GitBranch>[];

    for (final line in output.split('\n')) {
      if (line.isEmpty) continue;

      final isCurrent = line.startsWith('*');
      final parts = line.substring(2).trim().split(RegExp(r'\s+'));
      if (parts.isEmpty) continue;

      var name = parts[0];
      final isRemote = name.startsWith('remotes/');
      if (isRemote) {
        name = name.replaceFirst('remotes/', '');
      }

      branches.add(GitBranch(
        name: name,
        isCurrent: isCurrent,
        isRemote: isRemote,
      ));
    }

    return branches;
  }

  /// Create a new branch
  Future<void> createBranch(String name, {bool checkout = true}) async {
    if (checkout) {
      await _runGit(['checkout', '-b', name]);
    } else {
      await _runGit(['branch', name]);
    }
  }

  /// Switch to branch
  Future<void> switchBranch(String name) async {
    await _runGit(['checkout', name]);
    await getStatus();
  }

  /// Delete branch
  Future<void> deleteBranch(String name, {bool force = false}) async {
    await _runGit(['branch', force ? '-D' : '-d', name]);
  }

  /// Get diff for a file
  Future<GitFileDiff> getDiff(String path, {bool staged = false}) async {
    final args = ['diff'];
    if (staged) args.add('--cached');
    args.addAll(['--', path]);

    final output = await _runGit(args);
    return _parseDiff(path, output);
  }

  /// Get diff for all changes
  Future<List<GitFileDiff>> getAllDiffs({bool staged = false}) async {
    final args = ['diff', '--name-only'];
    if (staged) args.add('--cached');

    final output = await _runGit(args);
    final diffs = <GitFileDiff>[];

    for (final path in output.split('\n')) {
      if (path.isEmpty) continue;
      diffs.add(await getDiff(path, staged: staged));
    }

    return diffs;
  }

  GitFileDiff _parseDiff(String path, String output) {
    if (output.isEmpty) {
      return GitFileDiff(path: path);
    }

    // Check for binary
    if (output.contains('Binary files')) {
      return GitFileDiff(path: path, isBinary: true);
    }

    final hunks = <GitDiffHunk>[];
    final lines = output.split('\n');
    List<String>? currentHunkLines;
    int? oldStart, oldCount, newStart, newCount;

    for (final line in lines) {
      if (line.startsWith('@@')) {
        // Save previous hunk
        if (currentHunkLines != null) {
          hunks.add(GitDiffHunk(
            oldStart: oldStart!,
            oldCount: oldCount!,
            newStart: newStart!,
            newCount: newCount!,
            lines: currentHunkLines,
          ));
        }

        // Parse hunk header: @@ -1,5 +1,6 @@
        final match = RegExp(r'@@ -(\d+),?(\d*) \+(\d+),?(\d*) @@').firstMatch(line);
        if (match != null) {
          oldStart = int.parse(match.group(1)!);
          oldCount = int.tryParse(match.group(2) ?? '1') ?? 1;
          newStart = int.parse(match.group(3)!);
          newCount = int.tryParse(match.group(4) ?? '1') ?? 1;
          currentHunkLines = [];
        }
      } else if (currentHunkLines != null) {
        currentHunkLines.add(line);
      }
    }

    // Save last hunk
    if (currentHunkLines != null && currentHunkLines.isNotEmpty) {
      hunks.add(GitDiffHunk(
        oldStart: oldStart!,
        oldCount: oldCount!,
        newStart: newStart!,
        newCount: newCount!,
        lines: currentHunkLines,
      ));
    }

    return GitFileDiff(path: path, hunks: hunks);
  }

  /// Pull from remote
  Future<String> pull({String? remote, String? branch}) async {
    final args = ['pull'];
    if (remote != null) args.add(remote);
    if (branch != null) args.add(branch);

    return _runGit(args);
  }

  /// Push to remote
  Future<String> push({
    String? remote,
    String? branch,
    bool setUpstream = false,
  }) async {
    final args = ['push'];
    if (setUpstream) args.add('-u');
    if (remote != null) args.add(remote);
    if (branch != null) args.add(branch);

    return _runGit(args);
  }

  /// Fetch from remote
  Future<String> fetch({String? remote, bool prune = false}) async {
    final args = ['fetch'];
    if (prune) args.add('--prune');
    if (remote != null) args.add(remote);

    return _runGit(args);
  }

  /// Stash changes
  Future<void> stash({String? message}) async {
    final args = ['stash', 'push'];
    if (message != null) args.addAll(['-m', message]);

    await _runGit(args);
    await getStatus();
  }

  /// Pop stash
  Future<void> stashPop({int index = 0}) async {
    await _runGit(['stash', 'pop', 'stash@{$index}']);
    await getStatus();
  }

  /// List stashes
  Future<List<String>> listStashes() async {
    final output = await _runGit(['stash', 'list']);
    return output.split('\n').where((l) => l.isNotEmpty).toList();
  }

  /// Initialize a new repository
  Future<void> initRepo(String path) async {
    _repoPath = path;
    await _runGit(['init']);
  }

  /// Clone a repository
  Future<void> clone(String url, String path) async {
    await Process.run('git', ['clone', url, path]);
    _repoPath = path;
  }

  /// Get file content at specific commit
  Future<String> getFileAtCommit(String path, String commit) async {
    return _runGit(['show', '$commit:$path']);
  }

  /// Get blame for a file
  Future<List<Map<String, dynamic>>> getBlame(String path) async {
    final output = await _runGit([
      'blame',
      '--line-porcelain',
      path,
    ]);

    final blameLines = <Map<String, dynamic>>[];
    final lines = output.split('\n');
    Map<String, dynamic>? current;

    for (final line in lines) {
      if (line.startsWith('\t')) {
        // Content line
        if (current != null) {
          current['content'] = line.substring(1);
          blameLines.add(current);
          current = null;
        }
      } else if (RegExp(r'^[0-9a-f]{40}').hasMatch(line)) {
        // Commit hash line
        final parts = line.split(' ');
        current = {
          'hash': parts[0],
          'originalLine': int.tryParse(parts[1]) ?? 0,
          'finalLine': int.tryParse(parts[2]) ?? 0,
        };
      } else if (current != null) {
        // Metadata line
        final idx = line.indexOf(' ');
        if (idx > 0) {
          final key = line.substring(0, idx);
          final value = line.substring(idx + 1);
          current[key] = value;
        }
      }
    }

    return blameLines;
  }

  /// Run git command
  Future<String> _runGit(List<String> args) async {
    final result = await Process.run(
      'git',
      args,
      workingDirectory: _repoPath,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );

    if (result.exitCode != 0) {
      throw Exception('Git error: ${result.stderr}');
    }

    return result.stdout as String;
  }

  /// Dispose
  void dispose() {
    _statusController.close();
  }
}
