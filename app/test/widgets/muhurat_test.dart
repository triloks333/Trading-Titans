import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/screens/main/muhurat_screen.dart';

void main() {
  test('countdown is coarse beyond a day and to the second inside one', () {
    expect(countdownLabel(const Duration(days: 3, hours: 4, minutes: 12)), '3d 04h 12m');
    expect(countdownLabel(const Duration(hours: 4, minutes: 2, seconds: 9)), '04h 02m 09s');
    expect(countdownLabel(const Duration(seconds: -5)), '00h 00m 00s');
  });

  test('IST label shifts UTC by 5:30', () {
    expect(istLabel(DateTime.utc(2026, 11, 8, 12, 30)), 'Sun 8 Nov · 6:00 PM IST');
  });
}
