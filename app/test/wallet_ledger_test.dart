// Presentation of wallet_transactions rows.
//
// This is money on screen, and the failure is silent: a debit rendered as a
// credit still looks like a perfectly good statement line. The sign assertions
// below are the important ones.
//
// The `kind` vocabulary is pinned against what
// supabase/migrations/20260821000000_wallet_transactions_ledger.sql can actually
// produce. That column deliberately has no CHECK constraint — so that no
// statement line is ever dropped for carrying an unknown label — which means
// this switch must also survive a value it has never seen.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/screens/main/wallet_screen.dart';

void main() {
  // Every kind the trigger in the migration assigns.
  const kindsFromMigration = <String>[
    'opening',
    'trade',
    'referral',
    'plan',
    'credit',
    // Set via app.wallet_reason by convert_guest_account() in
    // supabase/migrations/20260822000000_guest_conversion.sql.
    'conversion_bonus',
  ];

  group('sign decides credit vs debit', () {
    test('a negative amount is never presented as a credit', () {
      for (final kind in kindsFromMigration) {
        expect(
          walletTxDisplay(kind: kind, amount: -1500).isCredit,
          isFalse,
          reason: kind,
        );
      }
    });

    test('a positive amount is presented as a credit', () {
      for (final kind in kindsFromMigration) {
        expect(
          walletTxDisplay(kind: kind, amount: 1500).isCredit,
          isTrue,
          reason: kind,
        );
      }
    });

    test('sign wins over the kind, not the other way round', () {
      // A 'credit' row carrying a negative amount must still read as a debit —
      // the number is the truth, the label is a hint.
      expect(walletTxDisplay(kind: 'credit', amount: -500).isCredit, isFalse);
      // ...and a 'trade' row that credited the wallet reads as a credit.
      expect(walletTxDisplay(kind: 'trade', amount: 500).isCredit, isTrue);
    });
  });

  group('labels for each kind the migration writes', () {
    test('opening balance', () {
      expect(walletTxDisplay(kind: 'opening', amount: 11000).label,
          'Opening balance');
    });

    test('trade wording follows the direction of the money', () {
      expect(walletTxDisplay(kind: 'trade', amount: -2964.80).label, 'Trade cost');
      expect(
          walletTxDisplay(kind: 'trade', amount: 3020).label, 'Trade proceeds');
    });

    test('referral, plan and credit', () {
      expect(walletTxDisplay(kind: 'referral', amount: 5000).label,
          'Referral bonus');
      expect(walletTxDisplay(kind: 'plan', amount: 500000).label, 'Plan credit');
      expect(walletTxDisplay(kind: 'credit', amount: 1000).label,
          'Demo cash credited');
      // The hint path leaves description NULL, so this fallback is what the
      // upgraded guest actually reads on their statement.
      expect(walletTxDisplay(kind: 'conversion_bonus', amount: 6000).label,
          'Permanent account bonus');
    });

    test('every migration kind resolves to a non-empty label and icon', () {
      for (final kind in kindsFromMigration) {
        final d = walletTxDisplay(kind: kind, amount: 100);
        expect(d.label, isNotEmpty, reason: kind);
        expect(d.icon, isA<IconData>(), reason: kind);
      }
    });
  });

  group("the row's own description wins when present", () {
    test('the backfill description is shown verbatim', () {
      // The migration backfills existing users with this exact wording.
      expect(
        walletTxDisplay(
          kind: 'opening',
          amount: 785840.56,
          description: 'Balance brought forward',
        ).label,
        'Balance brought forward',
      );
    });

    test('an app.wallet_reason hint row shows its description', () {
      expect(
        walletTxDisplay(
          kind: 'reward_claim',
          amount: 2000,
          description: 'Challenge complete: Sniper',
        ).label,
        'Challenge complete: Sniper',
      );
    });

    test('an empty or whitespace description falls back to the default', () {
      // The trigger stores NULL for hinted rows, but an empty string from a
      // manual insert must not render as a blank line.
      expect(walletTxDisplay(kind: 'trade', amount: -10, description: '').label,
          'Trade cost');
      expect(
          walletTxDisplay(kind: 'trade', amount: -10, description: '   ').label,
          'Trade cost');
    });
  });

  group('unknown kinds degrade instead of throwing', () {
    test('an unseen kind with no description still labels by direction', () {
      // A future app.wallet_reason value this build predates.
      expect(walletTxDisplay(kind: 'reward_claim', amount: 750).label, 'Credit');
      expect(walletTxDisplay(kind: 'reward_claim', amount: -750).label, 'Debit');
    });

    test('an empty kind is handled', () {
      // getWalletTransactions() substitutes '' for a null kind column.
      final d = walletTxDisplay(kind: '', amount: 100);
      expect(d.label, isNotEmpty);
      expect(d.isCredit, isTrue);
    });

    test('a garbage kind never throws', () {
      for (final kind in ['', 'OPENING', 'Trade', 'nonsense', '123', 'null']) {
        expect(
          () => walletTxDisplay(kind: kind, amount: 1),
          returnsNormally,
          reason: kind,
        );
      }
    });
  });
}
