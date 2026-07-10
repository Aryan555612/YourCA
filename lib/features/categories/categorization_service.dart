import '../../core/constants/app_categories.dart';

/// Singleton service for categorizing transactions by keyword matching.
/// Also accepts a user-provided correction map (from Firestore) for
/// merchant-level overrides.
class CategorizationService {
  CategorizationService._();
  static final CategorizationService instance = CategorizationService._();

  /// User-specific corrections loaded from Firestore.
  /// Key: lowercase merchant name, Value: category name.
  Map<String, String> _userCorrections = {};

  void loadUserCorrections(Map<String, String> corrections) {
    _userCorrections = corrections;
  }

  /// Categorize based on a text string (merchant name or bank narration).
  String categorize(String text) {
    if (text.isEmpty) return 'Other';

    final lower = text.toLowerCase().trim();

    // 1. Check user corrections first (highest priority)
    for (final entry in _userCorrections.entries) {
      if (lower.contains(entry.key)) return entry.value;
    }

    // 2. Check keyword lists
    for (final cat in AppCategories.all) {
      if (cat.name == 'Other') continue;
      for (final keyword in cat.keywords) {
        if (lower.contains(keyword)) return cat.name;
      }
    }

    return 'Other';
  }

  /// Returns category for a debit transaction — auto-selects Income for credits.
  String categorizeWithType(String text, {required bool isCredit}) {
    if (isCredit) return 'Income';
    return categorize(text);
  }
}
