import 'dart:developer' as developer;

import 'package:lexo_player/core/engine/hf_tokenizer.dart';
import 'package:lexo_player/core/engine/idiom_explainer.dart';
import 'package:lexo_player/core/engine/mwe_fast.dart';
import 'package:lexo_player/core/engine/onnx_service.dart';
import 'package:lexo_player/core/engine/serializer.dart';
import 'package:lexo_player/core/engine/span_builder.dart';
import 'package:lexo_player/core/engine/tokenizer.dart';
import 'package:lexo_player/core/engine/wsd_engine.dart';
import 'package:lexo_player/features/dictionary/data/unified_dictionary_repository.dart';
import 'package:lexo_player/core/models/engine_output.dart';

/// Configuration for the LexoEngine.
class EngineConfig {
  final bool useMonosemyFilter;
  final int topK;

  const EngineConfig({
    this.useMonosemyFilter = true,
    this.topK = 5,
  });
}

/// The main LexoEngine orchestrator.
///
/// Port of `engine/core.py` from LexoEngine. Ties together all inference
/// components into a single processing pipeline:
///
/// 1. Tokenize the sliding context window
/// 2. Filter target tokens
/// 3. Fast MWE detection (Aho-Corasick)
/// 4. Idiom explanation lookup
/// 5. WSD for each target token (single ONNX pass)
/// 6. Build hierarchical spans
/// 7. Serialize output
class LexoEngine {
  final UnifiedDictionaryRepository _db;
  final HfTokenizer _hfTokenizer;

  UnifiedDictionaryRepository get db => _db;
  HfTokenizer get hfTokenizer => _hfTokenizer;
  late final EngineTokenizer _tokenizer;
  late final OnnxService _onnxService;
  late final FastMweDetector _fastMwe;
  late final IdiomExplainer _idiomExplainer;
  late final WsdEngine _wsdEngine;
  late final HierarchicalSpanBuilder _spanBuilder;

  bool _isInitialized = false;

  LexoEngine({
    required UnifiedDictionaryRepository db,
    required HfTokenizer hfTokenizer,
    required OnnxService onnxService,
  })  : _db = db,
        _hfTokenizer = hfTokenizer,
        _onnxService = onnxService {
    _tokenizer = EngineTokenizer();
    _fastMwe = FastMweDetector(db);
    _idiomExplainer = IdiomExplainer(db);
    _wsdEngine = WsdEngine(
      db: db,
      hfTokenizer: hfTokenizer,
      onnxService: onnxService,
    );
    _spanBuilder = HierarchicalSpanBuilder();
  }

  /// Initializes the engine components (loads idioms into Aho-Corasick).
  Future<void> initialize() async {
    if (_isInitialized) return;

    developer.log('Initializing LexoEngine...', name: 'LexoEngine');

    await reloadDatabaseData();

    _isInitialized = true;
    developer.log('LexoEngine initialized.', name: 'LexoEngine');
  }

  /// Reloads DB-dependent engine components when the underlying DB changes.
  Future<void> reloadDatabaseData() async {
    developer.log('Reloading LexoEngine database data...', name: 'LexoEngine');
    await _fastMwe.loadIdioms();
    await _idiomExplainer.loadCache(forceReload: true);
    developer.log('LexoEngine database data reloaded.', name: 'LexoEngine');
  }

  /// Processes a single subtitle line through the full inference pipeline.
  ///
  /// [subtitleId] is the unique ID of the subtitle.
  /// [timestamp] is the time range string.
  /// [targetText] is the current subtitle text.
  /// [prevText] is the previous subtitle text (for sliding window context).
  /// [nextText] is the next subtitle text (for sliding window context).
  /// [config] is the engine configuration for this processing run.
  Future<EngineOutput> processSubtitle({
    required int subtitleId,
    required String timestamp,
    required String targetText,
    String? prevText,
    String? nextText,
    EngineConfig config = const EngineConfig(),
  }) async {
    await initialize();

    // Dynamically sync runtime feature toggles to sub-components.
    _wsdEngine.useMonosemyFilter = config.useMonosemyFilter;

    final startTime = DateTime.now().microsecondsSinceEpoch;

    // Build sliding window context
    final contextWindow = createSlidingWindowContext(
      subtitleId: subtitleId,
      timestamp: timestamp,
      targetText: targetText,
      prevText: prevText,
      nextText: nextText,
    );

    final windowText = contextWindow.slidingContextWindow;
    final tStart = contextWindow.targetStartChar;
    final tEnd = contextWindow.targetEndChar;

    // 1. Tokenize entire sliding context window
    final allTokens = _tokenizer.tokenize(windowText);

    // Filter tokens belonging to the target sentence
    final targetTokens = _tokenizer.filterTargetTokens(allTokens, tStart, tEnd);

    // 2. MWE & Idiom Detection
    final detectedMwes = <DetectedMwe>[];

    // 2a. Fast Pattern Matching (Aho-Corasick & Modified Patterns)
    final fastMatches = _fastMwe.detect(targetText, targetTokens);
    for (final match in fastMatches) {
      final canonical = match.canonicalForm;
      final explanation = _idiomExplainer.explainIdiom(
        sentenceText: targetText,
        phrase: canonical,
        detectedMethod: match.detectionMethod,
      );

      // Merge explanation onto the fast match
      detectedMwes.add(DetectedMwe(
        phrase: match.phrase,
        canonicalForm: explanation.canonicalForm,
        category: explanation.category,
        detectionMethod: match.detectionMethod,
        definitionEn: explanation.definitionEn ?? match.definitionEn,
        translationFa: explanation.translationFa ?? match.translationFa,
        confidence: explanation.confidence,
        inflectionNote: explanation.inflectionNote ?? match.inflectionNote,
        baseForm: explanation.baseForm ?? match.baseForm,
        tokens: match.tokens,
      ));
    }

    // 3. WSD for each target token (single ONNX sentence pass)
    final precomputedCtx = await _wsdEngine.encodeContextWindow(windowText);
    final wsdResultsByToken = <int, WsdResult>{};

    for (final tokenInfo in targetTokens) {
      if (tokenInfo.spacyPos == 'PUNCT' || tokenInfo.spacyPos == 'SPACE') {
        continue;
      }

      final wsdRes = await _wsdEngine.disambiguateWord(
        contextWindowText: windowText,
        targetToken: tokenInfo,
        topK: config.topK,
        precomputedCtx: precomputedCtx,
      );
      wsdResultsByToken[tokenInfo.tokenIndex] = wsdRes;
    }

    // 4. Build Hierarchical Spans (Parent-Child Tree)
    final hierarchicalSpans = _spanBuilder.buildSpans(
      targetTokens: targetTokens,
      targetStartCharInWindow: tStart,
      detectedMwes: detectedMwes,
      wsdResultsByToken: wsdResultsByToken,
    );

    final elapsedMs =
        (DateTime.now().microsecondsSinceEpoch - startTime) / 1000.0;

    return EngineSerializer.createOutput(
      subtitleId: contextWindow.subtitleId,
      timestamp: contextWindow.timestamp,
      targetSentence: contextWindow.targetSentence,
      slidingContextWindow: windowText,
      executionTimeMs: elapsedMs,
      hierarchicalSpans: hierarchicalSpans,
    );
  }

  /// Disposes of engine resources.
  void dispose() {
    _onnxService.dispose();
  }
}
