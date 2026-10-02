/// Represents the evaluation result of a spoken word in real-time shadowing.
class SpokenWordToken {
  final String text;
  final bool isMatch;

  const SpokenWordToken({
    required this.text,
    required this.isMatch,
  });
}

/// Evaluation result comparing spoken text against the target sentence.
class SpeechMatchResult {
  final List<SpokenWordToken> spokenTokens;
  final List<String> targetTokens;
  final int matchedCount;
  final int totalCount;
  final double matchPercentage;
  final bool isComplete;

  const SpeechMatchResult({
    required this.spokenTokens,
    required this.targetTokens,
    required this.matchedCount,
    required this.totalCount,
    required this.matchPercentage,
    required this.isComplete,
  });
}

/// Utility for matching spoken words against a target subtitle sentence in real time.
class SpeechMatcher {
  static final RegExp _cleanRegex = RegExp(r"[^\w']");

  /// Cleans a word for comparison by removing surrounding punctuation and lowercasing.
  static String cleanWord(String word) {
    return word.toLowerCase().replaceAll(_cleanRegex, '').trim();
  }

  /// Tokenizes a sentence into clean words.
  static List<String> tokenize(String sentence) {
    return sentence
        .split(RegExp(r'\s+'))
        .map(cleanWord)
        .where((w) => w.isNotEmpty)
        .toList();
  }

  /// Evaluates [spokenText] against [targetSentence].
  static SpeechMatchResult evaluate({
    required String spokenText,
    required String targetSentence,
  }) {
    final targetWords = tokenize(targetSentence);
    if (targetWords.isEmpty) {
      return const SpeechMatchResult(
        spokenTokens: [],
        targetTokens: [],
        matchedCount: 0,
        totalCount: 0,
        matchPercentage: 1.0,
        isComplete: true,
      );
    }

    final rawSpokenWords = spokenText
        .split(RegExp(r'\s+'))
        .where((w) => w.trim().isNotEmpty)
        .toList();

    final spokenTokens = <SpokenWordToken>[];
    int targetPointer = 0;
    int matchedWordsCount = 0;

    for (final rawWord in rawSpokenWords) {
      final cleaned = cleanWord(rawWord);
      if (cleaned.isEmpty) continue;

      // Check if this spoken word matches the next expected target word
      if (targetPointer < targetWords.length && cleaned == targetWords[targetPointer]) {
        spokenTokens.add(SpokenWordToken(text: rawWord, isMatch: true));
        targetPointer++;
        matchedWordsCount++;
      } else {
        // Lookahead check: maybe the user skipped a word or there is minor variance
        int lookahead = -1;
        for (int i = targetPointer; i < targetWords.length && i <= targetPointer + 2; i++) {
          if (cleaned == targetWords[i]) {
            lookahead = i;
            break;
          }
        }

        if (lookahead != -1) {
          spokenTokens.add(SpokenWordToken(text: rawWord, isMatch: true));
          targetPointer = lookahead + 1;
          matchedWordsCount++;
        } else {
          spokenTokens.add(SpokenWordToken(text: rawWord, isMatch: false));
        }
      }
    }

    final isComplete = targetPointer >= targetWords.length && targetWords.isNotEmpty;
    final matchPercentage = targetWords.isNotEmpty
        ? (matchedWordsCount / targetWords.length).clamp(0.0, 1.0)
        : 1.0;

    return SpeechMatchResult(
      spokenTokens: spokenTokens,
      targetTokens: targetWords,
      matchedCount: matchedWordsCount,
      totalCount: targetWords.length,
      matchPercentage: matchPercentage,
      isComplete: isComplete,
    );
  }
}
