import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Represents a saved sentence from a video for spaced practice/review.
class SavedSentence {
  final int? id;
  final String videoPath;
  final String videoTitle;
  final String sentenceText;
  final String targetWord;
  final int startTimeMs;
  final int endTimeMs;
  final String? translation;
  final String createdAt;
  final bool isMastered;

  const SavedSentence({
    this.id,
    required this.videoPath,
    required this.videoTitle,
    required this.sentenceText,
    required this.targetWord,
    required this.startTimeMs,
    required this.endTimeMs,
    this.translation,
    required this.createdAt,
    this.isMastered = false,
  });

  Duration get startTime => Duration(milliseconds: startTimeMs);
  Duration get endTime => Duration(milliseconds: endTimeMs);

  SavedSentence copyWith({
    int? id,
    String? videoPath,
    String? videoTitle,
    String? sentenceText,
    String? targetWord,
    int? startTimeMs,
    int? endTimeMs,
    String? translation,
    String? createdAt,
    bool? isMastered,
  }) {
    return SavedSentence(
      id: id ?? this.id,
      videoPath: videoPath ?? this.videoPath,
      videoTitle: videoTitle ?? this.videoTitle,
      sentenceText: sentenceText ?? this.sentenceText,
      targetWord: targetWord ?? this.targetWord,
      startTimeMs: startTimeMs ?? this.startTimeMs,
      endTimeMs: endTimeMs ?? this.endTimeMs,
      translation: translation ?? this.translation,
      createdAt: createdAt ?? this.createdAt,
      isMastered: isMastered ?? this.isMastered,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'video_path': videoPath,
      'video_title': videoTitle,
      'sentence_text': sentenceText,
      'target_word': targetWord,
      'start_time_ms': startTimeMs,
      'end_time_ms': endTimeMs,
      'translation': translation,
      'created_at': createdAt,
      'is_mastered': isMastered ? 1 : 0,
    };
  }

  factory SavedSentence.fromMap(Map<String, dynamic> map) {
    return SavedSentence(
      id: map['id'] as int?,
      videoPath: map['video_path'] as String? ?? '',
      videoTitle: map['video_title'] as String? ?? '',
      sentenceText: map['sentence_text'] as String? ?? '',
      targetWord: map['target_word'] as String? ?? '',
      startTimeMs: map['start_time_ms'] as int? ?? 0,
      endTimeMs: map['end_time_ms'] as int? ?? 0,
      translation: map['translation'] as String?,
      createdAt: map['created_at'] as String? ?? '',
      isMastered: (map['is_mastered'] as int? ?? 0) == 1,
    );
  }
}

/// Represents a saved vocabulary word.
class SavedWord {
  final int? id;
  final String word;
  final String? lemma;
  final String? pos;
  final String? translation;
  final String? wsdMeaning;
  final String? contextSentence;
  final String createdAt;

  const SavedWord({
    this.id,
    required this.word,
    this.lemma,
    this.pos,
    this.translation,
    this.wsdMeaning,
    this.contextSentence,
    required this.createdAt,
  });

  SavedWord copyWith({
    int? id,
    String? word,
    String? lemma,
    String? pos,
    String? translation,
    String? wsdMeaning,
    String? contextSentence,
    String? createdAt,
  }) {
    return SavedWord(
      id: id ?? this.id,
      word: word ?? this.word,
      lemma: lemma ?? this.lemma,
      pos: pos ?? this.pos,
      translation: translation ?? this.translation,
      wsdMeaning: wsdMeaning ?? this.wsdMeaning,
      contextSentence: contextSentence ?? this.contextSentence,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'word': word,
      'lemma': lemma,
      'pos': pos,
      'translation': translation,
      'wsd_meaning': wsdMeaning,
      'context_sentence': contextSentence,
      'created_at': createdAt,
    };
  }

  factory SavedWord.fromMap(Map<String, dynamic> map) {
    return SavedWord(
      id: map['id'] as int?,
      word: map['word'] as String? ?? '',
      lemma: map['lemma'] as String?,
      pos: map['pos'] as String?,
      translation: map['translation'] as String?,
      wsdMeaning: map['wsd_meaning'] as String?,
      contextSentence: map['context_sentence'] as String?,
      createdAt: map['created_at'] as String? ?? '',
    );
  }
}

/// SQLite persistence service for saved review items (sentences & vocabulary).
class SavedReviewService {
  Database? _db;

  Future<Database> get database async {
    if (_db != null && _db!.isOpen) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final supportDir = await getApplicationSupportDirectory();
    final dbPath = p.join(supportDir.path, 'user_library.db');

    return await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS saved_sentences (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            video_path TEXT NOT NULL,
            video_title TEXT NOT NULL,
            sentence_text TEXT NOT NULL,
            target_word TEXT NOT NULL,
            start_time_ms INTEGER NOT NULL,
            end_time_ms INTEGER NOT NULL,
            translation TEXT,
            created_at TEXT NOT NULL,
            is_mastered INTEGER DEFAULT 0
          );
        ''');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS saved_words (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            word TEXT NOT NULL,
            lemma TEXT,
            pos TEXT,
            translation TEXT,
            wsd_meaning TEXT,
            context_sentence TEXT,
            created_at TEXT NOT NULL
          );
        ''');
      },
    );
  }

  // ── Sentences CRUD ────────────────────────────────────────────────────────

  Future<SavedSentence> saveSentence(SavedSentence sentence) async {
    final db = await database;
    final id = await db.insert(
      'saved_sentences',
      sentence.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return sentence.copyWith(id: id);
  }

  Future<List<SavedSentence>> getAllSentences() async {
    final db = await database;
    final maps = await db.query(
      'saved_sentences',
      orderBy: 'id DESC',
    );
    return maps.map((m) => SavedSentence.fromMap(m)).toList();
  }

  Future<void> deleteSentence(int id) async {
    final db = await database;
    await db.delete('saved_sentences', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteSentencesForVideo(String videoPath) async {
    final db = await database;
    await db.delete('saved_sentences', where: 'video_path = ?', whereArgs: [videoPath]);
  }

  Future<void> toggleMastered(int id, bool isMastered) async {
    final db = await database;
    await db.update(
      'saved_sentences',
      {'is_mastered': isMastered ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ── Words CRUD ────────────────────────────────────────────────────────────

  Future<SavedWord> saveWord(SavedWord word) async {
    final db = await database;
    final id = await db.insert(
      'saved_words',
      word.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return word.copyWith(id: id);
  }

  Future<List<SavedWord>> getAllWords() async {
    final db = await database;
    final maps = await db.query(
      'saved_words',
      orderBy: 'id DESC',
    );
    return maps.map((m) => SavedWord.fromMap(m)).toList();
  }

  Future<void> deleteWord(int id) async {
    final db = await database;
    await db.delete('saved_words', where: 'id = ?', whereArgs: [id]);
  }
}

// ── Riverpod Providers ──────────────────────────────────────────────────────

final savedReviewServiceProvider = Provider<SavedReviewService>((ref) {
  return SavedReviewService();
});

class SavedSentencesNotifier extends StateNotifier<List<SavedSentence>> {
  final SavedReviewService _service;

  SavedSentencesNotifier(this._service) : super([]) {
    loadSentences();
  }

  Future<void> loadSentences() async {
    final items = await _service.getAllSentences();
    state = items;
  }

  Future<void> addSentence(SavedSentence sentence) async {
    final saved = await _service.saveSentence(sentence);
    state = [saved, ...state];
  }

  Future<void> removeSentence(int id) async {
    await _service.deleteSentence(id);
    state = state.where((s) => s.id != id).toList();
  }

  Future<void> removeSentencesForVideo(String videoPath) async {
    await _service.deleteSentencesForVideo(videoPath);
    state = state.where((s) => s.videoPath != videoPath).toList();
  }

  Future<void> toggleMastered(int id) async {
    final current = state.firstWhere((s) => s.id == id);
    final updated = !current.isMastered;
    await _service.toggleMastered(id, updated);
    state = state.map((s) => s.id == id ? s.copyWith(isMastered: updated) : s).toList();
  }
}

final savedSentencesProvider =
    StateNotifierProvider<SavedSentencesNotifier, List<SavedSentence>>((ref) {
  final service = ref.watch(savedReviewServiceProvider);
  return SavedSentencesNotifier(service);
});

class SavedWordsNotifier extends StateNotifier<List<SavedWord>> {
  final SavedReviewService _service;

  SavedWordsNotifier(this._service) : super([]) {
    loadWords();
  }

  Future<void> loadWords() async {
    final items = await _service.getAllWords();
    state = items;
  }

  Future<void> addWord(SavedWord word) async {
    final saved = await _service.saveWord(word);
    state = [saved, ...state];
  }

  Future<void> removeWord(int id) async {
    await _service.deleteWord(id);
    state = state.where((w) => w.id != id).toList();
  }
}

final savedWordsProvider =
    StateNotifierProvider<SavedWordsNotifier, List<SavedWord>>((ref) {
  final service = ref.watch(savedReviewServiceProvider);
  return SavedWordsNotifier(service);
});

/// Groups saved sentences by video title.
final savedSentencesGroupedByVideoProvider =
    Provider<Map<String, List<SavedSentence>>>((ref) {
  final sentences = ref.watch(savedSentencesProvider);
  final grouped = <String, List<SavedSentence>>{};
  for (final s in sentences) {
    final title = s.videoTitle.isNotEmpty ? s.videoTitle : 'Unknown Video';
    grouped.putIfAbsent(title, () => []).add(s);
  }
  return grouped;
});
