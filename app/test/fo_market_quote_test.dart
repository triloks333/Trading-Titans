import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/services/market_service.dart';

void main() {
  group('MarketService.parseDerivative', () {
    test('parses compact NSE futures (e.g. RELIANCE26DECFUT, RELIANCE26NOVFUT)', () {
      final decFut = MarketService.parseDerivative('RELIANCE26DECFUT');
      expect(decFut, isNotNull);
      expect(decFut!.isDerivative, isTrue);
      expect(decFut.type, 'FUTURE');
      expect(decFut.underlying, 'RELIANCE');
      expect(decFut.expiryDate, contains('2026-12-'));

      final novFut = MarketService.parseDerivative('NSE:RELIANCE26NOVFUT');
      expect(novFut, isNotNull);
      expect(novFut!.isDerivative, isTrue);
      expect(novFut.type, 'FUTURE');
      expect(novFut.underlying, 'RELIANCE');
      expect(novFut.expiryDate, contains('2026-11-'));

      final octFut = MarketService.parseDerivative('RELIANCE26OCTFUT');
      expect(octFut, isNotNull);
      expect(octFut!.type, 'FUTURE');
      expect(octFut.underlying, 'RELIANCE');
      expect(octFut.expiryDate, contains('2026-10-'));
    });

    test('parses compact NSE options (e.g. RELIANCE26DEC640CE, RELIANCE26DEC1000PE)', () {
      final ceOpt = MarketService.parseDerivative('RELIANCE26DEC640CE');
      expect(ceOpt, isNotNull);
      expect(ceOpt!.isDerivative, isTrue);
      expect(ceOpt.type, 'OPTION');
      expect(ceOpt.underlying, 'RELIANCE');
      expect(ceOpt.strikePrice, 640.0);
      expect(ceOpt.optionType, 'CE');
      expect(ceOpt.expiryDate, contains('2026-12-'));

      final peOpt = MarketService.parseDerivative('NSE:RELIANCE26DEC1000PE');
      expect(peOpt, isNotNull);
      expect(peOpt!.type, 'OPTION');
      expect(peOpt.underlying, 'RELIANCE');
      expect(peOpt.strikePrice, 1000.0);
      expect(peOpt.optionType, 'PE');
    });

    test('parses space-separated and hyphenated formats', () {
      final spaceFut = MarketService.parseDerivative('RELIANCE OCT FUT');
      expect(spaceFut, isNotNull);
      expect(spaceFut!.type, 'FUTURE');
      expect(spaceFut.underlying, 'RELIANCE');

      final hypOpt = MarketService.parseDerivative('RELIANCE-2026-10-27-3125-CE');
      expect(hypOpt, isNotNull);
      expect(hypOpt!.type, 'OPTION');
      expect(hypOpt.underlying, 'RELIANCE');
      expect(hypOpt.strikePrice, 3125.0);
      expect(hypOpt.optionType, 'CE');
      expect(hypOpt.expiryDate, '2026-10-27');
    });

    test('returns null for normal cash equities', () {
      expect(MarketService.parseDerivative('RELIANCE'), isNull);
      expect(MarketService.parseDerivative('NSE:TCS-EQ'), isNull);
      expect(MarketService.parseDerivative('BTC'), isNull);
    });
  });
}
