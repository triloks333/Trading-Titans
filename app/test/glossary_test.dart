// Unit tests for the beginner glossary lookup. These guard the case-insensitive
// fetch and the integrity of the term list (no blanks, unique keys) that the
// inline tooltips and Glossary screen depend on.

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/glossary.dart';

void main() {
  group('Glossary.of', () {
    test('finds a known term regardless of case/whitespace', () {
      final exact = Glossary.of('Margin');
      expect(exact, isNotNull);
      expect(exact!.term, 'Margin');

      expect(Glossary.of('margin')?.term, 'Margin');
      expect(Glossary.of('  MARGIN  ')?.term, 'Margin');
    });

    test('returns null for an unknown term', () {
      expect(Glossary.of('definitely-not-a-term'), isNull);
      expect(Glossary.of(''), isNull);
    });

    test('resolves multi-word and parenthesized terms', () {
      expect(Glossary.of('strike price')?.term, 'Strike Price');
      expect(Glossary.of('call (ce)')?.term, 'Call (CE)');
    });
  });

  group('Glossary.terms integrity', () {
    test('is non-empty and every entry is fully populated', () {
      expect(Glossary.terms, isNotEmpty);
      for (final t in Glossary.terms) {
        expect(t.term.trim(), isNotEmpty);
        expect(t.definition.trim(), isNotEmpty);
        expect(t.example.trim(), isNotEmpty);
      }
    });

    test('term keys are unique (case-insensitive)', () {
      final keys = Glossary.terms.map((t) => t.term.toLowerCase()).toList();
      expect(keys.toSet().length, keys.length);
    });
  });
}
