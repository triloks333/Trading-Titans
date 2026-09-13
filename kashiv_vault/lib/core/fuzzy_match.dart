/// Small typo-tolerant matcher for the on-device global search.
///
/// Scores exact/substring matches first, then a Dice coefficient over bigrams.
/// This avoids another dependency while remaining useful for short names.
double fuzzyScore(String query, String candidate) {
  final q = _normal(query);
  final c = _normal(candidate);
  if (q.isEmpty) return 1;
  if (c == q) return 1;
  if (c.contains(q)) return .9 - ((c.length - q.length) / c.length * .1);
  if (q.length < 2 || c.length < 2) return 0;

  final a = _bigrams(q);
  final b = _bigrams(c);
  var overlap = 0;
  final remaining = [...b];
  for (final gram in a) {
    final i = remaining.indexOf(gram);
    if (i >= 0) {
      overlap++;
      remaining.removeAt(i);
    }
  }
  return 2 * overlap / (a.length + b.length);
}

bool fuzzyMatches(String query, Iterable<String?> fields) =>
    fields.whereType<String>().any((value) => fuzzyScore(query, value) >= .38);

String _normal(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

List<String> _bigrams(String value) => [
  for (var i = 0; i < value.length - 1; i++) value.substring(i, i + 2),
];
