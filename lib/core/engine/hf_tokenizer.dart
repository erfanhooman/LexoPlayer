import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;

/// Encoding output from the HuggingFace WordPiece tokenizer.
class HfEncoding {
  final List<int> inputIds;
  final List<int> attentionMask;
  final List<int> tokenTypeIds;

  /// Maps each original character index to its corresponding sub-token index.
  /// `null` means the character was absorbed into a sub-token that starts earlier.
  final List<int?> charToTokenMap;

  const HfEncoding({
    required this.inputIds,
    required this.attentionMask,
    required this.tokenTypeIds,
    required this.charToTokenMap,
  });

  /// Returns the sub-token index that covers the given character position,
  /// or `null` if the character is not mapped (e.g., whitespace/punctuation
  /// absorbed into a subword).
  int? charToToken(int charIndex) {
    if (charIndex < 0 || charIndex >= charToTokenMap.length) return null;
    return charToTokenMap[charIndex];
  }
}

/// HuggingFace WordPiece tokenizer for `all-MiniLM-L6-v2`.
///
/// Implements WordPiece tokenization with [CLS]/[SEP] special tokens,
/// producing `input_ids` and `attention_mask` suitable for ONNX inference.
///
/// Also builds a `charToToken` mapping that tracks which sub-token index
/// covers each original character — critical for the WSD engine's
/// `_extract_target_token_vector()` method.
class HfTokenizer {
  static const int clsTokenId = 101;
  static const int sepTokenId = 102;
  static const int unkTokenId = 100;
  static const int padTokenId = 0;

  final Map<String, int> _vocab;
  final int _maxLength;

  HfTokenizer(this._vocab, {int maxLength = 128}) : _maxLength = maxLength;

  /// Loads a HfTokenizer from a bundled asset.
  ///
  /// The vocab.json maps subword strings to their integer IDs.
  static Future<HfTokenizer> fromAsset({int maxLength = 128}) async {
    final jsonStr = await rootBundle.loadString('assets/vocab.json');
    final Map<String, dynamic> raw = jsonDecode(jsonStr);
    final vocab = raw.map((k, v) => MapEntry(k, v as int));
    return HfTokenizer(vocab, maxLength: maxLength);
  }

  /// Creates an HfTokenizer from a file path.
  static Future<HfTokenizer> fromFile(String path,
      {int maxLength = 128}) async {
    final file = File(path);
    if (!await file.exists()) {
      throw FileSystemException('vocab.json not found', path);
    }
    final content = await file.readAsString();
    final Map<String, dynamic> raw = jsonDecode(content);
    final vocab = raw.map((k, v) => MapEntry(k, v as int));
    return HfTokenizer(vocab, maxLength: maxLength);
  }

  /// Creates an HfTokenizer from an in-memory vocab map.
  HfTokenizer.fromVocab(Map<String, int> vocab, {int maxLength = 128})
      : _vocab = vocab,
        _maxLength = maxLength;

  /// Tokenizes [text] and returns an [HfEncoding] with padded/truncated output.
  ///
  /// Pre-tokenization matches Python's BertPreTokenizer: split on whitespace,
  /// isolate punctuation as separate tokens.
  /// Then applies WordPiece subword splitting.
  HfEncoding encode(String text) {
    // Step 1: BertPreTokenizer — split on whitespace, isolate punctuation
    final basicTokenOffsets = _bertPreTokenize(text);

    // Step 2: WordPiece subword splitting
    final subTokens = <String>[];
    // Track which original token each sub-token belongs to
    final subTokenToBasicIndex = <int>[];

    for (int basicIdx = 0; basicIdx < basicTokenOffsets.length; basicIdx++) {
      final entry = basicTokenOffsets[basicIdx];
      final word = entry.$1;

      final pieces = _wordPieceTokenize(word);
      for (final piece in pieces) {
        subTokens.add(piece);
        subTokenToBasicIndex.add(basicIdx);
      }
    }

    // Step 3: Add special tokens
    final allTokens = <String>['[CLS]', ...subTokens, '[SEP]'];

    // Step 4: Map to IDs
    final inputIds = <int>[];
    for (final token in allTokens) {
      inputIds.add(_vocab[token] ?? unkTokenId);
    }

    // Truncate if needed
    if (inputIds.length > _maxLength) {
      inputIds.removeRange(_maxLength - 1, inputIds.length);
      inputIds.add(sepTokenId);
    }

    // Step 5: Build attention mask (1 for real tokens, 0 for padding)
    // Pre-allocate to max length — 1 for real tokens, 0 for padding.
    final attentionMask = List<int>.filled(_maxLength, 0);
    for (int i = 0; i < inputIds.length && i < _maxLength; i++) {
      attentionMask[i] = 1;
    }

    // Token type IDs (all 0 for single sentence)
    final tokenTypeIds = List<int>.filled(_maxLength, 0);

    // Step 6: Build char-to-token mapping
    // Map each original character to the sub-token that covers it.
    final charToTokenMap = List<int?>.filled(text.length, null);

    for (int subIdx = 0; subIdx < subTokens.length; subIdx++) {
      final basicIdx = subTokenToBasicIndex[subIdx];
      final entry = basicTokenOffsets[basicIdx];
      final start = entry.$2;
      final end = entry.$3;

      // Sub-token index in inputIds is subIdx + 1 (for [CLS])
      final mappedSubToken = subIdx + 1;

      // For the first sub-token of a word, map ALL characters of that word
      // For continuation sub-tokens (##), map remaining characters
      for (int c = start; c < end && c < text.length; c++) {
        charToTokenMap[c] = mappedSubToken;
      }
    }

    return HfEncoding(
      inputIds: inputIds,
      attentionMask: attentionMask,
      tokenTypeIds: tokenTypeIds,
      charToTokenMap: charToTokenMap,
    );
  }

  /// BertPreTokenizer: splits on whitespace and isolates punctuation.
  /// Matches Python's behavior: `\w+|[^\w\s]+`
  List<(String, int, int)> _bertPreTokenize(String text) {
    final results = <(String, int, int)>[];
    final pattern = RegExp(r'\w+|[^\w\s]+');
    for (final match in pattern.allMatches(text)) {
      results.add((match.group(0)!, match.start, match.end));
    }
    return results;
  }

  /// WordPiece subword tokenization for a single token.
  List<String> _wordPieceTokenize(String token) {
    final result = <String>[];
    final lower = token.toLowerCase();

    if (_vocab.containsKey(lower)) {
      result.add(lower);
      return result;
    }

    int start = 0;
    while (start < lower.length) {
      int end = lower.length;
      bool found = false;

      while (start < end) {
        var substr = start == 0
            ? lower.substring(start, end)
            : '##${lower.substring(start, end)}';
        if (_vocab.containsKey(substr)) {
          result.add(substr);
          found = true;
          break;
        }
        end--;
      }

      if (!found) {
        result.add('[UNK]');
        break;
      }

      start = end;
    }

    return result;
  }
}
