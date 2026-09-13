// Semantics of the update / maintenance gate, driven entirely by app_config.
//
// This decision had no test coverage, and it is easy to misread: the soft
// window is HALF-OPEN, so an installed version equal to `latest_version` is
// correctly silent. That is what makes a stale `latest_version` row look like a
// broken feature — every user on the previous build sits exactly on the closed
// end of the window and is never told.

import 'package:flutter_test/flutter_test.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:mobile/services/auth_service.dart';

void main() {
  const url = 'https://play.google.com/store/apps/details?id=com.kwm.tradingtitans';

  Map<String, String> cfg({
    String? min = '1.0.0',
    String? latest = '1.1.3',
    String? updateUrl = url,
    String? maintenance,
    String? message,
    String? notes,
  }) =>
      {
        'min_supported_version': ?min,
        'latest_version': ?latest,
        'update_url': ?updateUrl,
        'maintenance_mode': ?maintenance,
        'maintenance_message': ?message,
        'latest_version_notes': ?notes,
      };

  const now = 1000000000000;
  EvaluationResult run(Map<String, String> c, String local, {int? dismissed}) =>
      evaluateConfig(c, Version.parse(local), now, dismissed);

  group('soft update window', () {
    test('offers the update when a newer version is published', () {
      final r = run(cfg(latest: '1.1.3'), '1.1.2');
      expect(r.needsSoftUpdate, isTrue);
      expect(r.needsHardUpdate, isFalse);
      expect(r.updateUrl, url);
    });

    test('stays silent when installed equals latest', () {
      // The regression that reads as "the popup does not work": after shipping
      // 1.1.3, latest_version still said 1.1.2, so every user on 1.1.2 hit this.
      expect(run(cfg(latest: '1.1.2'), '1.1.2').needsSoftUpdate, isFalse);
    });

    test('stays silent when installed is ahead of latest', () {
      // A sideloaded dev build, or a stale config row.
      expect(run(cfg(latest: '1.0.0'), '1.1.2').needsSoftUpdate, isFalse);
    });

    test('patch and minor bumps both open the window', () {
      expect(run(cfg(latest: '1.1.3'), '1.1.2').needsSoftUpdate, isTrue);
      expect(run(cfg(latest: '1.2.0'), '1.1.2').needsSoftUpdate, isTrue);
      expect(run(cfg(latest: '2.0.0'), '1.1.2').needsSoftUpdate, isTrue);
    });

    test('an empty update_url disables the prompt entirely', () {
      // Both gates need somewhere to send the user, so a blank url is fail-open.
      expect(run(cfg(updateUrl: ''), '1.1.2').needsSoftUpdate, isFalse);
      expect(run(cfg(updateUrl: null), '1.1.2').needsSoftUpdate, isFalse);
    });
  });

  group('soft update snooze', () {
    test('an active snooze suppresses the prompt', () {
      final r = run(cfg(), '1.1.2', dismissed: now - const Duration(hours: 23).inMilliseconds);
      expect(r.needsSoftUpdate, isFalse);
    });

    test('the prompt returns once 24h has passed', () {
      final r = run(cfg(), '1.1.2', dismissed: now - const Duration(hours: 25).inMilliseconds);
      expect(r.needsSoftUpdate, isTrue);
    });

    test('a snooze never suppresses a hard update', () {
      final r = run(cfg(min: '1.2.0'), '1.1.2', dismissed: now);
      expect(r.needsHardUpdate, isTrue);
    });
  });

  group('hard update gate', () {
    test('blocks a build below min_supported_version', () {
      final r = run(cfg(min: '1.2.0', latest: '1.2.0'), '1.1.2');
      expect(r.needsHardUpdate, isTrue);
      expect(r.minCheckCompleted, isTrue);
    });

    test('does not block a build at min_supported_version', () {
      expect(run(cfg(min: '1.1.2'), '1.1.2').needsHardUpdate, isFalse);
    });

    test('is off for everyone while min_supported_version is 1.0.0', () {
      // The live value. Worth pinning: it means the blocking gate is dormant,
      // and only the soft prompt is doing any work.
      for (final v in ['1.0.0', '1.0.17', '1.1.2', '2.0.0']) {
        expect(run(cfg(min: '1.0.0'), v).needsHardUpdate, isFalse, reason: v);
      }
    });
  });

  group('fail-open on bad or missing data', () {
    test('an absent min_supported_version reports the check as incomplete', () {
      final r = run(cfg(min: null), '1.1.2');
      expect(r.needsHardUpdate, isFalse);
      expect(r.minCheckCompleted, isFalse);
    });

    test('malformed versions disable only their own gate', () {
      // '1.1' and 'v1.1.3' both fail the x.y.z shape the client requires — the
      // failure mode a '1.1.3+35' style value would hit.
      expect(run(cfg(min: '1.1'), '1.1.2').needsHardUpdate, isFalse);
      expect(run(cfg(latest: 'v1.1.3'), '1.1.2').needsSoftUpdate, isFalse);
      expect(run(cfg(latest: '1.1.3+35'), '1.1.2').needsSoftUpdate, isFalse);
      // A bad latest must not take the hard gate down with it.
      expect(run(cfg(min: '1.2.0', latest: 'nonsense'), '1.1.2').needsHardUpdate, isTrue);
    });

    test('an empty config gates nothing', () {
      final r = run(const {}, '1.1.2');
      expect(r.needsHardUpdate, isFalse);
      expect(r.needsSoftUpdate, isFalse);
      expect(r.needsMaintenanceMode, isFalse);
    });
  });

  group('maintenance mode', () {
    test('only the literal "true" enables it', () {
      expect(run(cfg(maintenance: 'true'), '1.1.2').needsMaintenanceMode, isTrue);
      for (final v in ['false', 'TRUE', '1', 'yes', '']) {
        expect(run(cfg(maintenance: v), '1.1.2').needsMaintenanceMode, isFalse,
            reason: v);
      }
    });

    test('passes the configured message through', () {
      final r = run(cfg(maintenance: 'true', message: 'Back at 6pm IST'), '1.1.2');
      expect(r.maintenanceMessage, 'Back at 6pm IST');
    });
  });

  test('release notes are carried to the dialog', () {
    final r = run(cfg(notes: '• Faster charts'), '1.1.2');
    expect(r.latestVersionNotes, '• Faster charts');
  });
}
