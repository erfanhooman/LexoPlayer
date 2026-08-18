import 'dart:typed_data';

/// Engine output for a processed subtitle line.
class EngineOutput {
  final int subtitleId;
  final String timestamp;
  final String targetSentence;
  final String slidingContextWindow;
  final double executionTimeMs;
  final List<SpanModel> hierarchicalSpans;

  const EngineOutput({
    required this.subtitleId,
    required this.timestamp,
    required this.targetSentence,
    required this.slidingContextWindow,
    required this.executionTimeMs,
    required this.hierarchicalSpans,
  });

  factory EngineOutput.fromJson(Map<String, dynamic> json) {
    return EngineOutput(
      subtitleId: json['subtitle_id'] as int,
      timestamp: json['timestamp'] as String,
      targetSentence: json['target_sentence'] as String,
      slidingContextWindow: json['sliding_context_window'] as String,
      executionTimeMs: (json['execution_time_ms'] as num).toDouble(),
      hierarchicalSpans: (json['hierarchical_spans'] as List<dynamic>)
          .map((e) => SpanModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'subtitle_id': subtitleId,
      'timestamp': timestamp,
      'target_sentence': targetSentence,
      'sliding_context_window': slidingContextWindow,
      'execution_time_ms': executionTimeMs,
      'hierarchical_spans': hierarchicalSpans.map((e) => e.toJson()).toList(),
    };
  }
}

enum SpanType { singleWord, multiWordSpan }

/// A span can be a single word or a multi-word expression (idiom, phrasal verb, etc.).
class SpanModel {
  final String spanId;
  final SpanType type;
  final String category;
  final String text;
  final String? canonicalForm;
  final String? lemma;
  final String? pos;
  final int startChar;
  final int endChar;
  final String? primaryTranslationFa;
  final String? secondaryTranslationFa;
  final String? tertiaryTranslationFa;
  final List<String> otherTranslationFa;
  final ParentMeaning? parentMeaning;
  final List<ChildSubToken> childrenSubTokens;
  final List<WsdSense> wsd;

  final String? inflectionNote;
  final String? baseForm;

  const SpanModel({
    required this.spanId,
    required this.type,
    required this.category,
    required this.text,
    this.canonicalForm,
    this.lemma,
    this.pos,
    required this.startChar,
    required this.endChar,
    this.primaryTranslationFa,
    this.secondaryTranslationFa,
    this.tertiaryTranslationFa,
    this.otherTranslationFa = const [],
    this.parentMeaning,
    this.childrenSubTokens = const [],
    this.wsd = const [],
    this.inflectionNote,
    this.baseForm,
  });

  bool get isMultiWord => type == SpanType.multiWordSpan;
  bool get isSingleWord => type == SpanType.singleWord;

  /// Whether this span contains real (non-fallback) data worth showing.
  ///
  /// A span is considered empty when:
  /// - It has no Persian translations at all, AND
  /// - Its WSD list is empty or contains only the generic placeholder sense
  ///   (i.e. `"Definition for '<word>' (<pos>)."`).
  bool get hasMeaningfulData {
    // Multi-word spans detected by Aho-Corasick always count as meaningful.
    if (isMultiWord) return true;

    final hasTranslations =
        (primaryTranslationFa?.isNotEmpty ?? false) ||
        (secondaryTranslationFa?.isNotEmpty ?? false) ||
        (tertiaryTranslationFa?.isNotEmpty ?? false) ||
        otherTranslationFa.isNotEmpty;
    if (hasTranslations) return true;

    // A WSD sense is meaningful if it is not just a generic placeholder
    // ("Definition for '<word>' (<pos>).") or if it has a translation.
    final hasRealWsd = wsd.any((sense) {
      final defLower = sense.definitionEn.toLowerCase().trim();
      final isPlaceholder = defLower.startsWith("definition for '") &&
          (defLower.endsWith(").") || defLower.endsWith(")"));
      return !isPlaceholder ||
          (sense.translationFa != null && sense.translationFa!.isNotEmpty);
    });

    return hasRealWsd;
  }

  factory SpanModel.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String;
    final type = typeStr == 'MULTI_WORD_SPAN'
        ? SpanType.multiWordSpan
        : SpanType.singleWord;

    return SpanModel(
      spanId: json['span_id'] as String,
      type: type,
      category: (json['category'] as String?) ??
          (json['pos'] as String?) ??
          (type == SpanType.multiWordSpan ? 'IDIOM' : 'WORD'),
      text: json['text'] as String,
      canonicalForm: json['canonical_form'] as String?,
      lemma: json['lemma'] as String?,
      pos: json['pos'] as String?,
      startChar: json['start_char'] as int,
      endChar: json['end_char'] as int,
      primaryTranslationFa: json['primary_translation_fa'] as String?,
      secondaryTranslationFa: json['secondary_translation_fa'] as String?,
      tertiaryTranslationFa: json['tertiary_translation_fa'] as String?,
      otherTranslationFa: (json['other_translation_fa'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      parentMeaning: json['parent_meaning'] != null
          ? ParentMeaning.fromJson(
              json['parent_meaning'] as Map<String, dynamic>)
          : null,
      childrenSubTokens: (json['children_sub_tokens'] as List<dynamic>?)
              ?.map((e) =>
                  ChildSubToken.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      wsd: (json['wsd'] as List<dynamic>?)
              ?.map((e) => WsdSense.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      inflectionNote: json['inflection_note'] as String?,
      baseForm: json['base_form'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'span_id': spanId,
      'type': type == SpanType.multiWordSpan
          ? 'MULTI_WORD_SPAN'
          : 'SINGLE_WORD',
      'category': category,
      'text': text,
      if (canonicalForm != null) 'canonical_form': canonicalForm,
      if (lemma != null) 'lemma': lemma,
      if (pos != null) 'pos': pos,
      'start_char': startChar,
      'end_char': endChar,
      'primary_translation_fa': primaryTranslationFa,
      'secondary_translation_fa': secondaryTranslationFa,
      'tertiary_translation_fa': tertiaryTranslationFa,
      'other_translation_fa': otherTranslationFa,
      if (parentMeaning != null) 'parent_meaning': parentMeaning!.toJson(),
      'children_sub_tokens':
          childrenSubTokens.map((e) => e.toJson()).toList(),
      'wsd': wsd.map((e) => e.toJson()).toList(),
      if (inflectionNote != null) 'inflection_note': inflectionNote,
      if (baseForm != null) 'base_form': baseForm,
    };
  }
}

/// Parent meaning for a multi-word span (idiom definition + translation).
class ParentMeaning {
  final String? definitionEn;
  final String? translationFa;
  final String? primaryTranslationFa;
  final String? secondaryTranslationFa;
  final String? tertiaryTranslationFa;
  final List<String> otherTranslationFa;
  final double confidence;
  final String? inflectionNote;
  final String? baseForm;

  const ParentMeaning({
    this.definitionEn,
    this.translationFa,
    this.primaryTranslationFa,
    this.secondaryTranslationFa,
    this.tertiaryTranslationFa,
    this.otherTranslationFa = const [],
    this.confidence = 1.0,
    this.inflectionNote,
    this.baseForm,
  });

  factory ParentMeaning.fromJson(Map<String, dynamic> json) {
    return ParentMeaning(
      definitionEn: json['definition_en'] as String?,
      translationFa: json['translation_fa'] as String?,
      primaryTranslationFa: json['primary_translation_fa'] as String?,
      secondaryTranslationFa: json['secondary_translation_fa'] as String?,
      tertiaryTranslationFa: json['tertiary_translation_fa'] as String?,
      otherTranslationFa: (json['other_translation_fa'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
      inflectionNote: json['inflection_note'] as String?,
      baseForm: json['base_form'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'definition_en': definitionEn,
      'translation_fa': translationFa,
      'primary_translation_fa': primaryTranslationFa,
      'secondary_translation_fa': secondaryTranslationFa,
      'tertiary_translation_fa': tertiaryTranslationFa,
      'other_translation_fa': otherTranslationFa,
      'confidence': confidence,
      if (inflectionNote != null) 'inflection_note': inflectionNote,
      if (baseForm != null) 'base_form': baseForm,
    };
  }
}

/// A child sub-token within a multi-word span.
class ChildSubToken {
  final String token;
  final String lemma;
  final String pos;
  final String? primaryTranslationFa;
  final String? secondaryTranslationFa;
  final String? tertiaryTranslationFa;
  final List<String> otherTranslationFa;
  final List<WsdSense> wsd;

  const ChildSubToken({
    required this.token,
    required this.lemma,
    required this.pos,
    this.primaryTranslationFa,
    this.secondaryTranslationFa,
    this.tertiaryTranslationFa,
    this.otherTranslationFa = const [],
    this.wsd = const [],
  });

  factory ChildSubToken.fromJson(Map<String, dynamic> json) {
    return ChildSubToken(
      token: json['token'] as String,
      lemma: json['lemma'] as String,
      pos: json['pos'] as String,
      primaryTranslationFa: json['primary_translation_fa'] as String?,
      secondaryTranslationFa: json['secondary_translation_fa'] as String?,
      tertiaryTranslationFa: json['tertiary_translation_fa'] as String?,
      otherTranslationFa: (json['other_translation_fa'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      wsd: (json['wsd'] as List<dynamic>?)
              ?.map((e) => WsdSense.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'token': token,
      'lemma': lemma,
      'pos': pos,
      'primary_translation_fa': primaryTranslationFa,
      'secondary_translation_fa': secondaryTranslationFa,
      'tertiary_translation_fa': tertiaryTranslationFa,
      'other_translation_fa': otherTranslationFa,
      'wsd': wsd.map((e) => e.toJson()).toList(),
    };
  }
}

/// A single word sense disambiguation candidate.
class WsdSense {
  final int rank;
  final double score;
  final String definitionEn;
  final String? translationFa;
  final String? inflectionNote;
  final String? baseForm;

  const WsdSense({
    required this.rank,
    required this.score,
    required this.definitionEn,
    this.translationFa,
    this.inflectionNote,
    this.baseForm,
  });

  factory WsdSense.fromJson(Map<String, dynamic> json) {
    return WsdSense(
      rank: json['rank'] as int,
      score: (json['score'] as num).toDouble(),
      definitionEn: json['definition_en'] as String,
      translationFa: json['translation_fa'] as String?,
      inflectionNote: json['inflection_note'] as String?,
      baseForm: json['base_form'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'rank': rank,
      'score': score,
      'definition_en': definitionEn,
      'translation_fa': translationFa,
      if (inflectionNote != null) 'inflection_note': inflectionNote,
      if (baseForm != null) 'base_form': baseForm,
    };
  }
}
