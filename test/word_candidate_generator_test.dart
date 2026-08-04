import 'package:flutter_test/flutter_test.dart';
import 'package:lexo_player/core/utils/word_tokenizer.dart';
import 'package:lexo_player/features/dictionary/domain/word_candidate_generator.dart';

void main() {
  group('WordCandidateGenerator', () {
    const generator = WordCandidateGenerator(maxWords: 8);

    test('returns empty list when lineTokens is empty', () {
      final candidates = generator.generateCandidates([], 0);
      expect(candidates, isEmpty);
    });

    test('returns empty list when targetIndex is out of bounds', () {
      final tokens = WordTokenizer.tokenize('Hello world');
      expect(generator.generateCandidates(tokens, -1), isEmpty);
      expect(generator.generateCandidates(tokens, 10), isEmpty);
    });

    test('returns empty list when targetIndex is on non-word token', () {
      final tokens = WordTokenizer.tokenize('Hello, world!');
      // index 1 is ', ' (isWord == false)
      expect(generator.generateCandidates(tokens, 1), isEmpty);
    });

    test('generates single word candidate for single-word line', () {
      final tokens = WordTokenizer.tokenize('run');
      final candidates = generator.generateCandidates(tokens, 0);

      expect(candidates, equals(['run']));
    });

    test('generates multi-word n-gram candidates prioritized by longest length first', () {
      final tokens = WordTokenizer.tokenize('look forward to meeting you');
      // target is "forward" at token index 2 (tokens: ["look", " ", "forward", " ", "to", " ", "meeting", " ", "you"])
      final candidates = generator.generateCandidates(tokens, 2);

      expect(candidates, contains('look forward to meeting you'));
      expect(candidates, contains('look forward to'));
      expect(candidates, contains('forward to'));
      expect(candidates, contains('forward'));

      // Check sorting (longest first)
      for (int i = 0; i < candidates.length - 1; i++) {
        expect(candidates[i].length, greaterThanOrEqualTo(candidates[i + 1].length));
      }
    });

    test('respects maxWords parameter', () {
      const smallGenerator = WordCandidateGenerator(maxWords: 2);
      final tokens = WordTokenizer.tokenize('one two three four five');
      // target is "three" at token index 4 ("one", " ", "two", " ", "three", ...)
      final candidates = smallGenerator.generateCandidates(tokens, 4);

      // Should only generate phrases with up to 2 words
      for (final candidate in candidates) {
        final wordCount = candidate.split(' ').length;
        expect(wordCount, lessThanOrEqualTo(2));
      }
      expect(candidates, contains('two three'));
      expect(candidates, contains('three four'));
      expect(candidates, contains('three'));
      expect(candidates, isNot(contains('one two three')));
    });
  });
}
