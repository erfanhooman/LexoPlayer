import 'dart:developer' as developer;

import 'package:sqflite/sqflite.dart';

import 'package:lexo_player/core/database/database_service.dart';
import 'package:lexo_player/core/models/dictionary_result.dart';
import 'package:lexo_player/core/utils/stemmer_utils.dart';

/// Repository that queries two dictionary databases concurrently and applies
/// a stemming fallback cascade when exact matches fail.
///
/// Unlike the previous hardcoded implementation, this repository accepts
/// runtime database paths via [switchDatabases], allowing the user to
/// dynamically select which monolingual and bilingual dictionaries to use.
///
/// Lookup flow:
/// 1. Clean the raw token (lowercase, strip punctuation).
/// 2. Execute parallel queries against the active monolingual & bilingual DBs.
/// 3. If both return null, stem the word via Porter 2 and retry.
/// 4. Return a combined [DictionaryResult].
class DualDictionaryRepository {
  final DatabaseService _dbService;

  Database? _monoDb;
  Database? _biDb;

  /// The absolute path of the currently loaded monolingual database.
  String? _monoPath;

  /// The absolute path of the currently loaded bilingual database.
  String? _biPath;

  DualDictionaryRepository(this._dbService);

  // ── Runtime database switching ──────────────────────────────────────────

  /// Switches the active dictionary databases at runtime.
  ///
  /// Closes any previously open handles and opens new databases at the
  /// specified paths. Either path may be `null` to indicate that no
  /// dictionary of that type is currently selected.
  ///
  /// This is the primary initialisation entry point — call it whenever the
  /// user changes their dictionary selection in the settings UI.
  Future<void> switchDatabases({
    String? monolingualPath,
    String? bilingualPath,
  }) async {
    // Close existing handles if paths have changed.
    if (_monoPath != null && _monoPath != monolingualPath) {
      await _dbService.closeDatabase(_monoPath!);
      _monoDb = null;
      developer.log(
        'DualDictionaryRepository: Closed monolingual DB at $_monoPath',
        name: 'DictRepo',
      );
    }
    if (_biPath != null && _biPath != bilingualPath) {
      await _dbService.closeDatabase(_biPath!);
      _biDb = null;
      developer.log(
        'DualDictionaryRepository: Closed bilingual DB at $_biPath',
        name: 'DictRepo',
      );
    }

    _monoPath = monolingualPath;
    _biPath = bilingualPath;

    // Open new handles.
    if (monolingualPath != null) {
      _monoDb = await _dbService.getDatabaseByPath(monolingualPath);
      developer.log(
        'DualDictionaryRepository: Opened monolingual DB at $monolingualPath',
        name: 'DictRepo',
      );
    }
    if (bilingualPath != null) {
      _biDb = await _dbService.getDatabaseByPath(bilingualPath);
      developer.log(
        'DualDictionaryRepository: Opened bilingual DB at $bilingualPath',
        name: 'DictRepo',
      );
    }
  }

  /// Whether at least one dictionary is currently loaded.
  bool get isReady => _monoDb != null || _biDb != null;

  // ── Public API ──────────────────────────────────────────────────────────

  /// Look up a raw token through the dual-tier pipeline.
  ///
  /// Returns a [DictionaryResult] containing any found definitions and/or
  /// translations, or an empty result if nothing matches even after stemming.
  Future<DictionaryResult> lookup(String rawToken) async {
    final cleaned = StemmerUtils.cleanToken(rawToken);
    if (cleaned.isEmpty) {
      return DictionaryResult(word: rawToken);
    }

    // Phase 1: Exact match in both databases concurrently.
    final exactResults = await Future.wait([
      _queryMonolingual(cleaned),
      _queryBilingual(cleaned),
    ]);

    final exactHtml = exactResults[0];
    final exactTrans = exactResults[1];

    if (exactHtml != null || exactTrans != null) {
      return DictionaryResult(
        word: cleaned,
        htmlDefinition: exactHtml,
        localizedText: exactTrans,
        wasStemmed: false,
      );
    }

    // Phase 2: Stemming fallback – try the root form.
    final stemmed = StemmerUtils.stem(cleaned);
    if (stemmed == cleaned || stemmed.isEmpty) {
      return DictionaryResult(word: cleaned);
    }

    final stemResults = await Future.wait([
      _queryMonolingual(stemmed),
      _queryBilingual(stemmed),
    ]);

    return DictionaryResult(
      word: stemmed,
      htmlDefinition: stemResults[0],
      localizedText: stemResults[1],
      wasStemmed: true,
    );
  }

  // ── Private query helpers ───────────────────────────────────────────────

  /// Query the monolingual (target-to-target) dictionary for an HTML definition.
  Future<String?> _queryMonolingual(String word) async {
    if (_monoDb == null) return null;
    try {
      final rows = await _monoDb!.query(
        'entries',
        columns: ['html_definition'],
        where: 'word = ?',
        whereArgs: [word],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        return rows.first['html_definition'] as String?;
      }
    } catch (_) {
      // Database query error – return null gracefully.
    }
    return null;
  }

  /// Query the bilingual (target-to-native) dictionary for localized text.
  Future<String?> _queryBilingual(String word) async {
    if (_biDb == null) return null;
    try {
      final rows = await _biDb!.query(
        'entries',
        columns: ['localized_text'],
        where: 'word = ?',
        whereArgs: [word],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        return rows.first['localized_text'] as String?;
      }
    } catch (_) {
      // Database query error – return null gracefully.
    }
    return null;
  }

  /// Release all database handles.
  Future<void> dispose() async {
    if (_monoPath != null) {
      await _dbService.closeDatabase(_monoPath!);
    }
    if (_biPath != null) {
      await _dbService.closeDatabase(_biPath!);
    }
    _monoDb = null;
    _biDb = null;
    _monoPath = null;
    _biPath = null;
  }
}
