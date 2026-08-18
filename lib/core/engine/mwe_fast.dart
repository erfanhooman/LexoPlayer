import 'package:lexo_player/core/engine/aho_corasick.dart';
import 'package:lexo_player/core/engine/tokenizer.dart';
import 'package:lexo_player/features/dictionary/data/unified_dictionary_repository.dart';

/// Intervening modifier words that can appear inside an idiom without
/// changing its meaning (e.g., "bite the proverbial bullet").
const Set<String> interveningModifiers = {
  'proverbial', 'metaphorical', 'literal', 'alleged', 'so-called',
  'famous', 'supposed', 'figurative', 'virtual', 'historical',
};

/// Redirect definition prefixes that indicate non-idiomatic entries.
const List<String> redirectPrefixes = [
  'ellipsis of',
  'alternative form of',
  'alternative spelling of',
  'misspelling of',
  'clipping of',
  'abbreviation of',
  'eye dialect',
  'archaic form of',
];

/// A detected multi-word expression from the fast MWE detector.
class DetectedMwe {
  final String phrase;
  final String canonicalForm;
  final String category;
  final String detectionMethod;
  final String? definitionEn;
  final String? translationFa;
  final double confidence;
  final String? inflectionNote;
  final String? baseForm;
  final List<EngineTokenInfo> tokens;

  const DetectedMwe({
    required this.phrase,
    required this.canonicalForm,
    required this.category,
    required this.detectionMethod,
    this.definitionEn,
    this.translationFa,
    this.confidence = 1.0,
    this.inflectionNote,
    this.baseForm,
    required this.tokens,
  });
}

/// Fast multi-word expression detector using Aho-Corasick pattern matching.
///
/// Port of `core/mwe_fast.py` from LexoEngine. Loads all idioms from the
/// database into an Aho-Corasick automaton for O(n) substring matching
/// on the normalized (lemmatized) sentence.
class FastMweDetector {
  final UnifiedDictionaryRepository _db;
  final AhoCorasick<String> _automaton = AhoCorasick();
  final Map<String, Map<String, dynamic>> _phraseMap = {};
  bool _isLoaded = false;

  FastMweDetector(this._db);

  bool get isLoaded => _isLoaded;

  /// Loads all idioms from the database into the Aho-Corasick automaton.
  ///
  /// Must be called once before [detect].
  Future<void> loadIdioms() async {
    _phraseMap.clear();
    _automaton.clear();
    _isLoaded = false;

    if (!_db.isReady) {
      print('FastMweDetector: Database not ready. Skipping idiom load.');
      return;
    }

    final idioms = await _db.getAllIdioms();
    int count = 0;

    for (final idiom in idioms) {
      final normPhrase = idiom.normalizedPhrase;
      if (normPhrase.isEmpty || normPhrase.split(' ').length < 2) continue;

      // Skip redirect definitions
      final defLower = idiom.definitionEn.toLowerCase();
      if (redirectPrefixes.any((prefix) => defLower.startsWith(prefix))) {
        continue;
      }

      if (!_phraseMap.containsKey(normPhrase)) {
        _phraseMap[normPhrase] = {
          'idiom_id': idiom.id,
          'phrase': idiom.phrase,
          'matched_idiom': idiom.phrase,
          'pos': idiom.pos.isNotEmpty ? idiom.pos : 'idiom',
          'definition_en': idiom.definitionEn,
          'translation_fa': idiom.translationFa,
        };
        _automaton.addWord(normPhrase, normPhrase);
        count++;
      }
    }

    if (count > 0) {
      _automaton.build();
      _isLoaded = true;
    }
    print('FastMweDetector: Loaded $count multi-word idioms into Aho-Corasick automaton.');
  }

  /// Detects multi-word expressions in [text] using the tokenized [tokens].
  ///
  /// Returns a list of [DetectedMwe] objects sorted by span length
  /// (longest first for greedy matching).
  List<DetectedMwe> detect(String text, List<EngineTokenInfo> tokens) {
    if (!_isLoaded) return const [];

    // Build normalized sentence from token lemmas
    final normalizedTokens = tokens.map((t) => t.lemma).toList();
    final normalizedSentence = normalizedTokens.join(' ');

    final matches = <DetectedMwe>[];

    // 1. Exact Aho-Corasick pattern match
    for (final match in _automaton.iter(normalizedSentence)) {
      final normPhrase = match.value;
      final endIndex = match.index;
      final startIndex = endIndex - normPhrase.length + 1;

      // Check word boundaries
      final isStartBound = startIndex == 0 ||
          normalizedSentence[startIndex - 1] == ' ';
      final isEndBound = endIndex == normalizedSentence.length - 1 ||
          normalizedSentence[endIndex + 1] == ' ';

      if (isStartBound && isEndBound) {
        final idiomInfo = _phraseMap[normPhrase];
        if (idiomInfo == null) continue;

        final phraseWords = normPhrase.split(' ');
        final matchedTokenRange = _findTokenRange(tokens, phraseWords);

        if (matchedTokenRange != null && matchedTokenRange.isNotEmpty) {
          // Guardrail: Simple 2-token DET + NOUN / DET + PROPN is NOT an MWE
          if (matchedTokenRange.length == 2) {
            final firstPos = matchedTokenRange[0].pos.toLowerCase();
            final secondPos = matchedTokenRange[1].pos.toLowerCase();
            if ((firstPos == 'det' || firstPos == 'determiner') &&
                (secondPos == 'noun' || secondPos == 'propn')) {
              continue;
            }
          }

          matches.add(DetectedMwe(
            phrase: idiomInfo['phrase'] as String,
            canonicalForm: idiomInfo['phrase'] as String,
            category: (idiomInfo['pos'] as String).toUpperCase(),
            detectionMethod: 'aho_corasick_pattern_match',
            definitionEn: idiomInfo['definition_en'] as String?,
            translationFa: idiomInfo['translation_fa'] as String?,
            confidence: 1.0,
            tokens: matchedTokenRange,
          ));
        }
      }
    }

    // 2. Modified / Intervening Modifier Matcher
    // (e.g., "bite the proverbial bullet" → "bite the bullet")
    if (matches.isEmpty) {
      final modifiedMatches = _detectModifiedPhrases(tokens);
      matches.addAll(modifiedMatches);
    }

    return matches;
  }

  /// Detects modified idioms where intervening modifiers have been inserted.
  ///
  /// Slides a window from size 8 down to 3, checking for intervening
  /// modifiers (adjectives, known modifier words) that can be stripped
  /// to reveal the underlying idiom.
  List<DetectedMwe> _detectModifiedPhrases(List<EngineTokenInfo> tokens) {
    final matches = <DetectedMwe>[];
    final n = tokens.length;

    for (int windowSize = (n < 8 ? n : 8); windowSize > 2; windowSize--) {
      for (int i = 0; i <= n - windowSize; i++) {
        final subTokens = tokens.sublist(i, i + windowSize);

        // Check if sub_tokens contains an intervening modifier
        final hasModifier = subTokens.skip(1).take(subTokens.length - 2).any(
            (t) =>
                interveningModifiers.contains(t.lemma) ||
                t.pos.toLowerCase() == 'adj');

        if (!hasModifier) continue;

        // Filter out intervening modifiers/adjectives to test underlying phrase
        final filteredLemmas = subTokens
            .where((t) => !interveningModifiers.contains(t.lemma))
            .map((t) => t.lemma)
            .toList();
        final candidateNorm = filteredLemmas.join(' ');

        if (_phraseMap.containsKey(candidateNorm)) {
          final idiomInfo = _phraseMap[candidateNorm]!;
          final phraseStr = subTokens.map((t) => t.token).join(' ');

          if (!isLengthCompatible(
              phraseStr, idiomInfo['phrase'] as String)) {
            continue;
          }

          matches.add(DetectedMwe(
            phrase: phraseStr,
            canonicalForm: idiomInfo['phrase'] as String,
            category: (idiomInfo['pos'] as String).toUpperCase(),
            detectionMethod: 'modified_pattern_match',
            definitionEn: idiomInfo['definition_en'] as String?,
            translationFa: idiomInfo['translation_fa'] as String?,
            confidence: 0.95,
            tokens: subTokens,
          ));
          return matches; // Return first match (greedy)
        }
      }
    }
    return matches;
  }

  /// Finds a contiguous range of tokens matching [phraseLemmas].
  List<EngineTokenInfo>? _findTokenRange(
      List<EngineTokenInfo> tokens, List<String> phraseLemmas) {
    final pLen = phraseLemmas.length;
    for (int i = 0; i <= tokens.length - pLen; i++) {
      final subLemmas = tokens.sublist(i, i + pLen).map((t) => t.lemma).toList();
      if (_listEquals(subLemmas, phraseLemmas)) {
        return tokens.sublist(i, i + pLen);
      }
    }
    return null;
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Checks if a span in text is compatible in length with the canonical idiom.
///
/// A modified/gappy idiom can be LONGER than the canonical idiom,
/// but should NEVER be significantly SHORTER.
bool isLengthCompatible(String spanText, String canonicalIdiomText) {
  final spanWords = spanText
      .toLowerCase()
      .split(' ')
      .where((w) => !{'.', ',', '!', '?'}.contains(w))
      .toList();
  final idiomWords = canonicalIdiomText
      .toLowerCase()
      .split(' ')
      .where((w) => !{'.', ',', '!', '?'}.contains(w))
      .toList();

  // Reject if span has fewer words than canonical idiom (-1 tolerance)
  if (spanWords.length < idiomWords.length - 1) {
    return false;
  }
  return true;
}
