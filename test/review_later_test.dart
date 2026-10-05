// Regression tests for Save & Review Later:
//  - duplicate saves no longer create duplicate cards,
//  - mastery toggle on a deleted row doesn't throw,
//  - clip player survives missing files + instant close (init race).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lexo_player/core/services/saved_review_service.dart';
import 'package:lexo_player/features/review_later/presentation/mini_clip_player.dart';

/// In-memory stand-in: exercises the notifiers without sqlite/path_provider.
class _FakeSavedReviewService extends SavedReviewService {
  int _nextId = 1;
  final Map<int, SavedSentence> sentences = {};
  final Map<int, SavedWord> words = {};

  @override
  Future<SavedSentence> saveSentence(SavedSentence sentence) async {
    final id = _nextId++;
    final saved = sentence.copyWith(id: id);
    sentences[id] = saved;
    return saved;
  }

  @override
  Future<List<SavedSentence>> getAllSentences() async =>
      sentences.values.toList();

  @override
  Future<void> deleteSentence(int id) async {
    sentences.remove(id);
  }

  @override
  Future<void> deleteSentencesForVideo(String videoPath) async {
    sentences.removeWhere((_, s) => s.videoPath == videoPath);
  }

  @override
  Future<void> toggleMastered(int id, bool isMastered) async {
    final s = sentences[id];
    if (s != null) sentences[id] = s.copyWith(isMastered: isMastered);
  }

  @override
  Future<SavedWord> saveWord(SavedWord word) async {
    final id = _nextId++;
    final saved = word.copyWith(id: id);
    words[id] = saved;
    return saved;
  }

  @override
  Future<List<SavedWord>> getAllWords() async => words.values.toList();

  @override
  Future<void> deleteWord(int id) async {
    words.remove(id);
  }
}

SavedSentence _sentence(
        {String word = 'shadow', String text = 'Follow the shadow'}) =>
    SavedSentence(
      videoPath: '/v/movie.mp4',
      videoTitle: 'Movie',
      sentenceText: text,
      targetWord: word,
      startTimeMs: 1000,
      endTimeMs: 4000,
      createdAt: '2026-10-05T00:00:00Z',
    );

void main() {
  group('saved sentences', () {
    test('saving the same sentence twice keeps a single card', () async {
      final notifier = SavedSentencesNotifier(_FakeSavedReviewService());
      // Allow constructor load to settle.
      await Future<void>.delayed(Duration.zero);
      await notifier.addSentence(_sentence());
      await notifier.addSentence(_sentence());
      expect(notifier.state.length, 1);
    });

    test('same sentence for a different word saves separately', () async {
      final notifier = SavedSentencesNotifier(_FakeSavedReviewService());
      await Future<void>.delayed(Duration.zero);
      await notifier.addSentence(_sentence(word: 'shadow'));
      await notifier.addSentence(_sentence(word: 'follow'));
      expect(notifier.state.length, 2);
    });

    test('mastery toggle flips and tolerates deleted rows', () async {
      final notifier = SavedSentencesNotifier(_FakeSavedReviewService());
      await Future<void>.delayed(Duration.zero);
      await notifier.addSentence(_sentence());
      final id = notifier.state.single.id!;
      await notifier.toggleMastered(id);
      expect(notifier.state.single.isMastered, isTrue);
      await notifier.removeSentence(id);
      // Must not throw StateError on the now-missing id.
      await notifier.toggleMastered(id);
      expect(notifier.state, isEmpty);
    });

    test('batch delete removes only that video', () async {
      final notifier = SavedSentencesNotifier(_FakeSavedReviewService());
      await Future<void>.delayed(Duration.zero);
      await notifier.addSentence(_sentence());
      await notifier.addSentence(_sentence()
          .copyWith(videoPath: '/v/other.mp4', sentenceText: 'Other line'));
      await notifier.removeSentencesForVideo('/v/movie.mp4');
      expect(notifier.state.length, 1);
      expect(notifier.state.single.videoPath, '/v/other.mp4');
    });

    test('sentence map round-trips mastery + null translation', () {
      final s = _sentence().copyWith(id: 7, isMastered: true);
      final back = SavedSentence.fromMap(s.toMap());
      expect(back.id, 7);
      expect(back.isMastered, isTrue);
      expect(back.translation, isNull);
      expect(back.startTime, const Duration(seconds: 1));
      expect(back.endTime, const Duration(seconds: 4));
    });
  });

  group('saved words', () {
    test('duplicate word in same context is ignored (case-insensitive)',
        () async {
      final notifier = SavedWordsNotifier(_FakeSavedReviewService());
      await Future<void>.delayed(Duration.zero);
      SavedWord w(String word) => SavedWord(
            word: word,
            contextSentence: 'Follow the shadow',
            createdAt: '2026-10-05T00:00:00Z',
          );
      await notifier.addWord(w('Shadow'));
      await notifier.addWord(w('shadow'));
      expect(notifier.state.length, 1);
      await notifier.addWord(w('shadow').copyWith(contextSentence: 'Other'));
      expect(notifier.state.length, 2);
    });
  });

  group('mini clip player', () {
    // NOTE: dart:io futures only resolve under runAsync in widget tests.
    testWidgets('missing file shows error card', (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: MiniClipPlayer(
                videoPath: '/definitely/not/here/clip.mp4',
                startTime: Duration(seconds: 1),
                endTime: Duration(seconds: 4),
              ),
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      expect(find.text('Video file not found or moved'), findsOneWidget);
    });

    testWidgets('instant close during init is safe (init race)',
        (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MiniClipPlayer(
                videoPath: '/definitely/not/here/clip.mp4',
                startTime: const Duration(seconds: 1),
                endTime: const Duration(seconds: 4),
                onClose: () {},
              ),
            ),
          ),
        );
        // Tear down while the async file check is still in flight.
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
        );
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('file:// URI is treated as a missing local file, not a crash',
        (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: MiniClipPlayer(
                videoPath: 'file:///definitely/not/here/clip.mp4',
                startTime: Duration(seconds: 1),
                endTime: Duration(seconds: 4),
              ),
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      expect(find.text('Video file not found or moved'), findsOneWidget);
    });
  });
}
