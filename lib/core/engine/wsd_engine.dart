import 'dart:math';
import 'dart:typed_data';
import 'dart:developer' as developer;

import 'package:lexo_player/core/engine/hf_tokenizer.dart';
import 'package:lexo_player/core/engine/onnx_service.dart';
import 'package:lexo_player/core/engine/tokenizer.dart';
import 'package:lexo_player/features/dictionary/data/unified_dictionary_repository.dart';

/// Result of word sense disambiguation for a single token.
class WsdResult {
  final String token;
  final String lemma;
  final String pos;
  final bool isPolysemous;
  final String wsdMethod;
  final List<WsdCandidate> senses;

  const WsdResult({
    required this.token,
    required this.lemma,
    required this.pos,
    required this.isPolysemous,
    required this.wsdMethod,
    required this.senses,
  });
}

/// A single WSD candidate sense.
class WsdCandidate {
  final int rank;
  final double score;
  final String definitionEn;
  final String? translationFa;

  const WsdCandidate({
    required this.rank,
    required this.score,
    required this.definitionEn,
    this.translationFa,
  });
}

/// Word Sense Disambiguation engine using pre-computed sense vectors
/// and runtime ONNX context embeddings.
///
/// Port of `core/wsd_engine.py` from LexoEngine. Runs ONNX inference
/// once per sentence context window, then disambiguates each target token
/// using cosine similarity against pre-computed sense vectors stored
/// in the unified dictionary database.
class WsdEngine {
  final UnifiedDictionaryRepository _db;
  final HfTokenizer _hfTokenizer;
  final OnnxService _onnxService;
  bool useMonosemyFilter;

  WsdEngine({
    required UnifiedDictionaryRepository db,
    required HfTokenizer hfTokenizer,
    required OnnxService onnxService,
    this.useMonosemyFilter = true,
  })  : _db = db,
        _hfTokenizer = hfTokenizer,
        _onnxService = onnxService;

  /// Encodes the entire sliding context window text using ONNX.
  ///
  /// Returns the HuggingFace encoding (for char-to-token mapping)
  /// and the token embeddings [seq_len, 384].
  ///
  /// This should be called ONCE per sentence, and the result passed
  /// to [disambiguateWord] for each target token.
  Future<(HfEncoding, OnnxResult)?> encodeContextWindow(
      String contextWindowText) async {
    if (!_onnxService.isInitialized) return null;

    // Tokenize with HuggingFace tokenizer to get inputIds + attentionMask
    final encoding = _hfTokenizer.encode(contextWindowText);

    // Run ONNX inference with the pre-tokenized input
    final embeddings =
        await _onnxService.runInference(encoding.inputIds, encoding.attentionMask);

    if (embeddings == null) return null;
    return (encoding, embeddings);
  }

  /// Disambiguates a single word token using context and sense vectors.
  ///
  /// [contextWindowText] is the full sliding window text.
  /// [targetToken] is the token to disambiguate.
  /// [topK] is the maximum number of senses to return.
  /// [precomputedCtx] is the optional pre-computed (encoding, embeddings)
  ///   from [encodeContextWindow] for efficiency.
  Future<WsdResult> disambiguateWord({
    required String contextWindowText,
    required EngineTokenInfo targetToken,
    int topK = 5,
    (HfEncoding, OnnxResult)? precomputedCtx,
  }) async {
    final lemma = targetToken.lemma;
    final pos = targetToken.pos;

    // Query the database for the word
    final lookupResult = await _db.lookupWordWithSenses(
      lemma,
      pos,
      token: targetToken.token,
    );

    if (lookupResult == null) {
      return _fallbackResult(targetToken, 'word_not_in_dictionary');
    }

    final word = lookupResult.word;
    final senses = lookupResult.senses;

    if (senses.isEmpty) {
      return _fallbackResult(targetToken, 'no_senses_found');
    }

    // Tier 1: Monosemy Filter Bypass
    if (useMonosemyFilter && (word.isMonosemous || senses.length == 1)) {
      final sense = senses.first;
      return WsdResult(
        token: targetToken.token,
        lemma: targetToken.lemma,
        pos: targetToken.pos.toUpperCase(),
        isPolysemous: false,
        wsdMethod: 'monosemy_filter_bypass',
        senses: [
          WsdCandidate(
            rank: 1,
            score: 1.0,
            definitionEn: sense.definitionEn,
            translationFa: sense.translationFa,
          ),
        ],
      );
    }

    // Tier 2: Target-Token Vector Similarity via ONNX BEM
    HfEncoding? encoding;
    OnnxResult? embeddings;

    if (precomputedCtx != null) {
      encoding = precomputedCtx.$1;
      embeddings = precomputedCtx.$2;
    } else {
      final ctx = await encodeContextWindow(contextWindowText);
      if (ctx == null) {
        return _fallbackWithSenses(targetToken, senses, 'fallback_onnx_missing');
      }
      encoding = ctx.$1;
      embeddings = ctx.$2;
    }

    // Extract target token vector using char-to-token mapping
    final targetVec = _extractTargetTokenVector(
      encoding,
      embeddings,
      targetToken.startChar,
      targetToken.endChar,
    );

    if (targetVec == null) {
      return _fallbackWithSenses(targetToken, senses, 'fallback_vector_extraction');
    }

    // Calculate cosine similarity with each candidate sense vector
    final scoredSenses = <(double, String, String?)>[];

    for (final sense in senses) {
      if (sense.vectorBlob != null && sense.vectorBlob!.isNotEmpty) {
        final senseVec = _dequantizeVector(sense.vectorBlob!);
        final norm = _norm(senseVec);
        if (norm > 0) {
          _normalize(senseVec, norm);
        }
        final sim = _dotProduct(targetVec, senseVec);
        scoredSenses.add((sim, sense.definitionEn, sense.translationFa));
      } else {
        // Positional rank fallback score
        final fallbackScore = max(0.1, 1.0 - (sense.senseIndex - 1) * 0.15);
        scoredSenses.add(
            (fallbackScore, sense.definitionEn, sense.translationFa));
      }
    }

    // Sort by score descending
    scoredSenses.sort((a, b) => b.$1.compareTo(a.$1));

    final ranked = <WsdCandidate>[];
    for (int i = 0; i < min(topK, scoredSenses.length); i++) {
      final (score, defEn, transFa) = scoredSenses[i];
      ranked.add(WsdCandidate(
        rank: i + 1,
        score: max(0.0, min(1.0, score)),
        definitionEn: defEn,
        translationFa: transFa,
      ));
    }

    return WsdResult(
      token: targetToken.token,
      lemma: targetToken.lemma,
      pos: targetToken.pos.toUpperCase(),
      isPolysemous: true,
      wsdMethod: 'onnx_target_token_similarity',
      senses: ranked,
    );
  }

  /// Extracts the target token's vector from the context window embeddings.
  ///
  /// Maps character range [startChar, endChar) to sub-token indices
  /// using the HuggingFace encoding's char-to-token mapping, then
  /// averages the matched sub-token embeddings and L2-normalizes.
  Float32List? _extractTargetTokenVector(
    HfEncoding encoding,
    OnnxResult embeddings,
    int startChar,
    int endChar,
  ) {
    final matchedIndices = <int>{};

    for (int charIdx = startChar; charIdx < endChar; charIdx++) {
      final tIdx = encoding.charToToken(charIdx);
      if (tIdx != null && !matchedIndices.contains(tIdx)) {
        matchedIndices.add(tIdx);
      }
    }

    if (matchedIndices.isEmpty) {
      // Fallback to index 1 (first real token after [CLS])
      if (embeddings.tokenEmbeddings.length > 1) {
        return Float32List.fromList(embeddings.tokenEmbeddings[1]);
      }
      return null;
    }

    // Average all matched sub-token embeddings
    final dim = embeddings.tokenEmbeddings[0].length;
    final meanVec = Float32List(dim);

    for (final idx in matchedIndices) {
      if (idx < embeddings.tokenEmbeddings.length) {
        final vec = embeddings.tokenEmbeddings[idx];
        for (int d = 0; d < dim; d++) {
          meanVec[d] += vec[d];
        }
      }
    }

    final count = matchedIndices.length.toDouble();
    for (int d = 0; d < dim; d++) {
      meanVec[d] /= count;
    }

    // L2-normalize
    final norm = _norm(meanVec);
    if (norm > 0) {
      _normalize(meanVec, norm);
    }

    return meanVec;
  }

  /// Dequantizes an INT8 or Float32 vector blob to a Float32List.
  static Float32List _dequantizeVector(Uint8List blob) {
    if (blob.length == 384) {
      // INT8 quantized
      final floatList = Float32List(384);
      for (int i = 0; i < 384; i++) {
        floatList[i] = blob[i].toDouble() / 127.0;
      }
      return floatList;
    }
    // Already Float32
    return Float32List.view(blob.buffer, blob.offsetInBytes, blob.lengthInBytes ~/ 4);
  }

  /// Computes the L2 norm of a vector.
  static double _norm(Float32List vec) {
    double sum = 0;
    for (final v in vec) {
      sum += v * v;
    }
    return sqrt(sum);
  }

  /// Normalizes a vector in-place to unit length.
  static void _normalize(Float32List vec, double norm) {
    for (int i = 0; i < vec.length; i++) {
      vec[i] /= norm;
    }
  }

  /// Computes the dot product of two vectors.
  static double _dotProduct(Float32List a, Float32List b) {
    double sum = 0;
    final len = min(a.length, b.length);
    for (int i = 0; i < len; i++) {
      sum += a[i] * b[i];
    }
    return sum;
  }

  /// Returns a fallback WSD result when the word is not in the dictionary.
  WsdResult _fallbackResult(EngineTokenInfo targetToken, String reason) {
    return WsdResult(
      token: targetToken.token,
      lemma: targetToken.lemma,
      pos: targetToken.pos.toUpperCase(),
      isPolysemous: false,
      wsdMethod: 'fallback_$reason',
      senses: [
        WsdCandidate(
          rank: 1,
          score: 1.0,
          definitionEn: "Definition for '${targetToken.lemma}' (${targetToken.pos}).",
          translationFa: null,
        ),
      ],
    );
  }

  /// Returns a fallback WSD result with available senses ranked positionally.
  WsdResult _fallbackWithSenses(
      EngineTokenInfo targetToken, List senses, String reason) {
    return WsdResult(
      token: targetToken.token,
      lemma: targetToken.lemma,
      pos: targetToken.pos.toUpperCase(),
      isPolysemous: true,
      wsdMethod: 'fallback_$reason',
      senses: [
        for (int i = 0; i < min(5, senses.length); i++)
          WsdCandidate(
            rank: i + 1,
            score: round(max(0.1, 1.0 - i * 0.15)),
            definitionEn: senses[i].definitionEn,
            translationFa: senses[i].translationFa,
          ),
      ],
    );
  }

  static double round(double value, [int places = 3]) {
    final factor = pow(10, places).toDouble();
    return (value * factor).round() / factor;
  }
}
