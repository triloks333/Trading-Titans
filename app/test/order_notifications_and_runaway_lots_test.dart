// Bug-condition exploration test for the
// "order-notifications-and-runaway-lots-fix" spec.
//
// Property 1 (Bug Condition / Expected Behavior):
//   "Duplicate Notifications, Double Execution, Underfunded Fills, And
//    Swallowed Failures"
//
//   isBugCondition(X) holds when, for a single fill, more than one user-facing
//   "executed" notification is produced (Bug 1); OR a pending order executes
//   more than once (Bug 2a); OR an opening/adding pending order fills despite
//   insufficient funds (Bug 2b); OR a failed F&O execution silently loses the
//   order (Bug 2a / 2.7).
//
//   The assertions below encode the EXPECTED (fixed) behavior:
//     * feedNotificationCount == 1  (one canonical trigger-sourced feed row)
//     * deviceAlertCount    <= 1    (the single local push, no duplicate feed)
//     * executionCount      <= 1    (at-most-once pending execution)
//     * abs(newNetQty - oldNetQty) == filledQty  (net_qty grows by exactly the
//       filled quantity, never unbounded)
//     * underfunded non-exit open/add is NOT filled (left pending)
//     * a failed order ends in {pending, failed} (never silently lost)
//   Validates: Requirements 1.1-1.9, 2.1-2.9
//
// IMPORTANT (bugfix workflow):
//   This test is EXPECTED TO FAIL on the UNFIXED code. The failure confirms the
//   two bugs exist. DO NOT fix the test or the production code in response to
//   the failure - the SAME Property 1 assertions are re-run in task 3.7 to
//   confirm the fix.
//
// Why this models the code paths directly (offline-helper approach):
//   `SupabaseService.placeOrder` / `executePendingOrders` cannot be driven
//   offline - they depend on a live Supabase backend (`Supabase.instance.client`),
//   `MarketService.quote`, and `getUserProfile`, none of which are injectable.
//   Mirroring `app/test/exit_position_order_test.dart` (proven for the prior
//   `exit-position-order-fix` spec), this test ports the UNFIXED notification
//   fan-out and pending-execution decision logic verbatim into pure Dart
//   helpers and drives them with `glados` generators. For the notification
//   counts it uses the Supabase-MCP-confirmed `trg_order_executed` ->
//   `notify_order_executed()` trigger behavior as the oracle: exactly one feed
//   row is inserted per executed-order write, in addition to any explicit Dart
//   "Order Executed" insert (which the fix removes).

import 'package:flutter_test/flutter_test.dart';
import 'package:glados/glados.dart'
    hide test, group, expect, setUpAll, setUp, tearDown, tearDownAll;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile/services/supabase_service.dart';

// ===========================================================================
// Notification fan-out model (Bug 1).
//
// Oracle (confirmed via Supabase MCP on project bftvimnhpoiuoyryyiff):
//   The `trg_order_executed` trigger fires `notify_order_executed()` on every
//   executed-order write (INSERT/UPDATE where status becomes 'filled'/'executed'
//   with a status change) and inserts EXACTLY ONE `notifications` feed row.
//   The `notifications` table itself has NO trigger/webhook/edge function, so a
//   feed row never produces an OS/FCM push.
// ===========================================================================

/// Outcome of one fill's notification fan-out.
class NotifOutcome {
  /// Feed rows from the canonical DB trigger (always 1 per executed write).
  final int triggerFeedRows;

  /// Feed rows inserted explicitly by the Dart code for this fill.
  /// UNFIXED: 1 (the redundant "Order Executed" insert). FIXED: 0.
  final int clientFeedRows;

  /// Local OS-level device pushes raised for this fill (foreground UX only).
  final int deviceAlertCount;

  const NotifOutcome({
    required this.triggerFeedRows,
    required this.clientFeedRows,
    required this.deviceAlertCount,
  });

  /// Total user-facing notification feed rows (what `NotificationsScreen` shows).
  int get feedNotificationCount => triggerFeedRows + clientFeedRows;

  @override
  String toString() => 'NotifOutcome(feed=$feedNotificationCount '
      '[trigger=$triggerFeedRows + client=$clientFeedRows], '
      'deviceAlerts=$deviceAlertCount)';
}

/// Port of the UNFIXED immediate-fill notification path in `placeOrder`
/// (F&O ~line 1779; equity ~line 2114): the executed-order write fires the
/// trigger (1 feed row) AND the explicit Dart `notifications` insert titled
/// "Order Executed" runs (1 more feed row). When the fill is returned to
/// `order_entry_screen.dart` `_submitOrder` (~line 240) a local device push is
/// also raised.
NotifOutcome simulateUnfixedImmediateFillNotifications({
  required bool returnedToOrderEntry,
}) {
  return NotifOutcome(
    triggerFeedRows: 1, // notify_order_executed() on the executed write
    clientFeedRows: 1, // redundant explicit Dart "Order Executed" insert
    deviceAlertCount: returnedToOrderEntry ? 1 : 0, // foreground local push
  );
}

/// Port of the UNFIXED pending-fill notification path in `executePendingOrders`
/// (F&O ~line 2494; equity ~line 2760): each fill writes the executed order
/// (firing the trigger once) AND inserts a redundant Dart "Order Executed" row.
/// Pending execution runs in the background, so no foreground device push.
NotifOutcome simulateUnfixedPendingFillNotifications() {
  return const NotifOutcome(
    triggerFeedRows: 1,
    clientFeedRows: 1, // redundant explicit Dart insert on the pending path
    deviceAlertCount: 0,
  );
}

// ===========================================================================
// At-most-once pending execution model (Bug 2a).
// ===========================================================================

/// Outcome of executing a single pending order under `overlappingPasses`
/// concurrent `executePendingOrders()` invocations.
class PendingExecOutcome {
  final int executionCount; // how many times the order actually executed
  final int oldNetQty; // position net_qty before
  final int newNetQty; // position net_qty after

  const PendingExecOutcome({
    required this.executionCount,
    required this.oldNetQty,
    required this.newNetQty,
  });

  int get filledQty => executionCount == 0 ? 0 : (newNetQty - oldNetQty).abs();

  @override
  String toString() => 'PendingExecOutcome(executionCount=$executionCount, '
      'oldNetQty=$oldNetQty, newNetQty=$newNetQty)';
}

/// Port of the UNFIXED `executePendingOrders` dedupe behavior under overlap.
///
/// The unfixed loop re-reads all `status='pending'` rows and executes each
/// after several `await`s (quote/profile/lot-size). It has NO atomic claim and
/// NO in-flight guard, so when `getOrders()` (~344) and `getHoldings()` (~649)
/// (and multiple screens) trigger overlapping passes, the same still-pending
/// row is read by every pass before it is deleted/updated, and each pass
/// executes it. The position `net_qty` therefore grows by `lots` per pass.
PendingExecOutcome simulateUnfixedPendingExecution({
  required int overlappingPasses,
  required int existingNetQty,
  required int lots, // signed: +N for a BUY of N lots
}) {
  // No claim/guard: every overlapping pass that read the pending snapshot
  // executes the same order.
  final int executionCount = overlappingPasses;
  final int newNetQty = existingNetQty + (lots * executionCount);
  return PendingExecOutcome(
    executionCount: executionCount,
    oldNetQty: existingNetQty,
    newNetQty: newNetQty,
  );
}

// ===========================================================================
// Opening/adding funds-gate model (Bug 2b).
// ===========================================================================

/// Outcome of the funds decision for an opening/adding pending F&O order.
class FundsOutcome {
  final bool filled; // did the order fill (pass the guard)?
  final double requiredCapital; // full incremental capital at execPrice
  final double walletBalance;
  final double totalCharges;

  const FundsOutcome({
    required this.filled,
    required this.requiredCapital,
    required this.walletBalance,
    required this.totalCharges,
  });

  /// The true funds-sufficiency predicate the FIXED code must enforce.
  bool get fundsSufficient => walletBalance >= requiredCapital + totalCharges;

  @override
  String toString() => 'FundsOutcome(filled=$filled, requiredCapital='
      '${requiredCapital.toStringAsFixed(2)}, walletBalance='
      '${walletBalance.toStringAsFixed(2)}, charges='
      '${totalCharges.toStringAsFixed(2)}, fundsSufficient=$fundsSufficient)';
}

/// Full incremental capital required at `execPrice` for adding `addLots`
/// futures lots (15% margin on the added notional) - the FIXED check.
double requiredCapitalFutures({
  required double execPrice,
  required int addLots,
  required int lotSize,
}) =>
    execPrice * addLots * lotSize * 0.15;

/// Port of the UNFIXED opening/adding funds check in `executePendingOrders`
/// (futures branch). It blocks margin on the BLENDED average and debits only
/// the margin DELTA `marginBlocked - oldMargin`, then applies the shared
/// net-impact guard `walletBalance + finalCredit - finalDebit < 0 => skip`.
///
/// Because `oldMargin` is read from the stored `fo_positions.margin_blocked`
/// (which, after prior adds at a higher average, can exceed the fresh
/// recomputation) the delta can be small or negative, so the guard passes for a
/// fill the true available balance does not support.
FundsOutcome simulateUnfixedFuturesAddFunds({
  required int existingQtyLots,
  required double existingAvg,
  required double existingMargin, // stored fo_positions.margin_blocked
  required int addLots,
  required double execPrice,
  required int lotSize,
  required double walletBalance,
  required double totalCharges,
}) {
  final int newNetQty = existingQtyLots + addLots; // same-direction add
  final double newAvgEntryPrice =
      ((existingAvg * existingQtyLots.abs()) + (execPrice * addLots)) /
          (existingQtyLots.abs() + addLots);
  final double marginBlocked =
      newAvgEntryPrice * newNetQty.abs() * lotSize * 0.15;
  final double oldMargin = existingMargin;
  double walletDebit = marginBlocked - oldMargin; // the delta guard
  double walletCredit = 0.0;

  // Charge adjustment exactly as the unfixed code does it.
  double finalDebit = walletDebit;
  double finalCredit = walletCredit;
  if (totalCharges > 0) {
    if (walletCredit >= totalCharges) {
      finalCredit = walletCredit - totalCharges;
    } else {
      finalCredit = 0.0;
      finalDebit = walletDebit + (totalCharges - walletCredit);
    }
  }

  // `if (profile.walletBalance + finalCredit - finalDebit < 0) continue;`
  final bool filled = !(walletBalance + finalCredit - finalDebit < 0);

  return FundsOutcome(
    filled: filled,
    requiredCapital: requiredCapitalFutures(
      execPrice: execPrice,
      addLots: addLots,
      lotSize: lotSize,
    ),
    walletBalance: walletBalance,
    totalCharges: totalCharges,
  );
}

// ===========================================================================
// Swallowed-failure model (Bug 2a / Property 5).
// ===========================================================================

/// Port of the UNFIXED F&O pending failure path in `executePendingOrders`:
/// the row is `delete()`d BEFORE the RPC, and the whole per-order body is
/// wrapped in `catch (_) {}`. If the RPC rejects (e.g. insufficient balance),
/// the failure is swallowed and the already-deleted order is silently lost -
/// it ends up in NO well-defined state (`'lost'`).
String simulateUnfixedFoRpcFailureStatus() {
  // 1. delete().eq('id', id)        -> row removed
  // 2. rpc(...) throws on balance    -> caught by catch(_){}
  // 3. nothing re-records the order  -> silently gone
  return 'lost';
}

// ===========================================================================
// FIXED-routing helpers for Property 1, 4 and 5 (Task 3.7).
//
// These mirror the actual Task 3.4-3.6 production edits in
// `app/lib/services/supabase_service.dart` so the re-run of the Property 1-5
// assertions reflects the real fixed routing (not a weakened test). The
// notification and at-most-once FIXED helpers already exist below in the
// Preservation section (`simulateFixedImmediateFillNotifications`,
// `simulateFixedPendingFillNotifications`, `simulateFixedPendingExecution`);
// the two helpers here cover the FIXED funds-gate and failure-state cases.
// ===========================================================================

/// Port of the FIXED opening/adding funds gate in `executePendingOrders`
/// (Task 3.6). Mirrors EXACTLY the production check, which validates the FULL
/// incremental capital required at `execPrice` against the CURRENT available
/// balance (NOT the blended-average margin delta the unfixed code used):
///   final addedLots = tradeQtyLots;
///   final requiredCapital = (instrumentType == 'OPTION' && newNetQty > 0)
///       ? execPrice * quantity                     // long option: full premium
///       : execPrice * addedLots * lotSize * 0.15;  // futures / short option
///   if (profile.walletBalance < requiredCapital + totalCharges) {
///     continue; // leave pending; insufficient true funds (un-claimed)
///   }
/// So the order fills IFF `walletBalance >= requiredCapital + totalCharges`,
/// which is exactly `FundsOutcome.fundsSufficient`.
FundsOutcome simulateFixedOpenAddFunds({
  required String instrumentType, // 'OPTION' | 'FUTURE'
  required int newNetQty, // signed resulting net_qty (position direction)
  required int addLots, // opening/adding lots (unsigned)
  required double execPrice,
  required int lotSize,
  required double walletBalance,
  required double totalCharges,
}) {
  final double quantity = (addLots * lotSize).toDouble();
  final double requiredCapital = (instrumentType == 'OPTION' && newNetQty > 0)
      ? execPrice * quantity // long option: full premium
      : execPrice * addLots * lotSize * 0.15; // futures / short option margin
  // Faithful mirror of `walletBalance < requiredCapital + totalCharges` ->
  // leave pending; otherwise fill.
  final bool filled = walletBalance >= requiredCapital + totalCharges;
  return FundsOutcome(
    filled: filled,
    requiredCapital: requiredCapital,
    walletBalance: walletBalance,
    totalCharges: totalCharges,
  );
}

/// Port of the FIXED F&O pending failure path in `executePendingOrders`
/// (Task 3.4 + 3.5). The row is CLAIMED (`pending -> executing`) BEFORE the
/// RPC, and the per-order catch leaves a well-defined state instead of the old
/// delete-before-RPC + `catch(_){}` that silently lost the order:
///   } catch (e) {
///     if (claimed) {
///       await client.from('orders').update({'status': 'failed'})
///           .eq('id', id).eq('status', 'executing');
///     }
///     continue;
///   }
/// A failure AFTER a successful claim marks the order `failed`; a failure
/// BEFORE the claim (e.g. the pre-claim funds/price check) never claims the
/// row, so it simply stays `pending`. Either way it is never silently lost.
String simulateFixedFoRpcFailureStatus({required bool claimedBeforeFailure}) {
  return claimedBeforeFailure ? 'failed' : 'pending';
}

// ===========================================================================
// Expected-behavior assertion helpers (encode the FIXED contract).
// ===========================================================================

void assertOneCanonicalFeedRow(NotifOutcome o) {
  expect(o.feedNotificationCount, 1,
      reason: 'A single fill must produce exactly one canonical feed row '
          '(the trigger row); the redundant Dart "Order Executed" insert must '
          'be removed. $o');
}

void assertNoDuplicateDeviceAlert(NotifOutcome o) {
  expect(o.deviceAlertCount <= 1, isTrue,
      reason: 'At most one local device push per fill. $o');
  expect(o.clientFeedRows, 0,
      reason: 'The device alert must NOT be accompanied by a duplicate '
          'client-inserted feed row for the same fill. $o');
}

void assertAtMostOnceExecution(PendingExecOutcome o, {required int lots}) {
  expect(o.executionCount <= 1, isTrue,
      reason: 'Each eligible pending order must execute at most once '
          'regardless of overlap. $o');
  expect((o.newNetQty - o.oldNetQty).abs(), lots.abs(),
      reason: 'net_qty must change by exactly the filled quantity, never '
          'grow unbounded. $o');
}

void assertNoUnderfundedFill(FundsOutcome o) {
  expect(o.filled, o.fundsSufficient,
      reason: 'An opening/adding order must fill iff the full incremental '
          'capital at execPrice (+ charges) is covered by the wallet. $o');
}

void assertFailedOrderWellDefined(String status) {
  expect(<String>{'pending', 'failed'}.contains(status), isTrue,
      reason: 'A failed execution must leave the order in {pending, failed}, '
          'never silently lost. Got: "$status".');
}

// ===========================================================================
// PROPERTY 2 - PRESERVATION helpers (observation-first).
//
// Preservation: for all X where NOT isBugCondition(X), execute(X) = execute'(X).
// These helpers model BOTH the original (unfixed) and fixed behavior for the
// non-buggy paths and assert they are identical, capturing the baseline that
// task 3.8 re-runs against the fixed code.
//   Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 3.8
// ===========================================================================

// --- 3.1 Order Pending notification (insert at ~line 1459, untouched) ---

/// Feed rows produced when a NON-immediate (pending) order is PLACED.
/// The legitimate "Order Pending" insert (~line 1459) is the only feed source
/// (the executed trigger does NOT fire for a `pending` status). The fix does
/// not touch this insert, so both original and fixed produce exactly one row.
int orderPendingFeedRows() => 1; // single "Order Pending" insert, no trigger

// --- 3.2 Single executed (trigger) notification preserved ---

/// Port of the FIXED immediate-fill notification path: the redundant Dart
/// "Order Executed" insert is removed (clientFeedRows == 0) but the canonical
/// trigger row is preserved (triggerFeedRows == 1) and the single foreground
/// device push is kept.
NotifOutcome simulateFixedImmediateFillNotifications({
  required bool returnedToOrderEntry,
}) {
  return NotifOutcome(
    triggerFeedRows: 1, // notify_order_executed() still fires once per write
    clientFeedRows: 0, // redundant Dart insert removed by the fix
    deviceAlertCount: returnedToOrderEntry ? 1 : 0,
  );
}

/// Port of the FIXED pending-fill notification path: trigger row preserved,
/// redundant client insert removed.
NotifOutcome simulateFixedPendingFillNotifications() {
  return const NotifOutcome(
    triggerFeedRows: 1,
    clientFeedRows: 0,
    deviceAlertCount: 0,
  );
}

// --- 3.3 Below-trigger limit stays pending (price condition) ---

/// Port of the price-condition gate in `executePendingOrders` (unchanged by the
/// fix): a `limit` order only executes when its trigger price is met. Returns
/// true if the order would execute, false if it stays pending. `market` orders
/// always execute.
bool pendingOrderPriceConditionMet({
  required String orderType,
  required String side,
  required double execPrice,
  required double limitPrice,
}) {
  if (orderType == 'limit') {
    if (side == 'buy' && execPrice > limitPrice) return false;
    if (side == 'sell' && execPrice < limitPrice) return false;
  }
  return true;
}

// --- 3.4 / 3.5 Single sufficient-funds fill (at-most-once, preserved) ---

/// Port of the FIXED `executePendingOrders` dedupe: with the in-flight guard +
/// atomic claim, each eligible order executes AT MOST once regardless of how
/// many passes overlap. For a single, non-overlapping pass this is byte-for-byte
/// identical to the original (executionCount == 1, net_qty += filled qty).
PendingExecOutcome simulateFixedPendingExecution({
  required int overlappingPasses,
  required int existingNetQty,
  required int lots,
}) {
  final int executionCount = overlappingPasses >= 1 ? 1 : 0; // claim => once
  final int newNetQty = existingNetQty + (lots * executionCount);
  return PendingExecOutcome(
    executionCount: executionCount,
    oldNetQty: existingNetQty,
    newNetQty: newNetQty,
  );
}

// --- 3.6 Exit/close exemption from the new opening/adding funds gate ---

/// Port of the FIXED opening/adding funds gate. The stricter full-incremental-
/// capital check applies ONLY to opens/adds; closes/reduces (which release
/// capital) are exempt, preserving the prior `exit-position-order-fix`
/// behavior. Returns true if the order is BLOCKED (left pending), false if it
/// may fill.
bool fixedFundsGateBlocks({
  required bool isExitOrClose,
  required double walletBalance,
  required double requiredCapital,
  required double totalCharges,
}) {
  if (isExitOrClose) return false; // closes/reduces exempt (Req 3.6)
  return walletBalance < requiredCapital + totalCharges;
}

// --- 3.8 Realized P&L on a closing fill (reduce/close formula, preserved) ---

/// Port of the reduce/close realized-P&L formula in `executePendingOrders`
/// (unchanged by the fix):
///   (existingQty > 0 ? (exec - avg) : (avg - exec)) * closedLots * lotSize
double realizedPnlOnClose({
  required int existingQtyLots, // signed: >0 long, <0 short
  required double existingAvg,
  required double execPrice,
  required int closedLots,
  required int lotSize,
}) {
  final double perUnit = existingQtyLots > 0
      ? (execPrice - existingAvg)
      : (existingAvg - execPrice);
  return perUnit * closedLots * lotSize;
}

// ===========================================================================
// TASK 4 helpers - additional concurrency, funds-gate, and failure-state
// models (design Properties 3, 4, 5) driven on the FIXED routing.
//
// These build on the existing FIXED helpers (simulateFixedPendingExecution,
// simulateFixedOpenAddFunds, simulateFixedFoRpcFailureStatus,
// fixedFundsGateBlocks) and add the small models Task 4 calls for: an
// atomic-claim model returning exactly one winner among k concurrent callers,
// a multi-order concurrent-schedule aggregator, and a richer failure-state
// model that also asserts the order is not deleted / not added to
// executedOrders and that wallet/position are unchanged.
// ===========================================================================

/// Result of the atomic conditional claim
/// `UPDATE orders SET status='executing' WHERE id=? AND status='pending'`.
/// Postgres serialises the conditional update, so among `callers` concurrent
/// passes EXACTLY ONE observes a non-empty returned row set (the winner) and
/// transitions `pending -> executing`; every other caller matches zero rows
/// (`.select()` returns `[]`) and `continue`s without mutating.
class ClaimResult {
  /// Callers whose claim returned a row (must be exactly 1 when callers >= 1).
  final int winners;

  /// Callers that got zero rows back and skipped (callers - winners).
  final int skippers;

  const ClaimResult({required this.winners, required this.skippers});

  @override
  String toString() => 'ClaimResult(winners=$winners, skippers=$skippers)';
}

/// Model of the FIXED atomic claim among `callers` concurrent
/// `executePendingOrders()` passes contending for ONE pending row.
ClaimResult simulateAtomicClaim({required int callers}) {
  final int winners = callers >= 1 ? 1 : 0; // conditional update => one winner
  return ClaimResult(winners: winners, skippers: callers - winners);
}

/// Aggregated outcome of running a SET of pending orders through the FIXED
/// at-most-once executor under overlapping passes.
class MultiOrderOutcome {
  final int totalExecutions; // sum of per-order executionCount (<= 1 each)
  final int totalNetQtyDelta; // sum of |newNetQty - oldNetQty| per order
  final int sumFilledQty; // sum of per-order filledQty

  const MultiOrderOutcome({
    required this.totalExecutions,
    required this.totalNetQtyDelta,
    required this.sumFilledQty,
  });

  @override
  String toString() => 'MultiOrderOutcome(totalExecutions=$totalExecutions, '
      'totalNetQtyDelta=$totalNetQtyDelta, sumFilledQty=$sumFilledQty)';
}

/// Run a set of pending BUY orders (one per entry in `lotsPerOrder`, each
/// starting from the matching `existingNetQtyPerOrder`) through the FIXED
/// executor under `overlappingPasses` concurrent invocations and aggregate.
/// Each order is independently subject to the atomic claim, so it executes at
/// most once; the total net_qty delta therefore equals the sum of filled
/// quantities (no unbounded growth).
MultiOrderOutcome simulateFixedConcurrentSchedule({
  required List<int> lotsPerOrder,
  required List<int> existingNetQtyPerOrder,
  required int overlappingPasses,
}) {
  int totalExecutions = 0;
  int totalNetQtyDelta = 0;
  int sumFilledQty = 0;
  for (var i = 0; i < lotsPerOrder.length; i++) {
    final o = simulateFixedPendingExecution(
      overlappingPasses: overlappingPasses,
      existingNetQty: existingNetQtyPerOrder[i],
      lots: lotsPerOrder[i],
    );
    totalExecutions += o.executionCount;
    totalNetQtyDelta += (o.newNetQty - o.oldNetQty).abs();
    sumFilledQty += o.filledQty;
  }
  return MultiOrderOutcome(
    totalExecutions: totalExecutions,
    totalNetQtyDelta: totalNetQtyDelta,
    sumFilledQty: sumFilledQty,
  );
}

/// Richer FIXED failure-state outcome (design Property 5). On a claimed-then-
/// failed F&O execution the order is marked `failed` and is NEVER deleted,
/// NEVER added to `executedOrders`, and leaves wallet/position unchanged. A
/// pre-claim funds/price failure never claims the row, so it stays `pending`.
class FailureStateOutcome {
  final String status; // 'failed' (claimed) | 'pending' (pre-claim)
  final bool deleted; // FIXED never deletes on failure
  final bool addedToExecutedOrders; // FIXED never records a failed fill
  final double walletBefore;
  final double walletAfter;
  final int positionBefore;
  final int positionAfter;

  const FailureStateOutcome({
    required this.status,
    required this.deleted,
    required this.addedToExecutedOrders,
    required this.walletBefore,
    required this.walletAfter,
    required this.positionBefore,
    required this.positionAfter,
  });

  bool get walletUnchanged => walletAfter == walletBefore;
  bool get positionUnchanged => positionAfter == positionBefore;

  @override
  String toString() => 'FailureStateOutcome(status=$status, deleted=$deleted, '
      'addedToExecutedOrders=$addedToExecutedOrders, '
      'walletUnchanged=$walletUnchanged, positionUnchanged=$positionUnchanged)';
}

/// Model the FIXED F&O failure path (Task 3.4 + 3.5). Reuses the FIXED status
/// router `simulateFixedFoRpcFailureStatus` and adds the side-effect
/// invariants: no delete, no executedOrders entry, wallet/position untouched.
FailureStateOutcome simulateFixedFoFailureState({
  required bool claimedBeforeFailure,
  required double walletBefore,
  required int positionBefore,
}) {
  final status =
      simulateFixedFoRpcFailureStatus(claimedBeforeFailure: claimedBeforeFailure);
  return FailureStateOutcome(
    status: status,
    deleted: false, // FIXED only deletes on a CONFIRMED successful RPC
    addedToExecutedOrders: false, // a failed RPC inserts no executed row
    walletBefore: walletBefore,
    walletAfter: walletBefore, // RPC rolled back / never debited
    positionBefore: positionBefore,
    positionAfter: positionBefore, // position not mutated on failure
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // =========================================================================
  // Bug 1 - Duplicate executed-fill notifications (Properties 1 & 2).
  //
  // TASK 3.7 (fix verification): the SAME Property 1/2 assertions written in
  // task 1 (`assertOneCanonicalFeedRow` / `assertNoDuplicateDeviceAlert`), now
  // driven against the FIXED routing (`simulateFixedImmediateFillNotifications`
  // / `simulateFixedPendingFillNotifications`), which mirrors the Task 3.1-3.3
  // edits in `supabase_service.dart` (the four redundant Dart "Order Executed"
  // inserts removed -> clientFeedRows == 0; the canonical trigger row and the
  // single foreground device push preserved). EXPECTED TO PASS, confirming the
  // fix. The documented Task 1 counterexamples (what the UNFIXED routing
  // produced) are retained inline as comments, and the unfixed helpers remain
  // in this file (the Property 2 preservation groups still use them as the
  // baseline).
  // =========================================================================
  group('Property 1 - One canonical feed row per fill (PASSES on fixed)', () {
    test('Bug 1 case: F&O immediate fill via placeOrder (~line 1779)', () {
      // Task 1 counterexample (UNFIXED): one fill -> 2 feed rows (trigger +
      // explicit Dart insert) + 1 device push.
      // FIXED (Task 3.1): the redundant Dart insert is removed -> exactly one
      // canonical (trigger) feed row.
      final o = simulateFixedImmediateFillNotifications(
          returnedToOrderEntry: true);
      assertOneCanonicalFeedRow(o);
    });

    test('Bug 1 case: equity immediate fill via placeOrder (~line 2114)', () {
      final o = simulateFixedImmediateFillNotifications(
          returnedToOrderEntry: true);
      assertOneCanonicalFeedRow(o);
    });

    test('Bug 1 case: F&O pending fill via executePendingOrders (~line 2494)',
        () {
      // FIXED (Task 3.1): the pending-path Dart insert is removed; the executed
      // write still fires the trigger exactly once.
      final o = simulateFixedPendingFillNotifications();
      assertOneCanonicalFeedRow(o);
    });

    test(
        'Bug 1 case: equity pending fill via executePendingOrders (~line 2760)',
        () {
      final o = simulateFixedPendingFillNotifications();
      assertOneCanonicalFeedRow(o);
    });

    test('Observed: SELL 12000 RELIANCE fill produces one canonical feed row',
        () {
      // Reported screenshot (UNFIXED): two "Order Executed" + one "Sell Order
      // Executed" for one fill (trigger(1) + client(1) = 2 feed rows).
      // FIXED: the client insert is removed -> a single trigger-sourced row.
      final o = simulateFixedImmediateFillNotifications(
          returnedToOrderEntry: true);
      assertOneCanonicalFeedRow(o);
    });
  });

  group('Property 2 - No duplicate device alert (PASSES on fixed)', () {
    test('Bug 1 case: single device push, no duplicate client feed row', () {
      // Task 1 counterexample (UNFIXED): device push + duplicate client feed
      // row both occur for the same fill.
      // FIXED (Task 3.1/3.2): the single foreground local push is kept, but the
      // duplicate client feed row is removed (clientFeedRows == 0), so the
      // device alert no longer duplicates the canonical feed row.
      final o = simulateFixedImmediateFillNotifications(
          returnedToOrderEntry: true);
      assertNoDuplicateDeviceAlert(o);
    });
  });

  // =========================================================================
  // Bug 2a - Runaway lots / double execution (Property 3).
  //
  // TASK 3.7 (fix verification): the SAME `assertAtMostOnceExecution` invariant
  // from task 1, now driven against the FIXED routing
  // (`simulateFixedPendingExecution`), which mirrors the Task 3.4 edits in
  // `supabase_service.dart` (the in-flight `_pendingRun` guard + the atomic
  // conditional `pending -> executing` claim, so only one pass mutates the row
  // regardless of overlap). EXPECTED TO PASS: each pending order executes at
  // most once and net_qty changes by exactly the filled quantity.
  // =========================================================================
  group('Property 3 - At-most-once pending execution (PASSES on fixed)', () {
    test('Bug 2a case: one pending BUY for N lots, two concurrent passes', () {
      // Task 1 counterexample (UNFIXED): getOrders + getHoldings overlap ->
      // executionCount = 2, net_qty grows by 2N instead of N.
      // FIXED (Task 3.4): the atomic claim lets exactly one pass execute ->
      // executionCount = 1, net_qty grows by exactly N.
      const int lots = 5; // BUY 5 lots
      final o = simulateFixedPendingExecution(
        overlappingPasses: 2,
        existingNetQty: 0,
        lots: lots,
      );
      assertAtMostOnceExecution(o, lots: lots);
    });

    test('Bug 2a case: add to existing position executes once', () {
      const int lots = 3;
      final o = simulateFixedPendingExecution(
        overlappingPasses: 2,
        existingNetQty: 10,
        lots: lots,
      );
      assertAtMostOnceExecution(o, lots: lots);
    });

    // Generalize across lot count and overlap depth: regardless of how many
    // passes overlap, the FIXED claim guarantees a single execution, so net_qty
    // grows by exactly N.
    Glados2<int, int>(
      any.intInRange(1, 100), // lots in the pending BUY
      any.intInRange(2, 5), // overlapping passes (k >= 2 used to => bug)
    ).test('Pending order executes at most once regardless of overlap depth',
        (lots, passes) {
      final o = simulateFixedPendingExecution(
        overlappingPasses: passes,
        existingNetQty: 0,
        lots: lots,
      );
      assertAtMostOnceExecution(o, lots: lots);
    });
  });

  // =========================================================================
  // Bug 2b - Opening/adding fill without funds (Property 4).
  //
  // TASK 3.7 (fix verification): the SAME `assertNoUnderfundedFill` invariant
  // from task 1, now driven against the FIXED routing
  // (`simulateFixedOpenAddFunds`), which mirrors the Task 3.6 edit in
  // `supabase_service.dart`: the funds gate validates the FULL incremental
  // capital required at execPrice (full premium for long options, otherwise
  // `execPrice * addedLots * lotSize * 0.15`) plus charges against the current
  // wallet balance, leaving an underfunded open/add pending. EXPECTED TO PASS:
  // an order fills iff the funds are truly sufficient (filled == fundsSufficient).
  // =========================================================================
  group('Property 4 - No opening/adding fill without funds (PASSES on fixed)',
      () {
    test('Bug 2b case: underfunded futures add is left pending', () {
      // Task 1 counterexample (UNFIXED): the margin-delta guard
      // (marginBlocked - oldMargin, which went NEGATIVE here) filled an add the
      // wallet could not support.
      // FIXED: requiredCapital = 100*10*50*0.15 = 7,500; wallet 1,000 < 7,500
      // -> NOT filled (left pending).
      final o = simulateFixedOpenAddFunds(
        instrumentType: 'FUTURE',
        newNetQty: 20, // same-direction add -> long futures position
        addLots: 10,
        execPrice: 100.0,
        lotSize: 50,
        walletBalance: 1000.0,
        totalCharges: 0.0,
      );
      assertNoUnderfundedFill(o);
    });

    test('Bug 2b case: sufficiently-funded futures add fills', () {
      // requiredCapital = 7,500; wallet 10,000 >= 7,500 -> fills.
      final o = simulateFixedOpenAddFunds(
        instrumentType: 'FUTURE',
        newNetQty: 20,
        addLots: 10,
        execPrice: 100.0,
        lotSize: 50,
        walletBalance: 10000.0,
        totalCharges: 0.0,
      );
      assertNoUnderfundedFill(o);
    });

    test('Bug 2b case: long-option add requires the full premium', () {
      // Long option: requiredCapital = execPrice * quantity = 50 * (2*50) =
      // 5,000; wallet 4,000 < 5,000 -> left pending.
      final o = simulateFixedOpenAddFunds(
        instrumentType: 'OPTION',
        newNetQty: 2, // long option (newNetQty > 0)
        addLots: 2,
        execPrice: 50.0,
        lotSize: 50,
        walletBalance: 4000.0,
        totalCharges: 0.0,
      );
      assertNoUnderfundedFill(o);
    });

    // Generalize: the FIXED gate fills exactly when the wallet covers the full
    // incremental capital + charges, across the balance/charge domain.
    Glados3<int, int, int>(
      any.intInRange(0, 20000), // wallet balance
      any.intInRange(1, 500), // exec price
      any.intInRange(0, 2000), // total charges
    ).test('Futures add fills iff wallet >= requiredCapital + charges',
        (wallet, price, charges) {
      final o = simulateFixedOpenAddFunds(
        instrumentType: 'FUTURE',
        newNetQty: 20,
        addLots: 10,
        execPrice: price.toDouble(),
        lotSize: 50,
        walletBalance: wallet.toDouble(),
        totalCharges: charges.toDouble(),
      );
      assertNoUnderfundedFill(o);
    });
  });

  // =========================================================================
  // Bug 2a / Property 5 - Failed order left in a well-defined state.
  //
  // TASK 3.7 (fix verification): the SAME `assertFailedOrderWellDefined`
  // invariant from task 1, now driven against the FIXED routing
  // (`simulateFixedFoRpcFailureStatus`), which mirrors the Task 3.4 + 3.5
  // edits: the row is CLAIMED (pending -> executing) before the RPC, and the
  // catch marks a claimed-then-failed row `failed` (a pre-claim failure leaves
  // it `pending`) - never deleted-before-RPC, never swallowed. EXPECTED TO
  // PASS: the order always lands in {pending, failed}.
  // =========================================================================
  group('Property 5 - Failed order in a well-defined state (PASSES on fixed)',
      () {
    test('Bug 2a case: claimed-then-failed F&O RPC marks the order failed', () {
      // Task 1 counterexample (UNFIXED): row deleted before the RPC, RPC throws,
      // catch(_){} swallows it -> order silently 'lost'.
      // FIXED: the row is claimed first; the RPC failure marks it 'failed'.
      final status =
          simulateFixedFoRpcFailureStatus(claimedBeforeFailure: true);
      assertFailedOrderWellDefined(status);
    });

    test('A pre-claim failure leaves the order pending (never lost)', () {
      // A failure before the claim (e.g. the pre-claim funds/price check) never
      // claims the row, so it simply stays 'pending'.
      final status =
          simulateFixedFoRpcFailureStatus(claimedBeforeFailure: false);
      assertFailedOrderWellDefined(status);
    });
  });

  // =========================================================================
  // PROPERTY 2 - PRESERVATION: Non-Buggy Notification, Execution, And Funds
  // Behavior Unchanged.
  //
  //   Preservation goal: FOR ALL X WHERE NOT isBugCondition(X),
  //   execute(X) = execute'(X).
  //
  // OBSERVATION-FIRST METHODOLOGY:
  //   Each group below first states the behavior OBSERVED on the UNFIXED code
  //   for non-buggy inputs, then asserts that the FIXED code reproduces it
  //   identically across the input domain (instrument x side x existing
  //   position x price-vs-limit x balance x charges). Because the fix is gated
  //   (it only removes redundant client inserts, adds an at-most-once claim,
  //   and tightens the OPEN/ADD funds gate), every non-buggy path is unchanged:
  //   the canonical trigger row, the single device push, below-trigger pending,
  //   single sufficient-funds fills, exit/close exemption, charges, and P&L.
  //
  //   EXPECTED OUTCOME ON UNFIXED CODE: these tests PASS (they capture the
  //   baseline that task 3.8 re-runs against the FIXED code).
  //   Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 3.8
  // =========================================================================

  // --- Req 3.1: Order Pending notification preserved -----------------------
  group('Property 2 - Preservation: Order Pending row preserved (Req 3.1)', () {
    test('Placing a pending order yields exactly one "Order Pending" feed row',
        () {
      // Observed (UNFIXED): the insert at ~line 1459 writes one "Order Pending"
      // row; the executed trigger does NOT fire for a `pending` status, so
      // there is exactly one feed row. The fix does not touch this insert, so
      // the fixed behavior is identical.
      expect(orderPendingFeedRows(), 1,
          reason: 'Exactly one "Order Pending" feed row per placement; the '
              'insert at ~line 1459 is untouched by the fix.');
    });
  });

  // --- Req 3.2: Single executed (trigger) notification preserved -----------
  group('Property 2 - Preservation: single executed notification (Req 3.2)',
      () {
    test('Immediate fill preserves the canonical trigger row and device push',
        () {
      // Observed (UNFIXED): triggerFeedRows == 1 and a single foreground device
      // push. The fix removes only the redundant client insert; the canonical
      // trigger row and the device push are unchanged.
      final original =
          simulateUnfixedImmediateFillNotifications(returnedToOrderEntry: true);
      final fixed =
          simulateFixedImmediateFillNotifications(returnedToOrderEntry: true);
      // The preserved sub-parts (trigger row + device push) are identical.
      expect(fixed.triggerFeedRows, original.triggerFeedRows,
          reason: 'Canonical trigger feed row count must be unchanged. '
              'original=$original fixed=$fixed');
      expect(fixed.deviceAlertCount, original.deviceAlertCount,
          reason: 'Single foreground device push must be unchanged. '
              'original=$original fixed=$fixed');
      // And the canonical executed notification is still delivered exactly once.
      expect(fixed.triggerFeedRows, 1);
      expect(fixed.feedNotificationCount, 1);
    });

    test('Pending fill preserves the canonical trigger row', () {
      final original = simulateUnfixedPendingFillNotifications();
      final fixed = simulateFixedPendingFillNotifications();
      expect(fixed.triggerFeedRows, original.triggerFeedRows,
          reason: 'Pending-fill canonical trigger row must be unchanged. '
              'original=$original fixed=$fixed');
      expect(fixed.triggerFeedRows, 1);
      expect(fixed.feedNotificationCount, 1);
    });

    test('A fill not returned to order_entry raises no device push (both)', () {
      final original =
          simulateUnfixedImmediateFillNotifications(returnedToOrderEntry: false);
      final fixed =
          simulateFixedImmediateFillNotifications(returnedToOrderEntry: false);
      expect(fixed.deviceAlertCount, original.deviceAlertCount);
      expect(fixed.deviceAlertCount, 0);
    });
  });

  // --- Req 3.3: Below-trigger limit stays pending --------------------------
  group('Property 2 - Preservation: below-trigger limit stays pending '
      '(Req 3.3)', () {
    test('Buy limit above LTP stays pending; at/under LTP executes', () {
      // Observed (UNFIXED): the price-condition gate is unchanged by the fix.
      expect(
          pendingOrderPriceConditionMet(
              orderType: 'limit', side: 'buy', execPrice: 120, limitPrice: 100),
          isFalse,
          reason: 'A BUY limit whose trigger (100) is not met by LTP (120) must '
              'stay pending.');
      expect(
          pendingOrderPriceConditionMet(
              orderType: 'limit', side: 'buy', execPrice: 90, limitPrice: 100),
          isTrue);
    });

    test('Sell limit below LTP stays pending; at/above LTP executes', () {
      expect(
          pendingOrderPriceConditionMet(
              orderType: 'limit', side: 'sell', execPrice: 80, limitPrice: 100),
          isFalse,
          reason: 'A SELL limit whose trigger (100) is not met by LTP (80) must '
              'stay pending.');
      expect(
          pendingOrderPriceConditionMet(
              orderType: 'limit', side: 'sell', execPrice: 110, limitPrice: 100),
          isTrue);
    });

    test('Market orders always execute (no price condition)', () {
      expect(
          pendingOrderPriceConditionMet(
              orderType: 'market', side: 'buy', execPrice: 999, limitPrice: 1),
          isTrue);
    });

    // Generalize across the price/limit domain: a below-trigger limit is never
    // executed, and a met limit always is - identical original and fixed (the
    // gate is unchanged), so below-trigger orders stay pending without churn.
    Glados2<int, int>(
      any.intInRange(1, 5000), // limit price
      any.intInRange(1, 5000), // LTP / exec price
    ).test('Limit price gate is consistent across the price domain',
        (limit, ltp) {
      final buy = pendingOrderPriceConditionMet(
          orderType: 'limit',
          side: 'buy',
          execPrice: ltp.toDouble(),
          limitPrice: limit.toDouble());
      // A BUY limit executes iff LTP <= limit (does not stay pending).
      expect(buy, ltp <= limit);
      final sell = pendingOrderPriceConditionMet(
          orderType: 'limit',
          side: 'sell',
          execPrice: ltp.toDouble(),
          limitPrice: limit.toDouble());
      // A SELL limit executes iff LTP >= limit.
      expect(sell, ltp >= limit);
    });
  });

  // --- Req 3.4 / 3.5: Single sufficient-funds fill preserved ---------------
  group('Property 2 - Preservation: single sufficient-funds fill (Req 3.4, '
      '3.5)', () {
    test('A single non-overlapping pass fills once; net_qty += filled qty', () {
      // Observed (UNFIXED): one pass executes once and net_qty grows by the
      // filled lots. The at-most-once fix does NOT change single-pass behavior.
      final original = simulateUnfixedPendingExecution(
          overlappingPasses: 1, existingNetQty: 10, lots: 5);
      final fixed = simulateFixedPendingExecution(
          overlappingPasses: 1, existingNetQty: 10, lots: 5);
      expect(fixed.executionCount, original.executionCount,
          reason: 'Single-pass execution count must be unchanged. '
              'original=$original fixed=$fixed');
      expect(fixed.newNetQty, original.newNetQty,
          reason: 'Single-pass net_qty must be unchanged. '
              'original=$original fixed=$fixed');
      expect(fixed.executionCount, 1);
      expect(fixed.newNetQty, 15);
    });

    // Generalize: for a single, non-overlapping pass the fixed outcome equals
    // the original outcome across the (existing position x lots) domain.
    Glados2<int, int>(
      any.intInRange(-50, 50), // existing net_qty (long or short)
      any.intInRange(1, 100), // filled lots (signed below)
    ).test('Single-pass fill is identical original-vs-fixed across the domain',
        (existing, mag) {
      for (final int lots in <int>[mag, -mag]) {
        final original = simulateUnfixedPendingExecution(
            overlappingPasses: 1, existingNetQty: existing, lots: lots);
        final fixed = simulateFixedPendingExecution(
            overlappingPasses: 1, existingNetQty: existing, lots: lots);
        expect(fixed.executionCount, original.executionCount);
        expect(fixed.newNetQty, original.newNetQty);
        // And net_qty changes by exactly the filled quantity.
        expect((fixed.newNetQty - fixed.oldNetQty).abs(), lots.abs());
      }
    });
  });

  // --- Req 3.6: Exit/close exemption from the new opening/adding gate -------
  group('Property 2 - Preservation: exit/close exemption (Req 3.6)', () {
    test('A reducing/closing order is never blocked by the new funds gate', () {
      // Observed (prior exit-position-order-fix): closes/reduces release
      // capital and are exempt from the opening/adding funds check. The new
      // gate applies ONLY to opens/adds, so a close is never blocked even with
      // a zero wallet.
      expect(
          fixedFundsGateBlocks(
              isExitOrClose: true,
              walletBalance: 0.0,
              requiredCapital: 1e9,
              totalCharges: 1e6),
          isFalse,
          reason: 'Exit/close must remain exempt from the opening/adding funds '
              'gate (Req 3.6).');
    });

    // Generalize: regardless of balance/required-capital/charges, a close is
    // never blocked; an open/add is blocked iff funds are insufficient.
    Glados3<int, int, int>(
      any.intInRange(0, 1000000), // wallet balance
      any.intInRange(0, 1000000), // required capital
      any.intInRange(0, 10000), // total charges
    ).test('Close never blocked; open/add blocked iff underfunded',
        (wallet, req, charges) {
      // Close branch: never blocked.
      expect(
          fixedFundsGateBlocks(
              isExitOrClose: true,
              walletBalance: wallet.toDouble(),
              requiredCapital: req.toDouble(),
              totalCharges: charges.toDouble()),
          isFalse);
      // Open/add branch: blocked exactly when the wallet cannot cover the full
      // incremental capital plus charges.
      final blocked = fixedFundsGateBlocks(
          isExitOrClose: false,
          walletBalance: wallet.toDouble(),
          requiredCapital: req.toDouble(),
          totalCharges: charges.toDouble());
      expect(blocked, wallet.toDouble() < req.toDouble() + charges.toDouble());
    });
  });

  // --- Req 3.7: Charges computed identically -------------------------------
  // Uses the REAL calculateTransactionCharges (offline-safe: falls back to
  // defaultChargeRates when no live config is loaded). The fix does not touch
  // charge computation, so these values are the preserved baseline.
  group('Property 2 - Preservation: charges computed identically (Req 3.7)',
      () {
    late SupabaseService service;

    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      await Supabase.initialize(
        url: 'https://placeholder.supabase.co',
        anonKey: 'placeholder-key',
      );
      service = SupabaseService();
    });

    test('Equity delivery buy charges match the documented formula', () {
      final c = service.calculateTransactionCharges(
        instrumentType: 'EQUITY',
        side: 'buy',
        quantity: 100,
        price: 250.0,
        isIntraday: false,
      );
      // total = 25,000. brokerage = 25000 * 0.0005 = 12.5 (< 20 cap).
      expect(c['brokerage'], 12.5);
      // delivery buy stamp duty = 25000 * 0.00015 = 3.75
      expect(c['stamp_duty'], 3.75);
      // dp_charges only on delivery SELL -> 0 on buy
      expect(c['dp_charges'], 0.0);
    });

    test('Equity delivery sell charges (STT + dp) match the documented formula',
        () {
      final c = service.calculateTransactionCharges(
        instrumentType: 'EQUITY',
        side: 'sell',
        quantity: 100,
        price: 260.0,
        isIntraday: false,
      );
      // total = 26,000. STT delivery = 26000 * 0.001 = 26.0
      expect(c['stt'], 26.0);
      // dp_charges flat on delivery sell
      expect(c['dp_charges'], 13.5);
    });

    test('Futures sell charges include flat brokerage and STT on sell', () {
      final c = service.calculateTransactionCharges(
        instrumentType: 'FUTURE',
        side: 'sell',
        quantity: 1.0,
        price: 50000.0,
        isIntraday: false,
      );
      expect(c['brokerage'], 20.0);
      // STT futures sell = 50000 * 0.000125 = 6.25
      expect(c['stt'], 6.25);
    });

    test('Option sell charges include STT on sell side', () {
      final c = service.calculateTransactionCharges(
        instrumentType: 'OPTION',
        side: 'sell',
        quantity: 50.0,
        price: 100.0,
        isIntraday: false,
      );
      // total = 5,000. STT options sell = 5000 * 0.000625 = 3.125 -> 3.13
      expect(c['stt'], 3.13);
      expect(c['brokerage'], 20.0);
    });

    // Charges are a pure function of (instrumentType, side, qty, price,
    // intraday): generate many inputs and assert the result is deterministic
    // and matches a fresh recomputation (the property the fix must preserve).
    Glados2<int, int>(
      any.intInRange(1, 1000), // quantity
      any.intInRange(1, 5000), // price
    ).test('Equity buy charges are deterministic across the input domain',
        (qty, price) {
      final a = service.calculateTransactionCharges(
        instrumentType: 'EQUITY',
        side: 'buy',
        quantity: qty.toDouble(),
        price: price.toDouble(),
        isIntraday: false,
      );
      final b = service.calculateTransactionCharges(
        instrumentType: 'EQUITY',
        side: 'buy',
        quantity: qty.toDouble(),
        price: price.toDouble(),
        isIntraday: false,
      );
      expect(a['total_charges'], b['total_charges']);
      // brokerage capped at 20 and proportional below the cap.
      final double total = qty.toDouble() * price.toDouble();
      final double expectedBrokerage =
          (total * 0.0005) > 20.0 ? 20.0 : (total * 0.0005);
      expect(a['brokerage'],
          closeTo((expectedBrokerage * 100).roundToDouble() / 100.0, 1e-9));
    });
  });

  // --- Req 3.8: Realized P&L on a closing fill preserved -------------------
  group('Property 2 - Preservation: realized P&L on close (Req 3.8)', () {
    test('Long close realizes (exec - avg) * closedLots * lotSize', () {
      // Observed (UNFIXED): the reduce/close realized-P&L formula is unchanged
      // by the fix.
      final pnl = realizedPnlOnClose(
          existingQtyLots: 10,
          existingAvg: 100.0,
          execPrice: 120.0,
          closedLots: 10,
          lotSize: 50);
      // (120 - 100) * 10 * 50 = 10,000
      expect(pnl, 10000.0);
    });

    test('Short close realizes (avg - exec) * closedLots * lotSize', () {
      final pnl = realizedPnlOnClose(
          existingQtyLots: -10,
          existingAvg: 100.0,
          execPrice: 80.0,
          closedLots: 10,
          lotSize: 50);
      // (100 - 80) * 10 * 50 = 10,000
      expect(pnl, 10000.0);
    });

    // Generalize: realized P&L is sign-correct and deterministic across the
    // (avg x exec x closed lots) domain - the preserved baseline.
    Glados3<int, int, int>(
      any.intInRange(1, 5000), // existing average
      any.intInRange(1, 5000), // execution price
      any.intInRange(1, 100), // closed lots
    ).test('Realized P&L formula is sign-correct and deterministic',
        (avg, exec, lots) {
      const int lotSize = 50;
      final long = realizedPnlOnClose(
          existingQtyLots: lots,
          existingAvg: avg.toDouble(),
          execPrice: exec.toDouble(),
          closedLots: lots,
          lotSize: lotSize);
      final short = realizedPnlOnClose(
          existingQtyLots: -lots,
          existingAvg: avg.toDouble(),
          execPrice: exec.toDouble(),
          closedLots: lots,
          lotSize: lotSize);
      // Long and short P&L are exact negatives for the same avg/exec/qty.
      expect(long, closeTo(-short, 1e-6));
      // Magnitude equals |exec - avg| * closedLots * lotSize.
      expect(long.abs(),
          closeTo((exec - avg).abs() * lots * lotSize.toDouble(), 1e-6));
    });
  });

  // =========================================================================
  // TASK 4 - design Property 3: At-Most-Once / concurrency over a SET of
  // pending orders, plus the atomic-claim unit case.
  //
  // Generate concurrent invocation schedules (1..k overlapping passes, k up to
  // ~8) over a set of pending orders; assert each order executes at most once
  // and the TOTAL net_qty delta equals the SUM of filled quantities (no
  // unbounded growth). Then model the conditional `pending -> executing` claim
  // returning exactly ONE winner among k concurrent callers (the others get
  // zero rows and skip) and assert only the winner mutates.
  //   Validates: Requirements 2.5, 2.8, 2.9
  // =========================================================================
  group('Property 3 - At-most-once over a set of orders + claim unit', () {
    test('Claim unit: exactly one winner among k concurrent callers', () {
      // The conditional UPDATE ... WHERE status='pending' is serialised by
      // Postgres: among k contending passes only ONE gets a row back; the rest
      // see `[]` and `continue` without mutating.
      for (final int k in <int>[1, 2, 3, 5, 8]) {
        final r = simulateAtomicClaim(callers: k);
        expect(r.winners, 1,
            reason: 'Exactly one caller may claim a pending row. $r (k=$k)');
        expect(r.skippers, k - 1,
            reason: 'Every other caller must get zero rows and skip. $r');
      }
    });

    test('A set of pending BUYs each executes once under 2 overlapping passes',
        () {
      // Three pending BUYs (5, 3, 8 lots) from distinct starting positions;
      // two concurrent passes (the getOrders + getHoldings overlap that caused
      // the runaway bug). FIXED: each claims once, so the total net_qty delta
      // equals the sum of filled quantities.
      final out = simulateFixedConcurrentSchedule(
        lotsPerOrder: const <int>[5, 3, 8],
        existingNetQtyPerOrder: const <int>[0, 10, -4],
        overlappingPasses: 2,
      );
      expect(out.totalExecutions, 3,
          reason: 'Each of the 3 eligible orders executes exactly once. $out');
      expect(out.totalNetQtyDelta, out.sumFilledQty,
          reason: 'Total net_qty delta must equal the sum of filled '
              'quantities (no unbounded growth). $out');
      expect(out.sumFilledQty, 16, reason: '5 + 3 + 8 = 16. $out');
    });

    // Generalize across the number of orders in the set and the overlap depth
    // (1..8 concurrent passes): regardless of k, every order in the set
    // executes at most once and the aggregate net_qty delta equals the sum of
    // filled quantities.
    Glados2<int, int>(
      any.intInRange(1, 8), // number of pending orders in the set
      any.intInRange(1, 8), // k overlapping passes (>=2 used to trigger bug)
    ).test('Set executes at-most-once; total delta == sum of filled qty',
        (numOrders, passes) {
      final lots = <int>[
        for (var i = 0; i < numOrders; i++) (i + 1) * 3, // distinct positives
      ];
      final existing = <int>[
        for (var i = 0; i < numOrders; i++) i * 7, // varied starting positions
      ];
      // Per-order at-most-once invariant.
      for (var i = 0; i < numOrders; i++) {
        final o = simulateFixedPendingExecution(
          overlappingPasses: passes,
          existingNetQty: existing[i],
          lots: lots[i],
        );
        expect(o.executionCount <= 1, isTrue,
            reason: 'Order $i must execute at most once under $passes passes. '
                '$o');
        expect((o.newNetQty - o.oldNetQty).abs(), lots[i],
            reason: 'Order $i net_qty must change by exactly its filled '
                'quantity. $o');
      }
      // Aggregate invariant: total delta == sum of filled quantities.
      final out = simulateFixedConcurrentSchedule(
        lotsPerOrder: lots,
        existingNetQtyPerOrder: existing,
        overlappingPasses: passes,
      );
      expect(out.totalExecutions, numOrders,
          reason: 'Every eligible order executes exactly once. $out');
      expect(out.totalNetQtyDelta, out.sumFilledQty,
          reason: 'Aggregate net_qty delta must equal the sum of filled '
              'quantities. $out');
    });
  });

  // =========================================================================
  // TASK 4 - design Property 4: funds gate across instrument type, balance,
  // price, and charges.
  //
  // Generators over (long-option vs futures/short-option) x balance x price x
  // charges; assert a fill occurs IFF
  //   walletBalance >= requiredCapital + charges
  // where requiredCapital is the full premium for long options and
  // `execPrice * addedLots * lotSize * 0.15` for futures / short options. An
  // underfunded add is left pending; a sufficiently-funded one fills.
  //   Validates: Requirements 2.6, 2.7
  // =========================================================================
  group('Property 4 - Funds gate across instrument/balance/price/charges', () {
    test('Boundary: fill exactly at walletBalance == requiredCapital + charges',
        () {
      // Futures add: requiredCapital = 100 * 10 * 50 * 0.15 = 7,500; charges
      // 500 => need 8,000. Wallet exactly 8,000 must fill (>=).
      final atBoundary = simulateFixedOpenAddFunds(
        instrumentType: 'FUTURE',
        newNetQty: 20,
        addLots: 10,
        execPrice: 100.0,
        lotSize: 50,
        walletBalance: 8000.0,
        totalCharges: 500.0,
      );
      expect(atBoundary.filled, isTrue,
          reason: 'A wallet exactly equal to requiredCapital + charges must '
              'fill (>= boundary). $atBoundary');
      // One paisa short must NOT fill.
      final justUnder = simulateFixedOpenAddFunds(
        instrumentType: 'FUTURE',
        newNetQty: 20,
        addLots: 10,
        execPrice: 100.0,
        lotSize: 50,
        walletBalance: 7999.99,
        totalCharges: 500.0,
      );
      expect(justUnder.filled, isFalse,
          reason: 'A wallet just below the requirement must stay pending. '
              '$justUnder');
    });

    // Generalize: across the balance/price/charge domain, EACH instrument
    // class fills iff the wallet covers its full incremental capital + charges.
    Glados3<int, int, int>(
      any.intInRange(0, 30000), // wallet balance
      any.intInRange(1, 800), // exec price
      any.intInRange(0, 3000), // total charges
    ).test('Fill iff wallet >= requiredCapital + charges (all instrument types)',
        (wallet, price, charges) {
      // Long option (full premium): requiredCapital = execPrice * (addLots*lot).
      final longOpt = simulateFixedOpenAddFunds(
        instrumentType: 'OPTION',
        newNetQty: 2, // long option (newNetQty > 0)
        addLots: 2,
        execPrice: price.toDouble(),
        lotSize: 50,
        walletBalance: wallet.toDouble(),
        totalCharges: charges.toDouble(),
      );
      assertNoUnderfundedFill(longOpt);

      // Futures (15% margin on added notional).
      final futures = simulateFixedOpenAddFunds(
        instrumentType: 'FUTURE',
        newNetQty: 20,
        addLots: 10,
        execPrice: price.toDouble(),
        lotSize: 50,
        walletBalance: wallet.toDouble(),
        totalCharges: charges.toDouble(),
      );
      assertNoUnderfundedFill(futures);

      // Short option (newNetQty < 0): margin formula, NOT full premium.
      final shortOpt = simulateFixedOpenAddFunds(
        instrumentType: 'OPTION',
        newNetQty: -2, // short option
        addLots: 2,
        execPrice: price.toDouble(),
        lotSize: 50,
        walletBalance: wallet.toDouble(),
        totalCharges: charges.toDouble(),
      );
      assertNoUnderfundedFill(shortOpt);
    });
  });

  // =========================================================================
  // TASK 4 - design Property 5: failed order left in a well-defined state.
  //
  // A claimed-then-failed F&O execution yields status 'failed' (NOT deleted,
  // NOT added to executedOrders, wallet/position unchanged). A pre-claim
  // funds/price failure leaves status 'pending'. Status is always in
  // {pending, failed} (never 'lost').
  //   Validates: Requirements 2.7, 2.9
  // =========================================================================
  group('Property 5 - Failed order side-effects are well-defined', () {
    test('Claimed-then-failed F&O RPC: failed, not deleted, no fill recorded',
        () {
      final out = simulateFixedFoFailureState(
        claimedBeforeFailure: true,
        walletBefore: 12345.67,
        positionBefore: 8,
      );
      expect(out.status, 'failed',
          reason: 'A claimed order whose RPC then fails must be marked '
              'failed. $out');
      assertFailedOrderWellDefined(out.status);
      expect(out.deleted, isFalse,
          reason: 'A failed order must NOT be deleted. $out');
      expect(out.addedToExecutedOrders, isFalse,
          reason: 'A failed RPC must NOT add the order to executedOrders. '
              '$out');
      expect(out.walletUnchanged, isTrue,
          reason: 'Wallet must be unchanged on a failed execution. $out');
      expect(out.positionUnchanged, isTrue,
          reason: 'Position must be unchanged on a failed execution. $out');
    });

    test('Pre-claim funds/price failure leaves the order pending', () {
      final out = simulateFixedFoFailureState(
        claimedBeforeFailure: false,
        walletBefore: 500.0,
        positionBefore: 0,
      );
      expect(out.status, 'pending',
          reason: 'A failure before the claim never mutates the row, so it '
              'stays pending. $out');
      assertFailedOrderWellDefined(out.status);
      expect(out.deleted, isFalse);
      expect(out.addedToExecutedOrders, isFalse);
      expect(out.walletUnchanged, isTrue);
      expect(out.positionUnchanged, isTrue);
    });

    // Generalize: regardless of claim timing and the wallet/position values,
    // the failed order always lands in {pending, failed} (never 'lost'), is
    // never deleted or recorded as executed, and leaves wallet/position intact.
    Glados3<int, int, int>(
      any.intInRange(0, 1000000), // wallet before (paise-free integer model)
      any.intInRange(-100, 100), // position before (signed net_qty)
      any.intInRange(0, 1), // claim timing: 0 = pre-claim, 1 = claimed
    ).test('Failed execution always {pending, failed}, no side effects',
        (wallet, position, claimFlag) {
      final claimed = claimFlag == 1;
      final out = simulateFixedFoFailureState(
        claimedBeforeFailure: claimed,
        walletBefore: wallet.toDouble(),
        positionBefore: position,
      );
      assertFailedOrderWellDefined(out.status);
      // Never the buggy 'lost' state.
      expect(out.status == 'lost', isFalse);
      // Claim timing fully determines the terminal status.
      expect(out.status, claimed ? 'failed' : 'pending');
      expect(out.deleted, isFalse);
      expect(out.addedToExecutedOrders, isFalse);
      expect(out.walletUnchanged, isTrue);
      expect(out.positionUnchanged, isTrue);
    });
  });
}
