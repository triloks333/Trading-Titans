// The in-app policies must describe the product as it actually sells.
//
// This file used to assert the opposite: that the app was free, took no payments
// and had nothing to refund. Its own header said that if monetisation was ever
// switched on, these tests would fail and the expectations should be flipped
// rather than deleted. That is what happened, and this is the flip.
//
// The failure mode being guarded has not changed, only its direction. Then, it was
// promising a refund policy for something nobody could buy. Now it is charging a
// user under terms that tell them they cannot be charged — which is the worse of
// the two, because money changes hands. A user must be able to read, in the app,
// what they can be billed for, that it renews by itself, how to stop it, and how
// to get their money back when we are at fault.

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/legal.dart';

/// Every word of a document, lowercased, for phrase checks.
String flatten(LegalDoc doc) {
  final parts = <String>[
    doc.title,
    doc.intro,
    if (doc.notice != null) doc.notice!,
    for (final s in doc.sections) ...[
      s.heading,
      ...s.paragraphs,
      ...s.bullets,
    ],
  ];
  return parts.join(' ').toLowerCase();
}

void main() {
  final docs = {'terms': LegalDocs.terms, 'privacy': LegalDocs.privacy};

  group('the policies match a product with optional paid plans', () {
    test('nothing still claims the app cannot be paid for', () {
      // Each of these was true in the previous revision and is now false. Any one
      // of them surviving would tell a paying user they cannot be charged.
      const stale = [
        'no in-app purchases',
        'nothing to refund',
        'there is nothing to pay for',
        'no payment information',
        'because there is nothing to buy',
        'we will never ask you to pay',
      ];
      for (final entry in docs.entries) {
        final text = flatten(entry.value);
        for (final phrase in stale) {
          expect(text, isNot(contains(phrase)),
              reason: '"$phrase" is in ${entry.key}, but plans are now sold');
        }
      }
    });

    test('terms disclose what is sold and that it renews by itself', () {
      final text = flatten(LegalDocs.terms);
      // Auto-renewal is the single most complained-about term in subscription
      // products, and the one a user is most entitled to see in advance.
      expect(text, contains('renew automatically'));
      expect(text, contains('cancel'));
      // Price transparency: the user pays the number on the card, tax included.
      expect(text, contains('include gst'));
      // Who takes the money, so a card statement is recognisable.
      expect(text, contains('razorpay'));
    });

    test('terms carry a real cancellation and refund policy', () {
      final headings =
          LegalDocs.terms.sections.map((s) => s.heading.toLowerCase()).join(' ');
      expect(headings, contains('refund'),
          reason: 'a paid product needs a refund section a user can find');

      final text = flatten(LegalDocs.terms);
      // The two cases where we are unambiguously at fault must be covered, or the
      // policy is decoration.
      expect(text, contains('refunded in full'));
      expect(text, contains('charged twice'));
      // And a stated route to ask.
      expect(text, contains('payment reference'));
    });

    test('terms still say the app is free to use without buying', () {
      final text = flatten(LegalDocs.terms);
      expect(text, contains('free'));
      // Paid plans must read as optional, because they are.
      expect(text, contains('optional'));
      // The anti-fraud line matters more than the legal boilerplate: if someone
      // is asking users for money outside our own checkout, users should know it
      // is not us.
      expect(text, contains('it is not us'));
    });

    test('privacy is honest about payment data in both directions', () {
      final text = flatten(LegalDocs.privacy);
      // What we genuinely never see. Naming the instruments is what makes the
      // promise legible to a user worried about exactly these.
      expect(text, contains('card numbers'));
      expect(text, contains('upi'));
      // And what we do keep, so the claim above is not a half-truth.
      expect(text, contains('razorpay'));
      expect(text, contains('payment reference'));
    });

    test('demo cash is worthless and non-withdrawable even when bought', () {
      final text = flatten(LegalDocs.terms);
      expect(text, contains('zero real-world value'));
      expect(text, contains('cannot be withdrawn'));
      // The important addition: paying for demo cash must not imply it became
      // real. This is the line that separates a simulator from a deposit.
      expect(text, contains('paid for'));
      expect(text, contains('not make that balance real money'));
    });

    test('the notice warns that some features cost money', () {
      final notice = LegalDocs.terms.notice!.toLowerCase();
      expect(notice, contains('paid'));
      // A purchased balance is still fictional, and the notice is where a user
      // who reads nothing else will see it.
      expect(notice, contains('top-up'));
    });
  });

  group('document structure', () {
    test('every section carries body text', () {
      for (final entry in docs.entries) {
        for (final s in entry.value.sections) {
          expect(s.paragraphs.isNotEmpty || s.bullets.isNotEmpty, isTrue,
              reason: '"${s.heading}" in ${entry.key} has no body');
        }
      }
    });

    test('sections are numbered consecutively from 1', () {
      for (final entry in docs.entries) {
        final sections = entry.value.sections;
        for (var i = 0; i < sections.length; i++) {
          expect(sections[i].heading, startsWith('${i + 1}. '),
              reason: '${entry.key} section ${i + 1} is misnumbered');
        }
      }
    });

    test('both documents share one last-updated date', () {
      expect(LegalDocs.terms.lastUpdated, LegalDocs.privacy.lastUpdated);
      expect(LegalDocs.terms.lastUpdated, isNotEmpty);
    });

    test('terms keep the virtual-only notice, privacy does not', () {
      expect(LegalDocs.terms.notice, isNotNull);
      final notice = LegalDocs.terms.notice!.toLowerCase();
      expect(notice, contains('educational'));
      expect(notice, contains('fictional'));
      expect(notice, contains('free'));
      expect(LegalDocs.privacy.notice, isNull);
    });

    test('the discloseable third parties are actually named', () {
      // Play requires disclosing what the app talks to. These are the ones the
      // app really uses: Supabase, Firebase (crash/analytics/FCM), the quote
      // providers, and now the payment processor.
      final text = flatten(LegalDocs.privacy);
      for (final name in ['supabase', 'firebase', 'coindcx', 'yahoo', 'razorpay']) {
        expect(text, contains(name), reason: '$name is not disclosed');
      }
    });
  });
}
