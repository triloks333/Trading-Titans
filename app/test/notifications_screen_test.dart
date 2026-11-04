import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mobile/core/theme.dart';
import 'package:mobile/screens/main/notifications_screen.dart';

Map<String, dynamic> n(String? type, {String title = 'T', String body = '', Map<String, dynamic>? data}) =>
    {'action_type': type, 'title': title, 'body': body, 'action_data': data};

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'http://127.0.0.1:9', anonKey: 'notifications-test-key');
  });

  group('noticeKindOf maps every type the backend writes', () {
    test('chat, price, orders, rewards', () {
      expect(noticeKindOf(n('chat')), NoticeKind.chat);
      expect(noticeKindOf(n('price_alert')), NoticeKind.price);
      for (final t in ['order', 'order_pending', 'expiry', 'audit_hold']) {
        expect(noticeKindOf(n(t)), NoticeKind.orders, reason: t);
      }
      expect(noticeKindOf(n('reward')), NoticeKind.rewards);
      expect(noticeKindOf(n('guest_upgrade')), NoticeKind.rewards);
    });

    test('broadcasts sort by their button, then their wording', () {
      expect(noticeKindOf(n('broadcast', data: {'cta_route': 'league'})), NoticeKind.league);
      expect(noticeKindOf(n('custom', data: {'cta_route': '/blog'})), NoticeKind.news);
      expect(noticeKindOf(n('broadcast', title: 'Diwali sale ends tonight')), NoticeKind.diwali);
      expect(noticeKindOf(n('broadcast', body: 'Muhurat trading starts in 15 minutes')), NoticeKind.diwali);
      expect(noticeKindOf(n('broadcast', title: 'You climbed the league')), NoticeKind.league);
      expect(noticeKindOf(n('broadcast', title: 'App update')), NoticeKind.other);
    });

    test('Diwali wording wins even on a typed row', () {
      expect(noticeKindOf(n('reward', title: 'Diwali bonus credited')), NoticeKind.diwali);
    });
  });

  test('routes written with a leading slash still resolve', () {
    expect(normalizedRoute({'cta_route': '/chat'}), 'chat');
    expect(normalizedRoute({'cta_route': ' /Subscribe '}), 'subscribe');
    expect(ctaLabel({'cta_label': 'Open chat', 'cta_route': '/chat'}), 'Open chat');
  });

  test('noticeAge reads like the design', () {
    final now = DateTime.utc(2026, 11, 4, 12);
    String ago(Duration d) => noticeAge(now.subtract(d).toIso8601String(), now: now);
    expect(ago(const Duration(seconds: 20)), 'Just now');
    expect(ago(const Duration(minutes: 5)), '5m ago');
    expect(ago(const Duration(hours: 3)), '3h ago');
    expect(ago(const Duration(hours: 30)), 'Yesterday');
    expect(ago(const Duration(days: 3)), '3 days ago');
    expect(noticeAge(null), '');
  });

  test('filter tabs are exactly the design set, in order', () {
    expect(kNoticeKindLabels.values.toList(), ['All', 'Diwali', 'Chat', 'Price', 'Orders', 'League', 'Rewards', 'News']);
  });

  testWidgets('chips filter the list and mark-all-read is off with nothing unread', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.darkTheme, home: const NotificationsScreen()));
    await tester.pump(const Duration(milliseconds: 500));

    for (final label in kNoticeKindLabels.values) {
      expect(find.widgetWithText(ChoiceChip, label), findsOneWidget, reason: label);
    }
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Mark all read')).onPressed, isNull);
    expect(find.text("You're all caught up"), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Price'));
    await tester.pump();
    expect(find.text('No price notifications'), findsOneWidget);
  });
}
