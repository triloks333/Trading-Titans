import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/widgets/live_price_text.dart';

Widget _host(double v) => Directionality(
      textDirection: TextDirection.ltr,
      child: LivePriceText('$v', value: v, style: const TextStyle(color: Color(0xFF000000))),
    );

Color? _textColor(WidgetTester t) => t.widget<Text>(find.byType(Text)).style?.color;

void main() {
  testWidgets('first build is calm, a new price flashes, then it settles', (t) async {
    await t.pumpWidget(_host(100));
    expect(_textColor(t), const Color(0xFF000000));

    await t.pumpWidget(_host(101));
    await t.pump(const Duration(milliseconds: 16));
    expect(_textColor(t), isNot(const Color(0xFF000000)));

    await t.pumpAndSettle();
    expect(_textColor(t), const Color(0xFF000000));
  });

  testWidgets('a rebuild with the same price does not flash', (t) async {
    await t.pumpWidget(_host(100));
    await t.pumpWidget(_host(100));
    await t.pump(const Duration(milliseconds: 16));
    expect(_textColor(t), const Color(0xFF000000));
  });
}
