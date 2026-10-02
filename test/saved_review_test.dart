import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:lexo_player/core/services/saved_review_service.dart';
import 'package:lexo_player/features/review_later/presentation/review_later_panel.dart';
import 'package:lexo_player/core/engine/engine_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('SavedSentence Model Tests', () {
    test('toMap and fromMap should correctly serialize and deserialize', () {
      final sentence = SavedSentence(
        id: 1,
        videoPath: '/path/to/movie.mp4',
        videoTitle: 'Inception',
        sentenceText: 'We need to go deeper.',
        targetWord: 'deeper',
        startTimeMs: 12500,
        endTimeMs: 15000,
        translation: 'باید عمیق‌تر بریم.',
        createdAt: '2026-10-02T10:00:00Z',
        isMastered: true,
      );

      final map = sentence.toMap();
      expect(map['id'], 1);
      expect(map['video_path'], '/path/to/movie.mp4');
      expect(map['video_title'], 'Inception');
      expect(map['sentence_text'], 'We need to go deeper.');
      expect(map['target_word'], 'deeper');
      expect(map['start_time_ms'], 12500);
      expect(map['end_time_ms'], 15000);
      expect(map['translation'], 'باید عمیق‌تر بریم.');
      expect(map['created_at'], '2026-10-02T10:00:00Z');
      expect(map['is_mastered'], 1);

      final from = SavedSentence.fromMap(map);
      expect(from.id, 1);
      expect(from.videoPath, '/path/to/movie.mp4');
      expect(from.videoTitle, 'Inception');
      expect(from.sentenceText, 'We need to go deeper.');
      expect(from.targetWord, 'deeper');
      expect(from.startTimeMs, 12500);
      expect(from.endTimeMs, 15000);
      expect(from.startTime, const Duration(milliseconds: 12500));
      expect(from.endTime, const Duration(milliseconds: 15000));
      expect(from.translation, 'باید عمیق‌تر بریم.');
      expect(from.createdAt, '2026-10-02T10:00:00Z');
      expect(from.isMastered, isTrue);
    });

    test('copyWith should update specified fields only', () {
      final sentence = SavedSentence(
        id: 1,
        videoPath: '/path/movie.mkv',
        videoTitle: 'Interstellar',
        sentenceText: 'Stay!',
        targetWord: 'Stay',
        startTimeMs: 1000,
        endTimeMs: 3000,
        createdAt: '2026-10-02T10:00:00Z',
        isMastered: false,
      );

      final updated = sentence.copyWith(isMastered: true, targetWord: 'STAY');
      expect(updated.id, 1);
      expect(updated.isMastered, isTrue);
      expect(updated.targetWord, 'STAY');
      expect(updated.videoTitle, 'Interstellar');
    });
  });

  group('SavedWord Model Tests', () {
    test('toMap and fromMap should correctly serialize and deserialize', () {
      final word = SavedWord(
        id: 42,
        word: 'meticulous',
        lemma: 'meticulous',
        pos: 'ADJ',
        translation: 'بسیار دقیق',
        wsdMeaning: 'showing great attention to detail',
        contextSentence: 'She was meticulous about her work.',
        createdAt: '2026-10-02T11:00:00Z',
      );

      final map = word.toMap();
      expect(map['id'], 42);
      expect(map['word'], 'meticulous');
      expect(map['lemma'], 'meticulous');
      expect(map['pos'], 'ADJ');
      expect(map['translation'], 'بسیار دقیق');
      expect(map['wsd_meaning'], 'showing great attention to detail');
      expect(map['context_sentence'], 'She was meticulous about her work.');
      expect(map['created_at'], '2026-10-02T11:00:00Z');

      final from = SavedWord.fromMap(map);
      expect(from.id, 42);
      expect(from.word, 'meticulous');
      expect(from.lemma, 'meticulous');
      expect(from.pos, 'ADJ');
      expect(from.translation, 'بسیار دقیق');
      expect(from.wsdMeaning, 'showing great attention to detail');
      expect(from.contextSentence, 'She was meticulous about her work.');
      expect(from.createdAt, '2026-10-02T11:00:00Z');
    });
  });

  group('In-Memory SQLite CRUD Tests', () {
    late Database db;

    setUp(() async {
      db = await openDatabase(
        inMemoryDatabasePath,
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
    });

    tearDown(() async {
      await db.close();
    });

    test('Insert, query, toggle, and delete sentences in SQLite', () async {
      final s1 = SavedSentence(
        videoPath: '/movies/film1.mp4',
        videoTitle: 'The Matrix',
        sentenceText: 'Follow the white rabbit.',
        targetWord: 'rabbit',
        startTimeMs: 5000,
        endTimeMs: 8000,
        createdAt: '2026-10-02T12:00:00Z',
      );

      final s2 = SavedSentence(
        videoPath: '/movies/film1.mp4',
        videoTitle: 'The Matrix',
        sentenceText: 'There is no spoon.',
        targetWord: 'spoon',
        startTimeMs: 12000,
        endTimeMs: 15000,
        createdAt: '2026-10-02T12:05:00Z',
      );

      final s3 = SavedSentence(
        videoPath: '/movies/film2.mp4',
        videoTitle: 'Gladiator',
        sentenceText: 'Are you not entertained?',
        targetWord: 'entertained',
        startTimeMs: 20000,
        endTimeMs: 23000,
        createdAt: '2026-10-02T12:10:00Z',
      );

      final id1 = await db.insert('saved_sentences', s1.toMap());
      final id2 = await db.insert('saved_sentences', s2.toMap());
      final id3 = await db.insert('saved_sentences', s3.toMap());

      expect(id1, greaterThan(0));
      expect(id2, greaterThan(0));
      expect(id3, greaterThan(0));

      // Query all
      final rows = await db.query('saved_sentences', orderBy: 'id DESC');
      expect(rows.length, 3);
      final fetched = rows.map((r) => SavedSentence.fromMap(r)).toList();
      expect(fetched[0].sentenceText, 'Are you not entertained?');
      expect(fetched[1].sentenceText, 'There is no spoon.');
      expect(fetched[2].sentenceText, 'Follow the white rabbit.');

      // Toggle mastery
      await db.update(
        'saved_sentences',
        {'is_mastered': 1},
        where: 'id = ?',
        whereArgs: [id2],
      );
      final updatedRow = await db.query('saved_sentences', where: 'id = ?', whereArgs: [id2]);
      expect(SavedSentence.fromMap(updatedRow.first).isMastered, isTrue);

      // Delete single
      await db.delete('saved_sentences', where: 'id = ?', whereArgs: [id3]);
      final afterSingleDel = await db.query('saved_sentences');
      expect(afterSingleDel.length, 2);

      // Batch delete by video
      await db.delete('saved_sentences', where: 'video_path = ?', whereArgs: ['/movies/film1.mp4']);
      final afterBatchDel = await db.query('saved_sentences');
      expect(afterBatchDel.isEmpty, isTrue);
    });

    test('Insert, query, and delete saved words in SQLite', () async {
      final w1 = SavedWord(
        word: 'serendipity',
        lemma: 'serendipity',
        pos: 'NOUN',
        translation: 'خوش‌اقبالی غیرمنتظره',
        createdAt: '2026-10-02T12:00:00Z',
      );

      final id = await db.insert('saved_words', w1.toMap());
      expect(id, greaterThan(0));

      final rows = await db.query('saved_words');
      expect(rows.length, 1);
      final fetched = SavedWord.fromMap(rows.first);
      expect(fetched.word, 'serendipity');
      expect(fetched.pos, 'NOUN');

      await db.delete('saved_words', where: 'id = ?', whereArgs: [id]);
      final afterDel = await db.query('saved_words');
      expect(afterDel.isEmpty, isTrue);
    });
  });

  group('ReviewLaterPanel Widget Tests', () {
    testWidgets('renders empty state when no sentences are saved', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appLanguageProvider.overrideWith((ref) => 'en'),
            savedSentencesProvider.overrideWith((ref) => _FakeSavedSentencesNotifier([])),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: ReviewLaterPanel(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Review Sentences Later'), findsOneWidget);
      expect(find.text('No saved sentences yet'), findsOneWidget);
    });

    testWidgets('renders saved sentences grouped by video with highlighted word', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      final testSentence = SavedSentence(
        id: 1,
        videoPath: '/movies/inception.mp4',
        videoTitle: 'Inception (2010)',
        sentenceText: 'You mustn\'t be afraid to dream a little bigger, darling.',
        targetWord: 'darling',
        startTimeMs: 10000,
        endTimeMs: 14000,
        translation: 'عزیزم نباید از رویاهای بزرگتر بترسی.',
        createdAt: '2026-10-02T12:00:00Z',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appLanguageProvider.overrideWith((ref) => 'en'),
            savedSentencesProvider.overrideWith((ref) => _FakeSavedSentencesNotifier([testSentence])),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: ReviewLaterPanel(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Inception (2010)'), findsOneWidget);
      expect(find.text('Play Video Clip'), findsOneWidget);
      expect(find.text('Hear Word'), findsOneWidget);
      expect(find.text('darling'), findsOneWidget);
      expect(find.text('00:10 → 00:14'), findsOneWidget);
    });
  });
}

class _FakeSavedSentencesNotifier extends StateNotifier<List<SavedSentence>>
    implements SavedSentencesNotifier {
  _FakeSavedSentencesNotifier(super.state);

  @override
  Future<void> loadSentences() async {}

  @override
  Future<void> addSentence(SavedSentence sentence) async {
    state = [sentence, ...state];
  }

  @override
  Future<void> removeSentence(int id) async {
    state = state.where((s) => s.id != id).toList();
  }

  @override
  Future<void> removeSentencesForVideo(String videoPath) async {
    state = state.where((s) => s.videoPath != videoPath).toList();
  }

  @override
  Future<void> toggleMastered(int id) async {
    state = state.map((s) => s.id == id ? s.copyWith(isMastered: !s.isMastered) : s).toList();
  }
}

