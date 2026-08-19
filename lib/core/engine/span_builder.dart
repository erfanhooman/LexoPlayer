import 'package:lexo_player/core/engine/mwe_fast.dart';
import 'package:lexo_player/core/engine/tokenizer.dart';
import 'package:lexo_player/core/engine/wsd_engine.dart';
import 'package:lexo_player/core/models/engine_output.dart';

/// Extracts top 3 Persian translations from WSD senses in rank order.
///
/// Collects all distinct translations from context-ranked WSD senses,
/// assigns the first 3 to primary/secondary/tertiary, and the rest
/// to other_translation_fa.
PersianTranslations extractTop3FaTranslations(List<WsdCandidate> senses) {
  final allList = <String>[];
  final seen = <String>{};

  for (final sense in senses) {
    final faRaw = sense.translationFa;
    if (faRaw == null || faRaw.isEmpty) continue;

    final parts =
        faRaw.split(',').map((p) => p.trim()).where((p) => p.isNotEmpty);
    for (final p in parts) {
      if (seen.add(p)) {
        allList.add(p);
      }
    }
  }

  return PersianTranslations(
    primary: allList.isNotEmpty ? allList[0] : null,
    secondary: allList.length > 1 ? allList[1] : null,
    tertiary: allList.length > 2 ? allList[2] : null,
    other: allList.length > 3 ? allList.sublist(3) : [],
  );
}

/// Extracted Persian translations for a span.
class PersianTranslations {
  final String? primary;
  final String? secondary;
  final String? tertiary;
  final List<String> other;

  const PersianTranslations({
    this.primary,
    this.secondary,
    this.tertiary,
    this.other = const [],
  });
}

/// Builds hierarchical spans (MULTI_WORD_SPAN and SINGLE_WORD) from
/// detected MWEs and WSD results.
///
/// Port of `core/span_builder.py` from LexoEngine.
class HierarchicalSpanBuilder {
  /// Builds a list of hierarchical spans from the engine pipeline outputs.
  ///
  /// Character offsets in returned spans are relative to the target_sentence.
  List<SpanModel> buildSpans({
    required List<EngineTokenInfo> targetTokens,
    required int targetStartCharInWindow,
    required List<DetectedMwe> detectedMwes,
    required Map<int, WsdResult> wsdResultsByToken,
  }) {
    // Sort detected MWEs by span length descending (greedy longest match)
    final sortedMwes = List<DetectedMwe>.from(detectedMwes)
      ..sort((a, b) => b.phrase.length.compareTo(a.phrase.length));

    final spans = <SpanModel>[];
    final coveredTokenIndices = <int>{};
    var spanCounter = 1;

    // 1. Process Multi-Word Spans
    for (final mwe in sortedMwes) {
      final mweTokens = mwe.tokens;
      if (mweTokens.isEmpty) continue;

      // Check if any token is already covered
      final tokenIndices = mweTokens.map((t) => t.tokenIndex).toList();
      if (tokenIndices.any(coveredTokenIndices.contains)) continue;

      // Mark tokens as covered
      coveredTokenIndices.addAll(tokenIndices);

      // Compute character bounds relative to target sentence
      final startC = mweTokens.first.startChar - targetStartCharInWindow;
      final endC = mweTokens.last.endChar - targetStartCharInWindow;
      final text = mweTokens.map((t) => t.token).join(' ');

      // Build children sub-tokens with WSD definitions
      final children = <ChildSubToken>[];
      for (final t in mweTokens) {
        final wsdInfo = wsdResultsByToken[t.tokenIndex];
        final senses = wsdInfo?.senses ?? [];
        final faTop = extractTop3FaTranslations(senses);
        children.add(ChildSubToken(
          token: t.token,
          lemma: t.lemma,
          pos: t.pos.toUpperCase(),
          primaryTranslationFa: faTop.primary,
          secondaryTranslationFa: faTop.secondary,
          tertiaryTranslationFa: faTop.tertiary,
          otherTranslationFa: faTop.other,
          wsd: senses
              .map((s) => WsdSense(
                    rank: s.rank,
                    score: s.score,
                    definitionEn: s.definitionEn,
                    translationFa: s.translationFa,
                  ))
              .toList(),
        ));
      }

      // Validate category
      var category = mwe.category.toUpperCase();
      const validCategories = {
        'IDIOM',
        'PHRASAL_VERB',
        'SEMI_AUXILIARY',
        'COMPOUND_PREPOSITION',
        'MWE',
      };
      if (!validCategories.contains(category)) category = 'IDIOM';

      // Extract parent meaning translations
      final parentFaRaw = mwe.translationFa;
      final parentFaTop = parentFaRaw != null
          ? extractTop3FaTranslations([
              WsdCandidate(
                rank: 1,
                score: 1.0,
                definitionEn: '',
                translationFa: parentFaRaw,
              ),
            ])
          : const PersianTranslations();

      spans.add(SpanModel(
        spanId: 'span_${spanCounter.toString().padLeft(2, '0')}',
        type: SpanType.multiWordSpan,
        category: category,
        text: text,
        canonicalForm: mwe.canonicalForm,
        startChar: startC,
        endChar: endC,
        primaryTranslationFa: parentFaTop.primary,
        secondaryTranslationFa: parentFaTop.secondary,
        tertiaryTranslationFa: parentFaTop.tertiary,
        otherTranslationFa: parentFaTop.other,
        parentMeaning: ParentMeaning(
          definitionEn: mwe.definitionEn,
          translationFa: parentFaRaw,
          primaryTranslationFa: parentFaTop.primary,
          secondaryTranslationFa: parentFaTop.secondary,
          tertiaryTranslationFa: parentFaTop.tertiary,
          otherTranslationFa: parentFaTop.other,
          confidence: mwe.confidence,
          inflectionNote: mwe.inflectionNote,
          baseForm: mwe.baseForm,
        ),
        childrenSubTokens: children,
        inflectionNote: mwe.inflectionNote,
        baseForm: mwe.baseForm,
      ));
      spanCounter++;
    }

    // 2. Process Remaining Single-Word Spans
    for (final t in targetTokens) {
      if (coveredTokenIndices.contains(t.tokenIndex)) continue;

      // Skip punctuation and spaces
      if (t.spacyPos == 'PUNCT' || t.spacyPos == 'SPACE') continue;

      final wsdInfo = wsdResultsByToken[t.tokenIndex];
      final senses = wsdInfo?.senses ?? [];
      final faTop = extractTop3FaTranslations(senses);
      final startC = t.startChar - targetStartCharInWindow;
      final endC = t.endChar - targetStartCharInWindow;

      spans.add(SpanModel(
        spanId: 'span_${spanCounter.toString().padLeft(2, '0')}',
        type: SpanType.singleWord,
        category: t.pos.toUpperCase(),
        text: t.token,
        lemma: t.lemma,
        pos: t.pos.toUpperCase(),
        startChar: startC,
        endChar: endC,
        primaryTranslationFa: faTop.primary,
        secondaryTranslationFa: faTop.secondary,
        tertiaryTranslationFa: faTop.tertiary,
        otherTranslationFa: faTop.other,
        childrenSubTokens: const [],
        wsd: senses
            .map((s) => WsdSense(
                  rank: s.rank,
                  score: s.score,
                  definitionEn: s.definitionEn,
                  translationFa: s.translationFa,
                ))
            .toList(),
      ));
      spanCounter++;
    }

    // Sort all spans by start_char
    spans.sort((a, b) => a.startChar.compareTo(b.startChar));
    return spans;
  }
}
