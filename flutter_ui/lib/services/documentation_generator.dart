/// Documentation Generator Service
///
/// Auto-generates documentation from code, comments, and metadata.
/// Supports multiple output formats: Markdown, HTML, JSON.
///
/// P3-10: Documentation Generator (~450 LOC)
library;

import 'dart:convert';
import 'dart:io';

/// Documentation format options
enum DocFormat {
  markdown,
  html,
  json,
}

/// Documentation entry type
enum DocEntryType {
  service,
  provider,
  widget,
  model,
  ffiFunction,
  rustCrate,
  constant,
  enum_,
}

/// Single documentation entry
class DocEntry {
  final String name;
  final DocEntryType type;
  final String description;
  final String? filePath;
  final int? lineNumber;
  final List<String> tags;
  final Map<String, String> parameters;
  final String? returnType;
  final List<String> examples;
  final DateTime? lastModified;

  const DocEntry({
    required this.name,
    required this.type,
    required this.description,
    this.filePath,
    this.lineNumber,
    this.tags = const [],
    this.parameters = const {},
    this.returnType,
    this.examples = const [],
    this.lastModified,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type.name,
        'description': description,
        if (filePath != null) 'filePath': filePath,
        if (lineNumber != null) 'lineNumber': lineNumber,
        if (tags.isNotEmpty) 'tags': tags,
        if (parameters.isNotEmpty) 'parameters': parameters,
        if (returnType != null) 'returnType': returnType,
        if (examples.isNotEmpty) 'examples': examples,
        if (lastModified != null) 'lastModified': lastModified!.toIso8601String(),
      };

  factory DocEntry.fromJson(Map<String, dynamic> json) => DocEntry(
        name: json['name'] as String,
        type: DocEntryType.values.firstWhere((e) => e.name == json['type']),
        description: json['description'] as String,
        filePath: json['filePath'] as String?,
        lineNumber: json['lineNumber'] as int?,
        tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? [],
        parameters: (json['parameters'] as Map<String, dynamic>?)?.cast<String, String>() ?? {},
        returnType: json['returnType'] as String?,
        examples: (json['examples'] as List<dynamic>?)?.cast<String>() ?? [],
        lastModified: json['lastModified'] != null
            ? DateTime.parse(json['lastModified'] as String)
            : null,
      );
}

/// Documentation section grouping
class DocSection {
  final String title;
  final String? description;
  final List<DocEntry> entries;
  final List<DocSection> subsections;

  const DocSection({
    required this.title,
    this.description,
    this.entries = const [],
    this.subsections = const [],
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        if (description != null) 'description': description,
        'entries': entries.map((e) => e.toJson()).toList(),
        if (subsections.isNotEmpty)
          'subsections': subsections.map((s) => s.toJson()).toList(),
      };
}

/// Generated documentation manifest
class DocManifest {
  final String projectName;
  final String version;
  final DateTime generatedAt;
  final List<DocSection> sections;
  final Map<String, int> stats;

  const DocManifest({
    required this.projectName,
    required this.version,
    required this.generatedAt,
    required this.sections,
    required this.stats,
  });

  Map<String, dynamic> toJson() => {
        'projectName': projectName,
        'version': version,
        'generatedAt': generatedAt.toIso8601String(),
        'sections': sections.map((s) => s.toJson()).toList(),
        'stats': stats,
      };
}

/// Documentation Generator Service
class DocumentationGenerator {
  DocumentationGenerator._();
  static final instance = DocumentationGenerator._();

  /// Generate documentation from source files
  Future<DocManifest> generate({
    required String projectPath,
    required String projectName,
    required String version,
    List<String> includePaths = const ['lib/', 'crates/'],
    List<String> excludePatterns = const ['.g.dart', '.freezed.dart', 'test/'],
  }) async {
    final entries = <DocEntry>[];
    final dir = Directory(projectPath);

    if (!await dir.exists()) {
      throw ArgumentError('Project path does not exist: $projectPath');
    }

    // Scan Dart files
    await _scanDartFiles(
      Directory('$projectPath/flutter_ui'),
      entries,
      includePaths,
      excludePatterns,
    );

    // Scan Rust crates
    await _scanRustCrates(
      Directory('$projectPath/crates'),
      entries,
    );

    // Organize into sections
    final sections = _organizeSections(entries);

    // Calculate stats
    final stats = _calculateStats(entries);

    return DocManifest(
      projectName: projectName,
      version: version,
      generatedAt: DateTime.now(),
      sections: sections,
      stats: stats,
    );
  }

  /// Scan Dart files for documentation
  Future<void> _scanDartFiles(
    Directory dir,
    List<DocEntry> entries,
    List<String> includePaths,
    List<String> excludePatterns,
  ) async {
    if (!await dir.exists()) return;

    await for (final entity in dir.list(recursive: true)) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('.dart')) continue;

      // Check exclude patterns
      final shouldExclude = excludePatterns.any((p) => entity.path.contains(p));
      if (shouldExclude) continue;

      try {
        final content = await entity.readAsString();
        final fileEntries = _parseDartFile(entity.path, content);
        entries.addAll(fileEntries);
      } catch (_) {
        // Skip files that can't be read
      }
    }
  }

  /// Parse a single Dart file
  List<DocEntry> _parseDartFile(String filePath, String content) {
    final entries = <DocEntry>[];
    final lines = content.split('\n');

    String? currentDoc;
    int? docStartLine;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();

      // Collect doc comments
      if (line.startsWith('///')) {
        currentDoc = '${currentDoc ?? ''}${line.substring(3).trim()} ';
        docStartLine ??= i + 1;
        continue;
      }

      // Check for class/service/provider
      if (currentDoc != null) {
        final entry = _parseDeclaration(line, currentDoc.trim(), filePath, docStartLine ?? i);
        if (entry != null) {
          entries.add(entry);
        }
        currentDoc = null;
        docStartLine = null;
      }
    }

    return entries;
  }

  /// Parse a declaration line
  DocEntry? _parseDeclaration(String line, String doc, String filePath, int lineNumber) {
    // Service class
    if (line.contains('class') && line.contains('Service')) {
      final match = RegExp(r'class\s+(\w+Service)').firstMatch(line);
      if (match != null) {
        return DocEntry(
          name: match.group(1)!,
          type: DocEntryType.service,
          description: doc,
          filePath: filePath,
          lineNumber: lineNumber,
          tags: ['service', 'singleton'],
        );
      }
    }

    // Provider class
    if (line.contains('class') && line.contains('Provider')) {
      final match = RegExp(r'class\s+(\w+Provider)').firstMatch(line);
      if (match != null) {
        return DocEntry(
          name: match.group(1)!,
          type: DocEntryType.provider,
          description: doc,
          filePath: filePath,
          lineNumber: lineNumber,
          tags: ['provider', 'state-management'],
        );
      }
    }

    // Widget class
    if (line.contains('class') && (line.contains('Widget') || line.contains('extends StatefulWidget') || line.contains('extends StatelessWidget'))) {
      final match = RegExp(r'class\s+(\w+)').firstMatch(line);
      if (match != null) {
        return DocEntry(
          name: match.group(1)!,
          type: DocEntryType.widget,
          description: doc,
          filePath: filePath,
          lineNumber: lineNumber,
          tags: ['widget', 'ui'],
        );
      }
    }

    // Model class
    if (line.contains('class') && !line.contains('abstract')) {
      final match = RegExp(r'class\s+(\w+)').firstMatch(line);
      if (match != null) {
        return DocEntry(
          name: match.group(1)!,
          type: DocEntryType.model,
          description: doc,
          filePath: filePath,
          lineNumber: lineNumber,
          tags: ['model'],
        );
      }
    }

    // Enum
    if (line.startsWith('enum ')) {
      final match = RegExp(r'enum\s+(\w+)').firstMatch(line);
      if (match != null) {
        return DocEntry(
          name: match.group(1)!,
          type: DocEntryType.enum_,
          description: doc,
          filePath: filePath,
          lineNumber: lineNumber,
          tags: ['enum'],
        );
      }
    }

    return null;
  }

  /// Scan Rust crates for documentation
  Future<void> _scanRustCrates(
    Directory cratesDir,
    List<DocEntry> entries,
  ) async {
    if (!await cratesDir.exists()) return;

    await for (final entity in cratesDir.list()) {
      if (entity is! Directory) continue;

      final crateName = entity.path.split('/').last;
      final cargoToml = File('${entity.path}/Cargo.toml');

      if (!await cargoToml.exists()) continue;

      String? description;
      try {
        final content = await cargoToml.readAsString();
        final descMatch = RegExp(r'description\s*=\s*"([^"]+)"').firstMatch(content);
        description = descMatch?.group(1);
      } catch (_) { /* ignored */ }

      entries.add(DocEntry(
        name: crateName,
        type: DocEntryType.rustCrate,
        description: description ?? 'Rust crate: $crateName',
        filePath: entity.path,
        tags: ['rust', 'crate'],
      ));

      // Scan FFI functions in lib.rs or ffi.rs
      await _scanRustFfi(entity, entries, crateName);
    }
  }

  /// Scan Rust FFI functions
  Future<void> _scanRustFfi(
    Directory crateDir,
    List<DocEntry> entries,
    String crateName,
  ) async {
    final ffiFile = File('${crateDir.path}/src/ffi.rs');
    final libFile = File('${crateDir.path}/src/lib.rs');

    for (final file in [ffiFile, libFile]) {
      if (!await file.exists()) continue;

      try {
        final content = await file.readAsString();
        final lines = content.split('\n');

        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];

          // Look for #[no_mangle] pub extern "C" fn
          if (line.contains('#[no_mangle]')) {
            // Next non-empty line should be the function
            for (var j = i + 1; j < lines.length && j < i + 5; j++) {
              final fnLine = lines[j];
              if (fnLine.contains('pub extern') || fnLine.contains('pub unsafe extern')) {
                final fnMatch = RegExp(r'fn\s+(\w+)').firstMatch(fnLine);
                if (fnMatch != null) {
                  entries.add(DocEntry(
                    name: fnMatch.group(1)!,
                    type: DocEntryType.ffiFunction,
                    description: 'FFI function in $crateName',
                    filePath: file.path,
                    lineNumber: j + 1,
                    tags: ['ffi', 'extern-c', crateName],
                  ));
                }
                break;
              }
            }
          }
        }
      } catch (_) { /* ignored */ }
    }
  }

  /// Organize entries into sections
  List<DocSection> _organizeSections(List<DocEntry> entries) {
    final sections = <DocSection>[];

    // Group by type
    final byType = <DocEntryType, List<DocEntry>>{};
    for (final entry in entries) {
      byType.putIfAbsent(entry.type, () => []).add(entry);
    }

    // Services section
    if (byType.containsKey(DocEntryType.service)) {
      sections.add(DocSection(
        title: 'Services',
        description: 'Singleton services providing core functionality',
        entries: byType[DocEntryType.service]!..sort((a, b) => a.name.compareTo(b.name)),
      ));
    }

    // Providers section
    if (byType.containsKey(DocEntryType.provider)) {
      sections.add(DocSection(
        title: 'Providers',
        description: 'State management providers using ChangeNotifier pattern',
        entries: byType[DocEntryType.provider]!..sort((a, b) => a.name.compareTo(b.name)),
      ));
    }

    // Widgets section
    if (byType.containsKey(DocEntryType.widget)) {
      sections.add(DocSection(
        title: 'Widgets',
        description: 'UI components and custom widgets',
        entries: byType[DocEntryType.widget]!..sort((a, b) => a.name.compareTo(b.name)),
      ));
    }

    // Models section
    if (byType.containsKey(DocEntryType.model)) {
      sections.add(DocSection(
        title: 'Models',
        description: 'Data models and DTOs',
        entries: byType[DocEntryType.model]!..sort((a, b) => a.name.compareTo(b.name)),
      ));
    }

    // Rust crates section
    if (byType.containsKey(DocEntryType.rustCrate)) {
      sections.add(DocSection(
        title: 'Rust Crates',
        description: 'Native Rust crates providing core engine functionality',
        entries: byType[DocEntryType.rustCrate]!..sort((a, b) => a.name.compareTo(b.name)),
      ));
    }

    // FFI functions section
    if (byType.containsKey(DocEntryType.ffiFunction)) {
      sections.add(DocSection(
        title: 'FFI Functions',
        description: 'C-compatible functions exposed to Dart via dart:ffi',
        entries: byType[DocEntryType.ffiFunction]!..sort((a, b) => a.name.compareTo(b.name)),
      ));
    }

    // Enums section
    if (byType.containsKey(DocEntryType.enum_)) {
      sections.add(DocSection(
        title: 'Enums',
        description: 'Enumeration types',
        entries: byType[DocEntryType.enum_]!..sort((a, b) => a.name.compareTo(b.name)),
      ));
    }

    return sections;
  }

  /// Calculate documentation stats
  Map<String, int> _calculateStats(List<DocEntry> entries) {
    final stats = <String, int>{
      'total': entries.length,
    };

    for (final type in DocEntryType.values) {
      final count = entries.where((e) => e.type == type).length;
      if (count > 0) {
        stats[type.name] = count;
      }
    }

    return stats;
  }

  /// Export to Markdown format
  String exportMarkdown(DocManifest manifest) {
    final buffer = StringBuffer();

    buffer.writeln('# ${manifest.projectName} Documentation');
    buffer.writeln();
    buffer.writeln('**Version:** ${manifest.version}');
    buffer.writeln('**Generated:** ${manifest.generatedAt.toIso8601String()}');
    buffer.writeln();

    // Stats
    buffer.writeln('## Statistics');
    buffer.writeln();
    buffer.writeln('| Category | Count |');
    buffer.writeln('|----------|-------|');
    for (final entry in manifest.stats.entries) {
      buffer.writeln('| ${entry.key} | ${entry.value} |');
    }
    buffer.writeln();

    // Table of Contents
    buffer.writeln('## Table of Contents');
    buffer.writeln();
    for (final section in manifest.sections) {
      buffer.writeln('- [${section.title}](#${_slugify(section.title)})');
    }
    buffer.writeln();

    // Sections
    for (final section in manifest.sections) {
      buffer.writeln('## ${section.title}');
      buffer.writeln();
      if (section.description != null) {
        buffer.writeln(section.description);
        buffer.writeln();
      }

      for (final entry in section.entries) {
        buffer.writeln('### ${entry.name}');
        buffer.writeln();
        buffer.writeln(entry.description);
        buffer.writeln();

        if (entry.filePath != null) {
          buffer.writeln('**File:** `${entry.filePath}`');
          if (entry.lineNumber != null) {
            buffer.writeln(' (line ${entry.lineNumber})');
          }
          buffer.writeln();
        }

        if (entry.tags.isNotEmpty) {
          buffer.writeln('**Tags:** ${entry.tags.map((t) => '`$t`').join(', ')}');
          buffer.writeln();
        }

        if (entry.parameters.isNotEmpty) {
          buffer.writeln('**Parameters:**');
          for (final param in entry.parameters.entries) {
            buffer.writeln('- `${param.key}`: ${param.value}');
          }
          buffer.writeln();
        }

        if (entry.returnType != null) {
          buffer.writeln('**Returns:** `${entry.returnType}`');
          buffer.writeln();
        }

        buffer.writeln('---');
        buffer.writeln();
      }
    }

    return buffer.toString();
  }

  /// Export to HTML format
  String exportHtml(DocManifest manifest) {
    final buffer = StringBuffer();

    buffer.writeln('<!DOCTYPE html>');
    buffer.writeln('<html lang="en">');
    buffer.writeln('<head>');
    buffer.writeln('  <meta charset="UTF-8">');
    buffer.writeln('  <meta name="viewport" content="width=device-width, initial-scale=1.0">');
    buffer.writeln('  <title>${manifest.projectName} Documentation</title>');
    buffer.writeln('  <style>');
    buffer.writeln(_getHtmlStyles());
    buffer.writeln('  </style>');
    buffer.writeln('</head>');
    buffer.writeln('<body>');
    buffer.writeln('  <div class="container">');
    buffer.writeln('    <h1>${manifest.projectName} Documentation</h1>');
    buffer.writeln('    <p class="meta">Version: ${manifest.version} | Generated: ${manifest.generatedAt.toIso8601String()}</p>');

    // Stats
    buffer.writeln('    <section class="stats">');
    buffer.writeln('      <h2>Statistics</h2>');
    buffer.writeln('      <div class="stats-grid">');
    for (final entry in manifest.stats.entries) {
      buffer.writeln('        <div class="stat-card">');
      buffer.writeln('          <span class="stat-value">${entry.value}</span>');
      buffer.writeln('          <span class="stat-label">${entry.key}</span>');
      buffer.writeln('        </div>');
    }
    buffer.writeln('      </div>');
    buffer.writeln('    </section>');

    // Sections
    for (final section in manifest.sections) {
      buffer.writeln('    <section id="${_slugify(section.title)}">');
      buffer.writeln('      <h2>${section.title}</h2>');
      if (section.description != null) {
        buffer.writeln('      <p class="section-desc">${section.description}</p>');
      }

      for (final entry in section.entries) {
        buffer.writeln('      <article class="entry">');
        buffer.writeln('        <h3>${entry.name}</h3>');
        buffer.writeln('        <p>${entry.description}</p>');

        if (entry.filePath != null) {
          buffer.writeln('        <p class="file-path"><code>${entry.filePath}</code>');
          if (entry.lineNumber != null) {
            buffer.writeln(' (line ${entry.lineNumber})');
          }
          buffer.writeln('</p>');
        }

        if (entry.tags.isNotEmpty) {
          buffer.writeln('        <div class="tags">');
          for (final tag in entry.tags) {
            buffer.writeln('          <span class="tag">$tag</span>');
          }
          buffer.writeln('        </div>');
        }

        buffer.writeln('      </article>');
      }

      buffer.writeln('    </section>');
    }

    buffer.writeln('  </div>');
    buffer.writeln('</body>');
    buffer.writeln('</html>');

    return buffer.toString();
  }

  /// Export to JSON format
  String exportJson(DocManifest manifest) {
    return const JsonEncoder.withIndent('  ').convert(manifest.toJson());
  }

  String _slugify(String text) {
    return text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
  }

  String _getHtmlStyles() {
    return '''
:root {
  --bg: #0a0a0c;
  --surface: #1a1a20;
  --text: #e0e0e0;
  --accent: #4a9eff;
  --accent2: #40ff90;
}
* { box-sizing: border-box; margin: 0; padding: 0; }
body {
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
  background: var(--bg);
  color: var(--text);
  line-height: 1.6;
}
.container { max-width: 1200px; margin: 0 auto; padding: 2rem; }
h1 { color: var(--accent); margin-bottom: 0.5rem; }
h2 { color: var(--accent2); margin: 2rem 0 1rem; border-bottom: 1px solid var(--surface); padding-bottom: 0.5rem; }
h3 { color: var(--text); margin: 1rem 0 0.5rem; }
.meta { color: #888; margin-bottom: 2rem; }
.stats-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(150px, 1fr)); gap: 1rem; margin: 1rem 0; }
.stat-card { background: var(--surface); padding: 1rem; border-radius: 8px; text-align: center; }
.stat-value { display: block; font-size: 2rem; font-weight: bold; color: var(--accent); }
.stat-label { display: block; font-size: 0.875rem; color: #888; text-transform: capitalize; }
section { margin-bottom: 3rem; }
.section-desc { color: #888; margin-bottom: 1rem; }
.entry { background: var(--surface); padding: 1.5rem; border-radius: 8px; margin-bottom: 1rem; }
.file-path { font-size: 0.875rem; color: #888; margin: 0.5rem 0; }
.tags { display: flex; gap: 0.5rem; flex-wrap: wrap; margin-top: 0.5rem; }
.tag { background: var(--accent); color: var(--bg); padding: 0.25rem 0.5rem; border-radius: 4px; font-size: 0.75rem; }
code { background: var(--bg); padding: 0.125rem 0.375rem; border-radius: 4px; font-family: 'SF Mono', Consolas, monospace; }
''';
  }
}
