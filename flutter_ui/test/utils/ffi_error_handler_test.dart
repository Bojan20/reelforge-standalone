/// Unit tests for FFIErrorHandler utility
///
/// Tests:
/// - Error parsing from JSON
/// - Error category mapping
/// - Error code extraction
/// - Recoverable error detection
/// - Display message formatting
/// - Exception throwing

import 'package:flutter_test/flutter_test.dart';
import '../../lib/utils/ffi_error_handler.dart';

void main() {
  group('FFIErrorCategory', () {
    test('fromValue maps values correctly', () {
      expect(FFIErrorCategory.fromValue(1), equals(FFIErrorCategory.invalidInput));
      expect(FFIErrorCategory.fromValue(2), equals(FFIErrorCategory.outOfBounds));
      expect(FFIErrorCategory.fromValue(3), equals(FFIErrorCategory.invalidState));
      expect(FFIErrorCategory.fromValue(255), equals(FFIErrorCategory.unknown));
    });

    test('fromValue handles invalid value', () {
      expect(FFIErrorCategory.fromValue(999), equals(FFIErrorCategory.unknown));
    });

    test('displayName returns readable names', () {
      expect(FFIErrorCategory.invalidInput.displayName, equals('Invalid Input'));
      expect(FFIErrorCategory.outOfBounds.displayName, equals('Out of Bounds'));
      expect(FFIErrorCategory.notFound.displayName, equals('Not Found'));
    });
  });

  group('FFIError', () {
    test('creates error with basic fields', () {
      final error = FFIError(
        category: FFIErrorCategory.invalidInput,
        code: 100,
        message: 'Test error',
      );

      expect(error.category, equals(FFIErrorCategory.invalidInput));
      expect(error.code, equals(100));
      expect(error.message, equals('Test error'));
      expect(error.context, isNull);
      expect(error.suggestion, isNull);
    });

    test('creates error with context and suggestion', () {
      final error = FFIError(
        category: FFIErrorCategory.outOfBounds,
        code: 200,
        message: 'Index out of bounds',
        context: 'my_function',
        suggestion: 'Use valid index (0-9)',
      );

      expect(error.context, equals('my_function'));
      expect(error.suggestion, equals('Use valid index (0-9)'));
    });

    test('fromJson parses valid JSON', () {
      final jsonString = '''
      {
        "category": 1,
        "code": 101,
        "message": "Invalid parameter",
        "context": "test_function",
        "suggestion": "Try passing valid values"
      }
      ''';

      final error = FFIError.fromJson(jsonString);

      expect(error.category, equals(FFIErrorCategory.invalidInput));
      expect(error.code, equals(101));
      expect(error.message, equals('Invalid parameter'));
      expect(error.context, equals('test_function'));
      expect(error.suggestion, equals('Try passing valid values'));
    });

    test('fromJson handles malformed JSON', () {
      final malformedJson = '{invalid json}';

      final error = FFIError.fromJson(malformedJson);

      expect(error.category, equals(FFIErrorCategory.unknown));
      expect(error.message, contains('Failed to parse'));
    });

    test('fromFullCode extracts category and code', () {
      final fullCode = (1 << 16) | 256; // Category=1, Code=256

      final error = FFIError.fromFullCode(fullCode, 'Test message');

      expect(error.category, equals(FFIErrorCategory.invalidInput));
      expect(error.code, equals(256));
      expect(error.message, equals('Test message'));
    });

    test('fullCode combines category and code', () {
      final error = FFIError(
        category: FFIErrorCategory.outOfBounds,
        code: 512,
        message: 'Test',
      );

      final fullCode = error.fullCode;
      final expectedCode = (2 << 16) | 512;

      expect(fullCode, equals(expectedCode));
    });

    test('displayMessage formats nicely', () {
      final error = FFIError(
        category: FFIErrorCategory.invalidInput,
        code: 100,
        message: 'Bad parameter',
        context: 'my_function',
        suggestion: 'Try X instead',
      );

      final display = error.displayMessage;

      expect(display, contains('[Invalid Input:100]'));
      expect(display, contains('Bad parameter'));
      expect(display, contains('(in my_function)'));
      expect(display, contains('💡 Try X instead'));
    });

    test('isRecoverable identifies recoverable errors', () {
      expect(
        FFIError(category: FFIErrorCategory.invalidInput, code: 0, message: '').isRecoverable,
        isTrue,
      );

      expect(
        FFIError(category: FFIErrorCategory.notFound, code: 0, message: '').isRecoverable,
        isTrue,
      );

      expect(
        FFIError(category: FFIErrorCategory.invalidState, code: 0, message: '').isRecoverable,
        isFalse,
      );

      expect(
        FFIError(category: FFIErrorCategory.syncError, code: 0, message: '').isRecoverable,
        isFalse,
      );
    });
  });

  group('FFIException', () {
    test('wraps FFIError', () {
      final error = FFIError(
        category: FFIErrorCategory.audioError,
        code: 800,
        message: 'Playback failed',
      );

      final exception = FFIException(error);

      expect(exception.error, equals(error));
      expect(exception.toString(), contains('Playback failed'));
    });
  });

  group('FFIErrorHandler', () {
    test('parseError returns null for null input', () {
      final error = FFIErrorHandler.parseError(null);

      expect(error, isNull);
    });

    test('parseError returns null for empty string', () {
      final error = FFIErrorHandler.parseError('');

      expect(error, isNull);
    });

    test('parseError deserializes valid JSON', () {
      final jsonString = '''
      {
        "category": 4,
        "code": 404,
        "message": "Event not found"
      }
      ''';

      final error = FFIErrorHandler.parseError(jsonString);

      expect(error, isNotNull);
      expect(error!.category, equals(FFIErrorCategory.notFound));
      expect(error.code, equals(404));
      expect(error.message, equals('Event not found'));
    });

    test('parseError handles malformed JSON gracefully', () {
      final malformed = 'Not JSON at all';

      final error = FFIErrorHandler.parseError(malformed);

      expect(error, isNotNull);
      expect(error!.category, equals(FFIErrorCategory.unknown));
      expect(error.message, equals(malformed));
    });

    test('handleError calls onError callback', () {
      var callbackInvoked = false;
      FFIError? capturedError;

      final error = FFIError(
        category: FFIErrorCategory.invalidInput,
        code: 100,
        message: 'Test',
      );

      FFIErrorHandler.handleError(
        error,
        onError: (err) {
          callbackInvoked = true;
          capturedError = err;
        },
      );

      expect(callbackInvoked, isTrue);
      expect(capturedError, equals(error));
    });

    test('handleError throws when requested', () {
      final error = FFIError(
        category: FFIErrorCategory.audioError,
        code: 800,
        message: 'Test',
      );

      expect(
        () => FFIErrorHandler.handleError(error, throwOnError: true),
        throwsA(isA<FFIException>()),
      );
    });

    test('checkResult returns value when no error', () {
      final result = FFIErrorHandler.checkResult<int>(42);

      expect(result, equals(42));
    });

    test('checkResult returns null when error present', () {
      final result = FFIErrorHandler.checkResult<int>(
        42,
        errorJson: '{"category": 1, "code": 100, "message": "Error"}',
      );

      expect(result, isNull);
    });
  });

  group('FFIErrorCodes', () {
    test('constants are defined', () {
      expect(FFIErrorCodes.invalidInputGeneric, equals(100));
      expect(FFIErrorCodes.outOfBoundsArrayIndex, equals(200));
      expect(FFIErrorCodes.invalidStateNotInitialized, equals(300));
      expect(FFIErrorCodes.notFoundEvent, equals(400));
      expect(FFIErrorCodes.resourceExhaustedVoicePool, equals(500));
      expect(FFIErrorCodes.ioErrorFileNotFound, equals(600));
      expect(FFIErrorCodes.serializationJsonParseError, equals(700));
      expect(FFIErrorCodes.audioErrorPlaybackFailed, equals(800));
    });
  });
}
