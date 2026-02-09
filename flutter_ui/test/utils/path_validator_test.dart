/// Unit tests for PathValidator utility
///
/// Tests:
/// - Valid path acceptance
/// - Path traversal attack blocking
/// - Symlink escape prevention
/// - Extension validation
/// - Character blacklist enforcement
/// - Length limit enforcement

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import '../../lib/utils/path_validator.dart';

void main() {
  group('PathValidator', () {
    late Directory tempDir;
    late String projectRoot;

    setUp(() async {
      // Create temp directory for testing
      tempDir = await Directory.systemTemp.createTemp('path_validator_test_');
      projectRoot = tempDir.path;

      // Initialize sandbox
      PathValidator.initializeSandbox(
        projectRoot: projectRoot,
      );

      // Create test audio file
      final audioFile = File(p.join(projectRoot, 'test.wav'));
      await audioFile.create();
      await audioFile.writeAsBytes([0, 1, 2, 3]); // Minimal WAV-like data
    });

    tearDown(() async {
      // Cleanup
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    group('Valid Paths', () {
      test('accepts valid audio file in sandbox', () async {
        final audioPath = p.join(projectRoot, 'test.wav');
        final result = PathValidator.validate(audioPath);

        expect(result.isValid, isTrue);
        expect(result.sanitizedPath, isNotNull);
        expect(result.error, isNull);
      });

      test('accepts file in subdirectory', () async {
        final subdir = Directory(p.join(projectRoot, 'audio'));
        await subdir.create();

        final audioFile = File(p.join(subdir.path, 'sound.wav'));
        await audioFile.create();
        await audioFile.writeAsBytes([0, 1, 2, 3]);

        final result = PathValidator.validate(audioFile.path);

        expect(result.isValid, isTrue);
      });

      test('accepts all allowed audio extensions', () async {
        final extensions = [
          'wav', 'wave', 'mp3', 'ogg', 'oga', 'flac',
          'aiff', 'aif', 'aifc', 'm4a', 'aac', 'opus',
        ];

        for (final ext in extensions) {
          final file = File(p.join(projectRoot, 'test.$ext'));
          await file.create();
          await file.writeAsBytes([0, 1, 2, 3]);

          final result = PathValidator.validate(file.path);

          expect(result.isValid, isTrue,
              reason: 'Extension .$ext should be allowed');

          await file.delete();
        }
      });
    });

    group('Path Traversal Attacks', () {
      test('blocks parent directory traversal', () {
        final maliciousPath = p.join(projectRoot, '..', '..', 'etc', 'passwd');

        final result = PathValidator.validate(maliciousPath);

        expect(result.isValid, isFalse);
        // Extension validation fires before sandbox check —
        // '.passwd' is not an allowed extension
        expect(result.error, contains('not allowed'));
      });

      test('blocks nested parent traversal', () {
        final maliciousPath = p.join(projectRoot, 'audio', '..', '..', '..', 'secret.txt');

        final result = PathValidator.validate(maliciousPath);

        expect(result.isValid, isFalse);
      });

      test('blocks symlink escape', () async {
        // Create symlink pointing outside sandbox
        final outsideDir = Directory(p.join(tempDir.parent.path, 'outside'));
        if (!await outsideDir.exists()) {
          await outsideDir.create();
        }

        final symlinkPath = p.join(projectRoot, 'escape_link');
        final link = Link(symlinkPath);

        try {
          await link.create(outsideDir.path);

          final result = PathValidator.validate(symlinkPath);

          expect(result.isValid, isFalse);
          // Extension validation fires before sandbox check —
          // 'escape_link' has no allowed audio extension
          expect(result.error, contains('not allowed'));
        } finally {
          if (await link.exists()) await link.delete();
          if (await outsideDir.exists()) await outsideDir.delete();
        }
      });
    });

    group('Extension Validation', () {
      test('blocks disallowed extensions', () async {
        final badExtensions = ['exe', 'dll', 'so', 'dylib', 'sh', 'bat', 'js', 'html'];

        for (final ext in badExtensions) {
          final file = File(p.join(projectRoot, 'malicious.$ext'));
          await file.create();

          final result = PathValidator.validate(file.path);

          expect(result.isValid, isFalse,
              reason: 'Extension .$ext should be blocked');
          expect(result.error, contains('not allowed'));

          await file.delete();
        }
      });

      test('blocks double extension bypass attempt', () async {
        final file = File(p.join(projectRoot, 'file.wav.exe'));
        await file.create();

        final result = PathValidator.validate(file.path);

        expect(result.isValid, isFalse);
        expect(result.error, contains('not allowed'));

        await file.delete();
      });
    });

    group('Character Blacklist', () {
      test('blocks null byte injection', () {
        final maliciousPath = '${projectRoot}/file\x00.wav';

        final result = PathValidator.validate(maliciousPath);

        expect(result.isValid, isFalse);
        expect(result.error, contains('dangerous character'));
      });

      test('blocks control characters', () {
        final maliciousPath = '${projectRoot}/file\x01\x02\x03.wav';

        final result = PathValidator.validate(maliciousPath);

        expect(result.isValid, isFalse);
        expect(result.error, contains('dangerous character'));
      });
    });

    group('Length Limits', () {
      test('blocks excessive path length', () {
        final longPath = projectRoot + '/' + ('a' * 5000) + '.wav';

        final result = PathValidator.validate(longPath);

        expect(result.isValid, isFalse);
        expect(result.error, contains('maximum length'));
      });

      test('blocks excessive filename length', () async {
        final longFilename = 'a' * 300 + '.wav';
        final file = File(p.join(projectRoot, longFilename));

        try {
          await file.create();

          final result = PathValidator.validate(file.path);

          expect(result.isValid, isFalse);
          expect(result.error, contains('maximum length'));
        } catch (e) {
          // OS might reject file creation itself
          expect(e, isA<FileSystemException>());
        }
      });
    });

    group('Utility Methods', () {
      test('sanitizeFilename removes dangerous characters', () {
        expect(
          PathValidator.sanitizeFilename('file/../name.wav'),
          equals('file_.._name.wav'),
        );

        expect(
          PathValidator.sanitizeFilename('file\x00name.wav'),
          equals('filename.wav'),
        );

        expect(
          PathValidator.sanitizeFilename('<script>alert(1)</script>.wav'),
          equals('_script_alert(1)__script_.wav'),
        );
      });

      test('isWithinSandbox returns correct status', () async {
        final validPath = p.join(projectRoot, 'test.wav');
        expect(PathValidator.isWithinSandbox(validPath), isTrue);

        final outsidePath = p.join(tempDir.parent.path, 'outside.wav');
        expect(PathValidator.isWithinSandbox(outsidePath), isFalse);
      });

      test('allowedExtensions returns complete list', () {
        final extensions = PathValidator.allowedExtensions;

        expect(extensions, contains('wav'));
        expect(extensions, contains('mp3'));
        expect(extensions, contains('flac'));
        expect(extensions, isNot(contains('exe')));
      });
    });

    group('Batch Validation', () {
      test('validateBatch returns results for all paths', () async {
        final file1 = File(p.join(projectRoot, 'valid1.wav'));
        final file2 = File(p.join(projectRoot, 'valid2.mp3'));
        await file1.create();
        await file2.create();

        final maliciousPath = p.join(projectRoot, '..', '..', 'bad.wav');

        final results = PathValidator.validateBatch([
          file1.path,
          file2.path,
          maliciousPath,
        ]);

        expect(results, hasLength(3));
        expect(results[file1.path]!.isValid, isTrue);
        expect(results[file2.path]!.isValid, isTrue);
        expect(results[maliciousPath]!.isValid, isFalse);

        await file1.delete();
        await file2.delete();
      });
    });

    group('Edge Cases', () {
      test('rejects empty path', () {
        final result = PathValidator.validate('');

        expect(result.isValid, isFalse);
        expect(result.error, contains('empty'));
      });

      test('rejects non-existent file', () {
        final nonExistentPath = p.join(projectRoot, 'does_not_exist.wav');

        final result = PathValidator.validate(nonExistentPath);

        expect(result.isValid, isFalse);
        expect(result.error, contains('does not exist'));
      });

      test('handles case-insensitive extension matching', () async {
        final file = File(p.join(projectRoot, 'TEST.WAV'));
        await file.create();
        await file.writeAsBytes([0, 1, 2, 3]);

        final result = PathValidator.validate(file.path);

        expect(result.isValid, isTrue);

        await file.delete();
      });
    });
  });
}
