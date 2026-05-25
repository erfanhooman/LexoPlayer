import 'package:porter_2_stemmer/porter_2_stemmer.dart';

/// Utility helpers for cleaning and stemming individual word tokens.
///
/// Uses the Porter 2 (Snowball) stemming algorithm to reduce English words
/// to their stem form, which improves dictionary lookup recall.
///
/// Example:
/// ```dart
/// StemmerUtils.cleanAndStem("Running!"); // → "run"
/// ```
class StemmerUtils {
  // Private constructor — this class is not meant to be instantiated.
  StemmerUtils._();

  /// Regex that matches every character that is **not** a word character
  /// (`[a-zA-Z0-9_]`), **not** an apostrophe, **not** a space, and **not** a hyphen.
  static final RegExp _nonWordExceptApostropheSpaceHyphen = RegExp(r"[^\w'\s-]");

  /// Removes non-word characters (except apostrophes, spaces, and hyphens)
  /// and lowercases [raw], then collapses multiple spaces into a single space.
  ///
  /// This is the first normalization step before stemming, ensuring that
  /// punctuation and casing do not interfere with dictionary lookups.
  ///
  /// ```dart
  /// StemmerUtils.cleanToken("Hello!"); // → "hello"
  /// StemmerUtils.cleanToken("it's");   // → "it's"
  /// StemmerUtils.cleanToken("able-bodied"); // → "able-bodied"
  /// ```
  static String cleanToken(String raw) {
    final cleaned = raw.replaceAll(_nonWordExceptApostropheSpaceHyphen, '').toLowerCase();
    return cleaned.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Returns the Porter 2 stem of [word].
  ///
  /// The input is expected to already be lowercased and cleaned; use
  /// [cleanToken] first if it has not been preprocessed.
  ///
  /// ```dart
  /// StemmerUtils.stem("running"); // → "run"
  /// ```
  static String stem(String word) {
    return word.stemPorter2();
  }

  /// Convenience method that cleans **and** stems [raw] in a single call.
  ///
  /// Equivalent to `stem(cleanToken(raw))`.
  ///
  /// ```dart
  /// StemmerUtils.cleanAndStem("Running!"); // → "run"
  /// ```
  static String cleanAndStem(String raw) {
    return stem(cleanToken(raw));
  }
}
