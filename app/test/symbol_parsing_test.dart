// Full-coverage tests for FoInstrumentsService.extractUnderlying — the symbol
// parser that drives lot-size lookup. A regression here mis-resolves the
// underlying and breaks lot sizes / option pricing.

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/services/fo_instruments_service.dart';

void main() {
  group('extractUnderlying', () {
    test('strips NSE: prefix and -EQ suffix', () {
      expect(FoInstrumentsService.extractUnderlying('NSE:RELIANCE-EQ'), 'RELIANCE');
    });

    test('concatenated contract -> base before first digit', () {
      expect(FoInstrumentsService.extractUnderlying('NSE:RELIANCE26JUN700CE'), 'RELIANCE');
    });

    test('hyphen-separated option contract', () {
      expect(
        FoInstrumentsService.extractUnderlying('HDFCBANK-2026-06-25-760-CE'),
        'HDFCBANK',
      );
    });

    test('EQ-embedded hyphen option contract', () {
      expect(
        FoInstrumentsService.extractUnderlying('NSE:FEDERALBNK-EQ-2026-06-25-305-CE'),
        'FEDERALBNK',
      );
    });

    test('space-separated future', () {
      expect(FoInstrumentsService.extractUnderlying('HDFCBANK JUN FUT'), 'HDFCBANK');
    });

    test('index aliases map to canonical names', () {
      expect(FoInstrumentsService.extractUnderlying('^NSEI'), 'NIFTY');
      expect(FoInstrumentsService.extractUnderlying('NSEI'), 'NIFTY');
      expect(FoInstrumentsService.extractUnderlying('NIFTY50'), 'NIFTY');
      expect(FoInstrumentsService.extractUnderlying('^NSEBANK'), 'BANKNIFTY');
      expect(FoInstrumentsService.extractUnderlying('NSEBANK'), 'BANKNIFTY');
      expect(FoInstrumentsService.extractUnderlying('^BSESN'), 'SENSEX');
      expect(FoInstrumentsService.extractUnderlying('SENSEX'), 'SENSEX');
    });

    test('lowercase input is upper-cased', () {
      expect(FoInstrumentsService.extractUnderlying('reliance-eq'), 'RELIANCE');
    });

    test('plain equity symbol passes through', () {
      expect(FoInstrumentsService.extractUnderlying('TCS'), 'TCS');
    });

    test('BSE prefix stripped', () {
      expect(FoInstrumentsService.extractUnderlying('BSE:TATAMOTORS'), 'TATAMOTORS');
    });
  });
}
