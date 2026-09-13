import 'package:flutter_test/flutter_test.dart';
import 'package:kashiv_vault/core/fuzzy_match.dart';

void main() {
  test('global search tolerates useful typos without broad false matches', () {
    expect(fuzzyMatches('agreemnt', ['Vendor Agreement']), isTrue);
    expect(fuzzyMatches('gst', ['GST Certificate']), isTrue);
    expect(fuzzyMatches('passport', ['Quarterly Finance Report']), isFalse);
    expect(fuzzyMatches('', ['anything']), isTrue);
  });
}
