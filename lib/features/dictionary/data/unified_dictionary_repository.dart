import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

import 'package:lexo_player/core/database/database_service.dart';
import 'package:lexo_player/core/models/unified_dictionary.dart';

/// Repository that queries the single unified `en_fa` dictionary database.
///
/// Replaces the old DualDictionaryRepository. Handles word lookups, idiom
/// lookups, and vector retrieval for the WSD/MWE engine pipeline.
class UnifiedDictionaryRepository {
  final DatabaseService _dbService;
  Database? _db;
  String? _dbPath;

  UnifiedDictionaryRepository(this._dbService);

  bool get isReady => _db != null;

  /// Opens the unified dictionary at the given path.
  Future<void> openDatabase(String path) async {
    if (_dbPath != null && _dbPath != path) {
      await _dbService.closeDatabase(_dbPath!);
      _db = null;
    }

    _dbPath = path;

    if (File(path).existsSync()) {
      try {
        _db = await _dbService.getDatabaseByPath(path);
        developer.log(
          'UnifiedDictionaryRepository: Opened DB at $path',
          name: 'UnifiedDict',
        );
      } catch (e) {
        developer.log(
          'UnifiedDictionaryRepository: Failed to open DB: $e',
          name: 'UnifiedDict',
          level: 1000,
        );
      }
    } else {
      developer.log(
        'UnifiedDictionaryRepository: DB file not found at $path',
        name: 'UnifiedDict',
        level: 900,
      );
    }
  }

  /// Closes the database.
  Future<void> close() async {
    if (_dbPath != null) {
      await _dbService.closeDatabase(_dbPath!);
      _db = null;
      _dbPath = null;
    }
  }

  // ── Candidate Generation Helper ──────────────────────────────────────────

  Set<String> _buildWordCandidates(String lemma, String? token) {
    final candidates = <String>{};

    final inputs = <String>{
      lemma.toLowerCase().trim(),
      if (token != null && token.trim().isNotEmpty) token.toLowerCase().trim(),
    };

    for (final input in inputs) {
      if (input.isEmpty) continue;
      // 1. Raw input (e.g. "near-sighted", "well-known")
      candidates.add(input);

      // 2. Hyphen to space (e.g. "near sighted", "well known")
      if (input.contains('-')) {
        candidates.add(input.replaceAll('-', ' '));
      }

      // 3. Space to hyphen (e.g. "near-sighted")
      if (input.contains(' ')) {
        candidates.add(input.replaceAll(' ', '-'));
      }

      // 4. Remove all hyphens & spaces (e.g. "nearsighted", "wellknown")
      final solid = input.replaceAll(RegExp(r'[\s\-]'), '');
      if (solid.isNotEmpty) candidates.add(solid);

      // 5. Clean alphanumeric + apostrophe
      final clean = input.replaceAll(RegExp(r"[^\w']"), '');
      if (clean.isNotEmpty) candidates.add(clean);

      // 6. Stem variations if ending in -ed
      if (input.endsWith('ed')) {
        final stem = input.substring(0, input.length - 2);
        if (stem.isNotEmpty) {
          candidates.add(stem);
          if (!stem.endsWith('e')) candidates.add('${stem}e');
          if (stem.endsWith('i')) candidates.add('${stem.substring(0, stem.length - 1)}y');
        }
        if (input.contains('-')) {
          final parts = input.split('-');
          if (parts.last.endsWith('ed')) {
            final lastStem = parts.last.substring(0, parts.last.length - 2);
            final prefix = parts.sublist(0, parts.length - 1).join('-');
            candidates.add('$prefix-$lastStem');
            if (!lastStem.endsWith('e')) candidates.add('$prefix-${lastStem}e');
            if (lastStem.endsWith('i')) {
              candidates.add('$prefix-${lastStem.substring(0, lastStem.length - 1)}y');
            }
          }
        }
      }
    }

    return candidates;
  }

  // ── Word Lookups ─────────────────────────────────────────────────────────

  /// Look up a word by lemma, POS, and optional surface token, returning the Word row.
  Future<UnifiedWord?> lookupWord(String lemma, String pos, {String? token}) async {
    if (_db == null) return null;

    final candidates = _buildWordCandidates(lemma, token);
    final posLower = pos.toLowerCase();

    try {
      // 1. Try candidates with exact POS match
      if (posLower.isNotEmpty) {
        for (final cand in candidates) {
          final rows = await _db!.query(
            'words',
            where: 'lemma = ? AND pos = ?',
            whereArgs: [cand, posLower],
            limit: 1,
          );
          if (rows.isNotEmpty) return UnifiedWord.fromMap(rows.first);
        }
      }

      // 2. Try candidates with any POS
      for (final cand in candidates) {
        final rows = await _db!.query(
          'words',
          where: 'lemma = ?',
          whereArgs: [cand],
          limit: 1,
        );
        if (rows.isNotEmpty) return UnifiedWord.fromMap(rows.first);
      }
    } catch (e) {
      developer.log('lookupWord error: $e', name: 'UnifiedDict', level: 1000);
    }
    return null;
  }

  /// Fetch all senses for a word, ordered by sense_index.
  Future<List<UnifiedSense>> getSenses(int wordId) async {
    if (_db == null) return const [];
    try {
      final rows = await _db!.query(
        'senses',
        where: 'word_id = ?',
        whereArgs: [wordId],
        orderBy: 'sense_index ASC',
      );
      return rows.map((r) => UnifiedSense.fromMap(r)).toList();
    } catch (e) {
      developer.log('getSenses error: $e', name: 'UnifiedDict', level: 1000);
      return const [];
    }
  }

  /// Look up a word and return all its senses (convenience method).
  /// Falls back to checking idioms table if no word entry is found.
  Future<WordLookupResult?> lookupWordWithSenses(
      String lemma, String pos, {String? token}) async {
    final word = await lookupWord(lemma, pos, token: token);
    if (word != null) {
      final senses = await getSenses(word.id);
      if (senses.isNotEmpty) {
        return WordLookupResult(word: word, senses: senses);
      }
    }

    // Fallback: check idioms table for hyphenated/compound expressions
    final idiom = await lookupIdiom(token ?? lemma);
    if (idiom != null) {
      final dummyWord = UnifiedWord(
        id: idiom.id,
        lemma: idiom.phrase,
        pos: idiom.pos.isNotEmpty ? idiom.pos : 'idiom',
        senseCount: 1,
        isMonosemous: true,
      );
      final dummySense = UnifiedSense(
        id: idiom.id,
        wordId: idiom.id,
        senseIndex: 1,
        definitionEn: idiom.definitionEn,
        translationFa: idiom.translationFa,
      );
      return WordLookupResult(word: dummyWord, senses: [dummySense]);
    }

    return null;
  }

  // ── Idiom Lookups ────────────────────────────────────────────────────────

  /// Look up an idiom by normalized phrase or exact phrase.
  Future<UnifiedIdiom?> lookupIdiom(String normalizedPhrase) async {
    if (_db == null) return null;
    final candidates = _buildWordCandidates(normalizedPhrase, null);

    try {
      for (final cand in candidates) {
        final rows = await _db!.query(
          'idioms',
          where: 'normalized_phrase = ? OR phrase = ?',
          whereArgs: [cand.toLowerCase(), cand],
          limit: 1,
        );
        if (rows.isNotEmpty) return UnifiedIdiom.fromMap(rows.first);
      }
    } catch (e) {
      developer.log('lookupIdiom error: $e', name: 'UnifiedDict', level: 1000);
    }
    return null;
  }

  /// Load all idioms for Aho-Corasick automaton initialization.
  Future<List<UnifiedIdiom>> getAllIdioms() async {
    if (_db == null) return const [];
    try {
      final rows = await _db!.query(
        'idioms',
        columns: [
          'id', 'phrase', 'normalized_phrase', 'pos',
          'definition_en', 'translation_fa',
        ],
      );
      return rows.map((r) => UnifiedIdiom.fromMap(r)).toList();
    } catch (e) {
      developer.log('getAllIdioms error: $e',
          name: 'UnifiedDict', level: 1000);
      return const [];
    }
  }

  /// Look up an idiom for the advanced MWE detector (with vector blobs).
  Future<List<UnifiedIdiom>> getAllIdiomsWithVectors() async {
    if (_db == null) return const [];
    try {
      final rows = await _db!.query(
        'idioms',
        columns: [
          'id', 'phrase', 'normalized_phrase', 'pos',
          'definition_en', 'translation_fa',
          'vector_blob', 'isolated_components_vec_blob',
        ],
      );
      return rows.map((r) => UnifiedIdiom.fromMap(r)).toList();
    } catch (e) {
      developer.log('getAllIdiomsWithVectors error: $e',
          name: 'UnifiedDict', level: 1000);
      return const [];
    }
  }

  // ── Isolated Word Lookups ────────────────────────────────────────────────

  /// Look up a pre-computed isolated word vector.
  Future<IsolatedWord?> lookupIsolatedWord(String lemma) async {
    if (_db == null) return null;
    try {
      final rows = await _db!.query(
        'isolated_words',
        where: 'lemma = ?',
        whereArgs: [lemma.toLowerCase()],
        limit: 1,
      );
      if (rows.isNotEmpty) return IsolatedWord.fromMap(rows.first);
    } catch (e) {
      developer.log('lookupIsolatedWord error: $e',
          name: 'UnifiedDict', level: 1000);
    }
    return null;
  }

  // ── Vector Utilities ─────────────────────────────────────────────────────

  /// Dequantize an INT8 or Float32 vector blob to a Float32List.
  ///
  /// INT8 blobs are 384 bytes; Float32 blobs are 1536 bytes.
  static Float32List dequantizeVector(Uint8List blob) {
    if (blob.length == 384) {
      // INT8 quantized: dequantize to float32
      final floatList = Float32List(384);
      for (int i = 0; i < 384; i++) {
        floatList[i] = blob[i].toDouble() / 127.0;
      }
      return floatList;
    }
    // Already Float32
    return Float32List.view(blob.buffer, blob.offsetInBytes, blob.lengthInBytes ~/ 4);
  }
}

/// Combined result of a word lookup with its senses.
class WordLookupResult {
  final UnifiedWord word;
  final List<UnifiedSense> senses;

  const WordLookupResult({required this.word, required this.senses});
}
