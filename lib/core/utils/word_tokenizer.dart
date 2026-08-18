/// A span of text produced by [WordTokenizer].
///
/// Each [TokenSpan] is either a **word** token (letters, digits, apostrophes,
/// hyphens) or a **separator** token (whitespace, punctuation, etc.).
class TokenSpan {
  /// The raw text of this span.
  final String text;

  /// `true` when this span represents a word; `false` for separators
  /// (whitespace, punctuation, etc.).
  final bool isWord;

  /// Creates an immutable [TokenSpan].
  const TokenSpan({
    required this.text,
    required this.isWord,
  });

  @override
  String toString() => 'TokenSpan("$text", isWord: $isWord)';
}

/// Splits a subtitle line (or any text) into an ordered list of [TokenSpan]s.
///
/// Word tokens consist of sequences of word characters, apostrophes, and
/// hyphens (`[\w'-]+`). Everything else is classified as a separator token.
/// Concatenating all [TokenSpan.text] values reproduces the original input
/// exactly.
///
/// Example:
/// ```dart
/// final spans = WordTokenizer.tokenize("Hello, world!");
/// // [TokenSpan("Hello", isWord: true),
/// //  TokenSpan(", ",    isWord: false),
/// //  TokenSpan("world", isWord: true),
/// //  TokenSpan("!",     isWord: false)]
/// ```
class WordTokenizer {
  // Private constructor — this class is not meant to be instantiated.
  WordTokenizer._();

  /// Pattern that alternates between word tokens (group 1) and separator
  /// tokens (group 2). Every character in the input is covered by exactly one
  /// of the two groups.
  ///
  /// Includes Persian / Arabic Unicode blocks:
  ///   \u0600-\u06FF  Arabic & Persian main block
  ///   \u0750-\u077F  Arabic Supplement
  ///   \uFB50-\uFDFF  Arabic Presentation Forms-A
  ///   \uFE70-\uFEFF  Arabic Presentation Forms-B
  ///   \u200C         Zero-Width Non-Joiner (used between Persian morphemes)
  static final RegExp _pattern = RegExp(
    r"([\w\u0600-\u06FF\u0750-\u077F\uFB50-\uFDFF\uFE70-\uFEFF\u200C'\-]+)"
    r"|([^\w\u0600-\u06FF\u0750-\u077F\uFB50-\uFDFF\uFE70-\uFEFF\u200C'\-]+)",
  );

  /// Tokenizes [input] into a list of [TokenSpan]s.
  ///
  /// Returns an empty list when [input] is empty.
  static List<TokenSpan> tokenize(String input) {
    if (input.isEmpty) return const [];

    // Replace ASS break tags (\N, \n, \h) and raw line breaks/tabs with spaces
    final sanitizedInput = input.replaceAll(RegExp(r'(\\N|\\n|\\h|[\r\n\t])'), ' ');

    final List<TokenSpan> spans = [];

    for (final match in _pattern.allMatches(sanitizedInput)) {
      if (match.group(1) != null) {
        spans.add(TokenSpan(text: match.group(1)!, isWord: true));
      } else if (match.group(2) != null) {
        spans.add(TokenSpan(text: match.group(2)!, isWord: false));
      }
    }

    return spans;
  }
}
