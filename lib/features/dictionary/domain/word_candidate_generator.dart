import 'package:lexo_player/core/utils/word_tokenizer.dart';

/// Abstract interface for generating dictionary lookup candidate phrases
/// from a list of tokenized words in a sentence or line.
abstract class IWordCandidateGenerator {
  /// Generates a list of candidate strings (single words, multi-word phrases)
  /// centered around [targetIndex] in [lineTokens].
  ///
  /// Returns candidates ordered by phrase length descending (longest candidate first).
  List<String> generateCandidates(List<TokenSpan> lineTokens, int targetIndex);
}

/// Standard implementation of [IWordCandidateGenerator] using a sliding window
/// n-gram strategy for phrase extraction.
class WordCandidateGenerator implements IWordCandidateGenerator {
  /// The maximum number of words allowed in a candidate multi-word phrase.
  final int maxWords;

  /// Creates a [WordCandidateGenerator] with an optional [maxWords] limit (default: 8).
  const WordCandidateGenerator({this.maxWords = 8});

  @override
  List<String> generateCandidates(List<TokenSpan> lineTokens, int targetIndex) {
    if (lineTokens.isEmpty || targetIndex < 0 || targetIndex >= lineTokens.length) {
      return const [];
    }

    // Collect all valid word token indices in order.
    final wordIndices = <int>[];
    for (int i = 0; i < lineTokens.length; i++) {
      if (lineTokens[i].isWord) {
        wordIndices.add(i);
      }
    }

    // Locate position of targetIndex within wordIndices.
    final targetWordPos = wordIndices.indexOf(targetIndex);
    if (targetWordPos == -1) {
      return const [];
    }

    final candidates = <String>{};

    // Generate n-gram word phrases containing targetWordPos.
    for (int len = 1; len <= maxWords; len++) {
      for (int startPos = targetWordPos - len + 1; startPos <= targetWordPos; startPos++) {
        final endPos = startPos + len - 1;
        if (startPos >= 0 && endPos < wordIndices.length) {
          final phraseWords = <String>[];
          for (int i = startPos; i <= endPos; i++) {
            phraseWords.add(lineTokens[wordIndices[i]].text);
          }
          candidates.add(phraseWords.join(' '));
        }
      }
    }

    // Sort candidate phrases with longest length prioritized first.
    final list = candidates.toList();
    list.sort((a, b) => b.length.compareTo(a.length));
    return list;
  }
}
