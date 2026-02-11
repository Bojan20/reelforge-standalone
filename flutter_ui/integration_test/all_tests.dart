/// FluxForge Studio — E2E Integration Test Suite
///
/// Master entry point that runs ALL E2E tests in sequence.
/// Total: 76 tests across 5 test groups.
///
/// Usage:
///   cd flutter_ui
///   flutter test integration_test/all_tests.dart -d macos
///
/// Individual groups:
///   flutter test integration_test/tests/app_launch_test.dart -d macos
///   flutter test integration_test/tests/daw_section_test.dart -d macos
///   flutter test integration_test/tests/slotlab_section_test.dart -d macos
///   flutter test integration_test/tests/middleware_section_test.dart -d macos
///   flutter test integration_test/tests/cross_section_test.dart -d macos

import 'tests/app_launch_test.dart' as app_launch;
import 'tests/daw_section_test.dart' as daw_section;
import 'tests/slotlab_section_test.dart' as slotlab_section;
import 'tests/middleware_section_test.dart' as middleware_section;
import 'tests/cross_section_test.dart' as cross_section;

void main() {
  app_launch.main();
  daw_section.main();
  slotlab_section.main();
  middleware_section.main();
  cross_section.main();
}
