/// Helpers for Combined Reports company multi-select.
///
/// Never merges identities across companies. Selection is always validated
/// against the user's allowed company list before any fetch.
class CombinedCompanySelection {
  CombinedCompanySelection._();

  static const int minCompanies = 2;

  static String normalize(String? name) => (name ?? '').trim();

  /// Deduplicate, drop blanks / placeholders, sort for stable keys.
  static List<String> normalizeList(Iterable<String?> names) {
    final seen = <String>{};
    final out = <String>[];
    for (final raw in names) {
      final name = normalize(raw);
      if (name.isEmpty || name == 'No Company Linked') continue;
      if (seen.add(name)) out.add(name);
    }
    out.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return out;
  }

  /// Keep only selected names that are in [allowed] (after normalization).
  static List<String> validateSelection({
    required Iterable<String?> selected,
    required Iterable<String?> allowed,
  }) {
    final allowedSet = normalizeList(allowed).toSet();
    return normalizeList(selected).where(allowedSet.contains).toList();
  }

  static bool isReady(Iterable<String?> companies) =>
      normalizeList(companies).length >= minCompanies;

  /// Stable cache / screen key for a company set.
  static String selectionKey(Iterable<String?> companies) =>
      normalizeList(companies).join('|');
}
