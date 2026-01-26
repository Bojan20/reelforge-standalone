/// Input Validator Tests (P0.4)
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/utils/input_validator.dart';

void main() {
  group('PathValidator', () {
    test('rejects path traversal', () {
      final error = PathValidator.validate('../../../etc/passwd');
      expect(error, isNotNull);
      expect(error, contains('traversal'));
    });

    test('rejects invalid extensions', () {
      final error = PathValidator.validate('/path/to/file.exe');
      expect(error, isNotNull);
      expect(error, contains('not supported'));
    });

    test('accepts valid audio files', () {
      final error = PathValidator.validate('/path/to/audio.wav');
      expect(error, isNull);
    });
  });

  group('InputSanitizer', () {
    test('validates alphanumeric names', () {
      expect(InputSanitizer.validateName('Track 1'), isNull);
      expect(InputSanitizer.validateName('My-Track_Name'), isNull);
    });

    test('rejects special characters', () {
      final error = InputSanitizer.validateName('<script>alert</script>');
      expect(error, isNotNull);
    });

    test('rejects empty names', () {
      final error = InputSanitizer.validateName('');
      expect(error, isNotNull);
      expect(error, contains('empty'));
    });

    test('sanitizes dangerous input', () {
      final result = InputSanitizer.sanitizeName('<Track> Name!');
      expect(result, 'Track Name');
    });
  });

  group('FFIBoundsChecker', () {
    test('validates track IDs', () {
      expect(FFIBoundsChecker.validateTrackId(0), true);
      expect(FFIBoundsChecker.validateTrackId(100), true);
      expect(FFIBoundsChecker.validateTrackId(-1), false);
      expect(FFIBoundsChecker.validateTrackId(2000), false);
    });

    test('validates volume range', () {
      expect(FFIBoundsChecker.validateVolume(1.0), true);
      expect(FFIBoundsChecker.validateVolume(-1.0), false);
      expect(FFIBoundsChecker.validateVolume(double.nan), false);
      expect(FFIBoundsChecker.validateVolume(double.infinity), false);
    });

    test('validates pan range', () {
      expect(FFIBoundsChecker.validatePan(0.0), true);
      expect(FFIBoundsChecker.validatePan(-1.0), true);
      expect(FFIBoundsChecker.validatePan(1.0), true);
      expect(FFIBoundsChecker.validatePan(-1.5), false);
      expect(FFIBoundsChecker.validatePan(1.5), false);
    });

    test('clamps volume to safe range', () {
      expect(FFIBoundsChecker.clampVolume(2.0), 2.0);
      expect(FFIBoundsChecker.clampVolume(5.0), 4.0);
      expect(FFIBoundsChecker.clampVolume(-1.0), 0.0);
      expect(FFIBoundsChecker.clampVolume(double.nan), 0.0);
    });
  });
}
