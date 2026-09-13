import 'package:flutter_test/flutter_test.dart';
import 'package:kashiv_vault/features/home/home_shell.dart';

void main() {
  test('tabs with a direct add button never show the shortcut strip', () {
    // Company, Personal and Tasks must keep their own add button, so the
    // shell's quick-add must stay out of their way.
    for (final tab in tabsWithOwnAddButton) {
      expect(
        showQuickAddFor(tab),
        isFalse,
        reason: 'tab $tab owns its add button',
      );
    }
  });

  test('home and more expose the shortcut strip', () {
    expect(showQuickAddFor(0), isTrue); // Home
    expect(showQuickAddFor(4), isTrue); // More
  });
}
