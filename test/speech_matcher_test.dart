import 'package:flutter_test/flutter_test.dart';
import 'package:lexo_player/core/utils/speech_matcher.dart';

void main() {
  group('SpeechMatcher Unit Tests', () {
    test('cleanWord strips punctuation and lowercases', () {
      expect(SpeechMatcher.cleanWord('Hello,'), 'hello');
      expect(SpeechMatcher.cleanWord('WORLD!'), 'world');
      expect(SpeechMatcher.cleanWord("don't"), "don't");
      expect(SpeechMatcher.cleanWord('...test...'), 'test');
      expect(SpeechMatcher.cleanWord('  '), '');
    });

    test('tokenize handles punctuation and multiple whitespace', () {
      const sentence = 'Hello,   world! How are you?';
      final tokens = SpeechMatcher.tokenize(sentence);
      expect(tokens, ['hello', 'world', 'how', 'are', 'you']);
    });

    test('empty target sentence returns complete', () {
      final result = SpeechMatcher.evaluate(
        spokenText: 'hello',
        targetSentence: '',
      );
      expect(result.isComplete, isTrue);
      expect(result.matchPercentage, 1.0);
      expect(result.totalCount, 0);
    });

    test('empty spoken text returns incomplete with zero matches', () {
      final result = SpeechMatcher.evaluate(
        spokenText: '',
        targetSentence: 'Hello world',
      );
      expect(result.isComplete, isFalse);
      expect(result.matchedCount, 0);
      expect(result.totalCount, 2);
      expect(result.matchPercentage, 0.0);
      expect(result.spokenTokens, isEmpty);
    });

    test('exact match with case and punctuation differences completes successfully', () {
      const target = 'To be, or not to be: that is the question!';
      const spoken = 'to be or not to be that is the question';

      final result = SpeechMatcher.evaluate(
        spokenText: spoken,
        targetSentence: target,
      );

      expect(result.isComplete, isTrue);
      expect(result.matchedCount, 10);
      expect(result.totalCount, 10);
      expect(result.matchPercentage, 1.0);
      expect(result.spokenTokens.every((t) => t.isMatch), isTrue);
    });

    test('partial match identifies progress accurately', () {
      const target = 'We are learning Flutter for cross platform apps';
      const spoken = 'we are learning flutter';

      final result = SpeechMatcher.evaluate(
        spokenText: spoken,
        targetSentence: target,
      );

      expect(result.isComplete, isFalse);
      expect(result.matchedCount, 4);
      expect(result.totalCount, 8);
      expect(result.matchPercentage, closeTo(4 / 8, 0.01));
      expect(result.spokenTokens.length, 4);
      expect(result.spokenTokens.every((t) => t.isMatch), isTrue);
    });

    test('handles incorrect words with isMatch = false', () {
      const target = 'Good morning everyone';
      const spoken = 'Good banana everyone';

      final result = SpeechMatcher.evaluate(
        spokenText: spoken,
        targetSentence: target,
      );

      expect(result.spokenTokens.length, 3);
      expect(result.spokenTokens[0].text, 'Good');
      expect(result.spokenTokens[0].isMatch, isTrue);
      expect(result.spokenTokens[1].text, 'banana');
      expect(result.spokenTokens[1].isMatch, isFalse);
      expect(result.spokenTokens[2].text, 'everyone');
      expect(result.spokenTokens[2].isMatch, isTrue);
    });

    test('lookahead absorbs a skipped word', () {
      const target = 'I really love this movie';
      const spoken = 'I love this movie'; // Skipped "really"

      final result = SpeechMatcher.evaluate(
        spokenText: spoken,
        targetSentence: target,
      );

      expect(result.spokenTokens.every((t) => t.isMatch), isTrue);
      expect(result.isComplete, isTrue);
      expect(result.matchedCount, 4);
    });
  });
}
