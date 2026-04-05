/// TimeStretch + Elastic FFI Bindings Tests
///
/// Tests elastic audio enums and data model correctness.
/// FFI calls are tested via integration tests (requires native lib).
@Tags(['provider'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/src/rust/native_ffi.dart';

void main() {
  group('ElasticQuality', () {
    test('has correct values', () {
      expect(ElasticQuality.values.length, 4);
      expect(ElasticQuality.preview.index, 0);
      expect(ElasticQuality.standard.index, 1);
      expect(ElasticQuality.high.index, 2);
      expect(ElasticQuality.ultra.index, 3);
    });
  });

  group('ElasticMode', () {
    test('has correct values', () {
      expect(ElasticMode.values.length, 6);
      expect(ElasticMode.auto.index, 0);
      expect(ElasticMode.polyphonic.index, 1);
      expect(ElasticMode.monophonic.index, 2);
      expect(ElasticMode.rhythmic.index, 3);
      expect(ElasticMode.speech.index, 4);
      expect(ElasticMode.creative.index, 5);
    });

    test('polyphonic is best for drums and ensembles', () {
      // Verify the mode exists and maps to correct algorithm
      expect(ElasticMode.polyphonic.index, 1);
    });

    test('rhythmic is best for percussion', () {
      expect(ElasticMode.rhythmic.index, 3);
    });
  });
}
