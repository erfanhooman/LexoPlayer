import 'dart:developer' as developer;

import 'package:lexo_player/core/engine/mwe_fast.dart' show isLengthCompatible;
import 'package:lexo_player/features/dictionary/data/unified_dictionary_repository.dart';

/// Structural stop words used for content-word coverage filtering.
const Set<String> structuralStopWords = {
  'the', 'a', 'an', 'in', 'of', 'to', 'under', 'at', 'for', 'on', 'with',
  'by', 'from', 'as', 'is', 'are', 'was', 'were', 'be', 'been', 'being',
  'and', 'or', 'but', 'so', 'it', 'this', 'that', 'these', 'those',
};

/// Explanation result for a detected idiom.
class IdiomExplanation {
  final String phrase;
  final String canonicalForm;
  final String category;
  final String detectionMethod;
  final String explanationSource;
  final String? definitionEn;
  final String? translationFa;
  final double confidence;
  final String? inflectionNote;
  final String? baseForm;

  const IdiomExplanation({
    required this.phrase,
    required this.canonicalForm,
    required this.category,
    required this.detectionMethod,
    required this.explanationSource,
    this.definitionEn,
    this.translationFa,
    this.confidence = 0.5,
    this.inflectionNote,
    this.baseForm,
  });
}

/// Represents parsed inflection redirect metadata.
class RedirectParseResult {
  final String inflectionNote;
  final String baseForm;

  const RedirectParseResult({
    required this.inflectionNote,
    required this.baseForm,
  });
}

final List<String> _inflectionPrefixes = [
  'simple past and past participle of',
  'simple past of',
  'past participle of',
  'past tense of',
  'present participle of',
  'third-person singular simple present indicative form of',
  'plural of',
  'inflection of',
  'alternative form of',
  'alternative spelling of',
  'misspelling of',
  'clipping of',
  'abbreviation of',
  'eye dialect of',
  'archaic form of',
];

RedirectParseResult? parseInflectionRedirect(String? definitionEn) {
  if (definitionEn == null || definitionEn.trim().isEmpty) return null;
  final defLower = definitionEn.trim().toLowerCase();

  for (final prefix in _inflectionPrefixes) {
    if (defLower.startsWith(prefix)) {
      final rawTarget = definitionEn.trim().substring(prefix.length).trim();
      var cleanTarget = rawTarget.replaceAll(RegExp(r'\.+$'), '').trim();
      final parenIdx = cleanTarget.indexOf('(');
      if (parenIdx != -1) {
        cleanTarget = cleanTarget.substring(0, parenIdx).trim();
      }

      if (cleanTarget.isNotEmpty) {
        return RedirectParseResult(
          inflectionNote: definitionEn.trim(),
          baseForm: cleanTarget,
        );
      }
    }
  }
  return null;
}

/// Looks up idiom explanations from the unified dictionary database.
///
/// Port of `core/idiom_explainer.py` from LexoEngine.
/// Pre-loads idiom cache for synchronous lookups during processing.
class IdiomExplainer {
  final UnifiedDictionaryRepository _db;
  final double confidenceThreshold;

  /// Pre-loaded idiom cache: normalized_phrase -> idiom data
  final Map<String, Map<String, dynamic>> _idiomCache = {};
  /// Secondary index: raw phrase (lowercased) -> idiom data
  final Map<String, Map<String, dynamic>> _phraseIndex = {};
  bool _isCacheLoaded = false;

  IdiomExplainer(this._db, {this.confidenceThreshold = 0.75});

  /// Pre-loads all idioms into memory for fast synchronous lookups.
  Future<void> loadCache({bool forceReload = false}) async {
    if (_isCacheLoaded && !forceReload) return;
    _idiomCache.clear();
    _phraseIndex.clear();
    _isCacheLoaded = false;
    final idioms = await _db.getAllIdioms();
    for (final idiom in idioms) {
      final norm = idiom.normalizedPhrase;
      final entry = {
        'phrase': idiom.phrase,
        'pos': idiom.pos,
        'definition_en': idiom.definitionEn,
        'translation_fa': idiom.translationFa,
      };
      if (norm.isNotEmpty) {
        _idiomCache[norm] = entry;
      }
      // Secondary index: also map raw phrase (lowercased) for OR query parity
      final rawKey = idiom.phrase.toLowerCase().trim();
      if (rawKey.isNotEmpty && !_phraseIndex.containsKey(rawKey)) {
        _phraseIndex[rawKey] = entry;
      }
    }
    _isCacheLoaded = true;
    developer.log('IdiomExplainer: Loaded ${_idiomCache.length} idioms into cache.',
        name: 'IdiomExplainer');
  }

  /// Explains a detected idiom by looking it up in the lexicon.
  ///
  /// Returns an [IdiomExplanation] with the definition and translation
  /// from the database, or a generic fallback if not found.
  IdiomExplanation explainIdiom({
    required String sentenceText,
    required String phrase,
    required String detectedMethod,
  }) {
    if (!_isCacheLoaded) {
      return _defaultExplanation(phrase, detectedMethod);
    }

    final matchedEntry = _searchLexicon(phrase);

    if (matchedEntry != null) {
      String? defEn = matchedEntry['definition_en'] as String?;
      String? transFa = matchedEntry['translation_fa'] as String?;
      String? inflectionNote;
      String? baseForm;

      final redirect = parseInflectionRedirect(defEn);
      if (redirect != null) {
        inflectionNote = redirect.inflectionNote;
        baseForm = redirect.baseForm;

        // Directly query cache for the base target phrase without strict span filters
        final baseEntry = _lookupRawCache(redirect.baseForm);
        if (baseEntry != null) {
          final baseDef = baseEntry['definition_en'] as String?;
          if (baseDef != null &&
              baseDef.isNotEmpty &&
              parseInflectionRedirect(baseDef) == null) {
            defEn = baseDef;
          }
          final baseTrans = baseEntry['translation_fa'] as String?;
          if (baseTrans != null && baseTrans.isNotEmpty) {
            transFa = baseTrans;
          }
        }
      }

      return IdiomExplanation(
        phrase: phrase,
        canonicalForm: matchedEntry['phrase'] as String,
        category: (matchedEntry['pos'] as String? ?? 'IDIOM').toUpperCase(),
        detectionMethod: detectedMethod,
        explanationSource: 'lexicon_database_match',
        definitionEn: defEn,
        translationFa: transFa,
        confidence: (matchedEntry['confidence'] as num).toDouble(),
        inflectionNote: inflectionNote,
        baseForm: baseForm,
      );
    }

    return _defaultExplanation(phrase, detectedMethod);
  }

  Map<String, dynamic>? _lookupRawCache(String phrase) {
    final norm = phrase.toLowerCase().trim();
    return _idiomCache[norm] ?? _phraseIndex[norm];
  }

  IdiomExplanation _defaultExplanation(String phrase, String detectedMethod) {
    return IdiomExplanation(
      phrase: phrase,
      canonicalForm: phrase,
      category: 'MWE',
      detectionMethod: detectedMethod,
      explanationSource: 'default_generic',
      definitionEn: "An idiomatic expression meaning non-literal phrase: '$phrase'.",
      translationFa: null,
      confidence: 0.50,
    );
  }

  /// Searches the lexicon cache for an idiom matching [phrase].
  /// Checks both normalized_phrase and raw phrase (matching Python's OR query).
  Map<String, dynamic>? _searchLexicon(String phrase) {
    final norm = phrase.toLowerCase().trim();

    // Look up by normalized_phrase first, then fall back to raw phrase.
    // This mirrors Python's: WHERE normalized_phrase = ? OR phrase = ?
    final idiom = _idiomCache[norm] ?? _phraseIndex[norm];
    if (idiom == null) return null;

    // Verify content word coverage
    final coverage = _verifyTokenCoverage(phrase, idiom['phrase'] as String);
    if (coverage < 0.60) return null;

    // Check POS structure compatibility
    if (!posStructureCompatible(phrase, idiom['pos'] as String)) return null;

    // Check length compatibility
    if (!isLengthCompatible(phrase, idiom['phrase'] as String)) return null;

    return {
      'phrase': idiom['phrase'],
      'pos': idiom['pos'],
      'definition_en': idiom['definition_en'],
      'translation_fa': idiom['translation_fa'],
      'confidence': 0.95,
    };
  }

  /// Calculates content-word coverage overlap ratio.
  double _verifyTokenCoverage(String inputPhrase, String candidateIdiom) {
    final inputWords = _extractContentWords(inputPhrase);
    final candidateWords = _extractContentWords(candidateIdiom);

    if (candidateWords.isEmpty) {
      return inputWords.isEmpty ? 1.0 : 0.0;
    }

    final overlap = inputWords.intersection(candidateWords);
    return overlap.length / candidateWords.length;
  }

  /// Extracts content words (excluding stop words, len >= 2).
  Set<String> _extractContentWords(String text) {
    final cleaned = text.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '');
    return cleaned.split(' ').where((w) =>
        !structuralStopWords.contains(w) && w.length >= 2).toSet();
  }

  /// Checks if the POS structure of the input phrase is compatible.
  bool posStructureCompatible(String inputPhrase, String candidatePos) {
    if (candidatePos.isEmpty || !candidatePos.toLowerCase().contains('verb')) {
      return true;
    }
    final words = inputPhrase.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '').split(' ').toSet();
    return words.intersection(structuralStopWords).length < words.length;
  }
}
