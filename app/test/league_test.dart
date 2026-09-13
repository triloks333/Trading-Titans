// The two pure bits of the league screen.
//
// Both take user-supplied data straight from the `leaderboard` view, and both had
// a way to fail badly: `name[0]` throws on an empty string, which would blank the
// whole tab rather than one row, and the rank phrasing is the kind of off-by-one
// that ships as "1 traders ahead of you".

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/screens/main/compete_screen.dart';

void main() {
  group('avatarInitial', () {
    test('uses the first letter, upper-cased', () {
      expect(avatarInitial('Pawan'), 'P');
      expect(avatarInitial('abhindan patil'), 'A');
    });

    test('survives every empty-ish name without throwing', () {
      // A blank display name is reachable: profiles.name defaults to '' and the
      // view passes it straight through.
      expect(avatarInitial(null), '?');
      expect(avatarInitial(''), '?');
      expect(avatarInitial('   '), '?');
      expect(avatarInitial('\n\t'), '?');
    });

    test('trims before picking, so a leading space is not the initial', () {
      expect(avatarInitial('  Trilok'), 'T');
    });

    test('handles a name whose first character is not one code unit', () {
      // Devanagari and emoji both appear in real display names. Indexing with
      // [0] would split a surrogate pair and render a replacement glyph.
      expect(avatarInitial('अमित'), 'अ');
      expect(avatarInitial('🚀 rocket'), '🚀');
    });
  });

  group('standingLabel', () {
    test('the leader is told they lead, not that 0 people are ahead', () {
      expect(standingLabel(0), 'Top of the board');
    });

    test('singular at one, plural above it', () {
      expect(standingLabel(1), '1 trader ahead of you');
      expect(standingLabel(2), '2 traders ahead of you');
      expect(standingLabel(19), '19 traders ahead of you');
    });

    test('a negative index cannot happen but must not read as nonsense', () {
      // indexWhere returns -1 when absent; the caller guards on >= 0, so this is
      // belt-and-braces rather than a live path.
      expect(standingLabel(-1), 'Top of the board');
    });
  });
}
