import 'dart:typed_data';

/// Models for the unified `en_fa` dictionary database schema.
///
/// The new database has four tables:
/// - `words`: lemma, pos, sense_count, is_monosemous
/// - `senses`: word_id, sense_index, definition_en, translation_fa, vector_blob
/// - `idioms`: phrase, normalized_phrase, pos, definition_en, translation_fa, vector_blob, isolated_components_vec_blob
/// - `isolated_words`: lemma, isolated_vec_blob

class UnifiedWord {
  final int id;
  final String lemma;
  final String pos;
  final int senseCount;
  final bool isMonosemous;

  const UnifiedWord({
    required this.id,
    required this.lemma,
    required this.pos,
    required this.senseCount,
    required this.isMonosemous,
  });

  factory UnifiedWord.fromMap(Map<String, dynamic> map) {
    return UnifiedWord(
      id: map['id'] as int,
      lemma: map['lemma'] as String,
      pos: map['pos'] as String,
      senseCount: map['sense_count'] as int,
      isMonosemous: (map['is_monosemous'] as int) == 1,
    );
  }
}

class UnifiedSense {
  final int id;
  final int wordId;
  final int senseIndex;
  final String definitionEn;
  final String? translationFa;
  final Uint8List? vectorBlob;

  const UnifiedSense({
    required this.id,
    required this.wordId,
    required this.senseIndex,
    required this.definitionEn,
    this.translationFa,
    this.vectorBlob,
  });

  factory UnifiedSense.fromMap(Map<String, dynamic> map) {
    return UnifiedSense(
      id: map['id'] as int,
      wordId: map['word_id'] as int,
      senseIndex: map['sense_index'] as int,
      definitionEn: map['definition_en'] as String,
      translationFa: map['translation_fa'] as String?,
      vectorBlob: map['vector_blob'] as Uint8List?,
    );
  }
}

class UnifiedIdiom {
  final int id;
  final String phrase;
  final String normalizedPhrase;
  final String pos;
  final String definitionEn;
  final String? translationFa;
  final Uint8List? vectorBlob;
  final Uint8List? isolatedComponentsVecBlob;

  const UnifiedIdiom({
    required this.id,
    required this.phrase,
    required this.normalizedPhrase,
    required this.pos,
    required this.definitionEn,
    this.translationFa,
    this.vectorBlob,
    this.isolatedComponentsVecBlob,
  });

  factory UnifiedIdiom.fromMap(Map<String, dynamic> map) {
    return UnifiedIdiom(
      id: map['id'] as int,
      phrase: map['phrase'] as String,
      normalizedPhrase: map['normalized_phrase'] as String,
      pos: map['pos'] as String? ?? 'idiom',
      definitionEn: map['definition_en'] as String,
      translationFa: map['translation_fa'] as String?,
      vectorBlob: map['vector_blob'] as Uint8List?,
      isolatedComponentsVecBlob:
          map['isolated_components_vec_blob'] as Uint8List?,
    );
  }
}

class IsolatedWord {
  final int id;
  final String lemma;
  final Uint8List isolatedVecBlob;

  const IsolatedWord({
    required this.id,
    required this.lemma,
    required this.isolatedVecBlob,
  });

  factory IsolatedWord.fromMap(Map<String, dynamic> map) {
    return IsolatedWord(
      id: map['id'] as int,
      lemma: map['lemma'] as String,
      isolatedVecBlob: map['isolated_vec_blob'] as Uint8List,
    );
  }
}
