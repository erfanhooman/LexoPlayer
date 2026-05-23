/// The result of a dictionary lookup for a single word.
///
/// Contains an optional monolingual HTML definition (from `core_dict.db`) and
/// an optional localized translation (from `trans_dict.db`). Either, both, or
/// neither may be populated depending on the coverage of the underlying
/// dictionaries.
class DictionaryResult {
  /// The cleaned/stemmed word that was looked up.
  final String word;

  /// HTML definition from `core_dict.db` (target-to-target / monolingual).
  final String? htmlDefinition;

  /// Localized translation from `trans_dict.db` (target-to-native / bilingual).
  final String? localizedText;

  /// Whether a stemming fallback was used to find this result.
  ///
  /// When `true`, the exact form entered by the user did not match any
  /// dictionary entry and the stemmed form was used instead.
  final bool wasStemmed;

  /// Creates an immutable [DictionaryResult].
  const DictionaryResult({
    required this.word,
    this.htmlDefinition,
    this.localizedText,
    this.wasStemmed = false,
  });

  /// `true` when a monolingual HTML definition is available.
  bool get hasDefinition => htmlDefinition != null;

  /// `true` when a bilingual translation is available.
  bool get hasTranslation => localizedText != null;

  /// `true` when neither definition nor translation was found.
  bool get isEmpty => !hasDefinition && !hasTranslation;
}
