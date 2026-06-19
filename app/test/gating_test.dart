// Full-coverage tests for the app-gate precedence (loading > maintenance >
// hard update > normal). This decides what the user sees at launch.

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart';

void main() {
  group('selectActiveGate precedence', () {
    test('initializing always wins', () {
      expect(
        selectActiveGate(isInitializing: true, needsMaintenanceMode: true, needsHardUpdate: true),
        ActiveGate.loading,
      );
    });

    test('maintenance beats hard update', () {
      expect(
        selectActiveGate(isInitializing: false, needsMaintenanceMode: true, needsHardUpdate: true),
        ActiveGate.maintenance,
      );
    });

    test('hard update when maintenance off', () {
      expect(
        selectActiveGate(isInitializing: false, needsMaintenanceMode: false, needsHardUpdate: true),
        ActiveGate.hardUpdate,
      );
    });

    test('normal when nothing pending', () {
      expect(
        selectActiveGate(isInitializing: false, needsMaintenanceMode: false, needsHardUpdate: false),
        ActiveGate.normal,
      );
    });
  });
}
