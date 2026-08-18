import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:lexo_player/features/dictionary/data/dictionary_providers.dart';
import 'package:lexo_player/core/engine/hf_tokenizer.dart';
import 'package:lexo_player/core/engine/lexo_engine.dart';
import 'package:lexo_player/core/engine/onnx_service.dart';
import 'package:lexo_player/features/dictionary/data/unified_dictionary_repository.dart';
import 'package:lexo_player/core/models/engine_output.dart';
import 'package:lexo_player/features/dictionary/data/manifest_providers.dart';
import 'package:lexo_player/features/subtitles/providers/subtitle_providers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Unified dictionary providers
// ─────────────────────────────────────────────────────────────────────────────

/// Repository for the unified dictionary.
final unifiedDictionaryRepositoryProvider =
    Provider<UnifiedDictionaryRepository>((ref) {
  final dbService = ref.watch(databaseServiceProvider);
  final repo = UnifiedDictionaryRepository(dbService);
  ref.onDispose(() => repo.close());
  return repo;
});

/// The currently selected unified dictionary ID.
final selectedUnifiedDictIdProvider = StateProvider<String?>((ref) => null);

/// Controls the active application language ('en' for English LTR, 'fa' for Persian RTL).
final appLanguageProvider = StateProvider<String>((ref) => 'en');

/// Tracks the user-facing status message during dictionary database loading / engine reload.
final dictLoadingStatusProvider = StateProvider<String?>((ref) => null);

/// Watches the selected unified dictionary and opens it reactively.
///
/// NOTE: Does NOT modify other providers during build (forbidden by Riverpod).
/// Callers that need loading status should track it separately.
final unifiedDictSwitcherProvider = FutureProvider<void>((ref) async {
  final repo = ref.read(unifiedDictionaryRepositoryProvider);
  final storage = ref.read(dictStorageManagerProvider);

  final dictId = ref.watch(selectedUnifiedDictIdProvider);

  if (dictId != null && dictId != 'none') {
    final path = await storage.getDictPath(dictId);
    await repo.openDatabase(path);
    developer.log('UnifiedDictSwitcher: Opened DB at $path',
        name: 'UnifiedDictSwitcher');

    // Reload engine idiom data if the engine is already created.
    final engine = ref.read(_lexoEngineHolderProvider);
    if (engine != null) {
      await engine.reloadDatabaseData();
    }
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// Engine initialization — eagerly loads vocab + ONNX + idiom cache
// ─────────────────────────────────────────────────────────────────────────────

/// Tracks whether the engine has finished initializing.
final engineReadyProvider = StateProvider<bool>((ref) => false);

/// Eagerly initializes the full engine pipeline at app startup.
///
/// This loads:
/// 1. HuggingFace vocab.json from bundled assets
/// 2. ONNX Runtime model (minilm_target_token.onnx)
/// 3. Aho-Corasick idiom automaton from dictionary.db
/// 4. Idiom explanation cache
///
/// Must be triggered early (e.g. in LexoPlayerApp.initState) so the engine
/// is ready before the user opens a video with subtitles.
final engineInitProvider = FutureProvider<void>((ref) async {
  developer.log('Engine init: starting…', name: 'EngineInit');

  try {
    // 1. Load vocab
    final hfTokenizer = await HfTokenizer.fromAsset();
    developer.log('Engine init: vocab loaded', name: 'EngineInit');

    // 2. Initialize ONNX Runtime
    final onnxService = RealOnnxService();
    await onnxService.initialize();
    developer.log(
        'Engine init: ONNX ready=${onnxService.isInitialized}',
        name: 'EngineInit');

    // 3. Create engine instance
    final db = ref.read(unifiedDictionaryRepositoryProvider);
    final engine = LexoEngine(
      db: db,
      hfTokenizer: hfTokenizer,
      onnxService: onnxService,
    );

    // Store in providers so downstream code and switcher can access the engine
    ref.read(_hfTokenizerHolderProvider.notifier).state = hfTokenizer;
    ref.read(_onnxServiceHolderProvider.notifier).state = onnxService;
    ref.read(_lexoEngineHolderProvider.notifier).state = engine;

    // 4. Ensure dictionary is open and initialize engine data if DB is ready
    await ref.read(unifiedDictSwitcherProvider.future);
    if (db.isReady) {
      await engine.initialize();
    }
    ref.read(engineReadyProvider.notifier).state = true;
    developer.log('Engine init: engine ready', name: 'EngineInit');

    ref.onDispose(() {
      engine.dispose();
      onnxService.dispose();
    });
  } catch (e, stack) {
    developer.log('Engine init FAILED: $e\n$stack',
        name: 'EngineInit', level: 1000);
    // Don't rethrow — let the app continue without the engine.
    // The subtitle overlay will show plain text without span interaction.
  }
});

int _vocabSize(HfTokenizer t) => 0; // placeholder — vocab size is internal

/// Holds the initialized HfTokenizer after startup.
final _hfTokenizerHolderProvider = StateProvider<HfTokenizer?>((ref) => null);

/// Holds the initialized OnnxService after startup.
final _onnxServiceHolderProvider = StateProvider<OnnxService?>((ref) => null);

/// Holds the initialized LexoEngine after startup.
final _lexoEngineHolderProvider = StateProvider<LexoEngine?>((ref) => null);

/// Convenience getter for the ready engine. Throws if called before init.
LexoEngine getEngine(WidgetRef ref) {
  final engine = ref.read(_lexoEngineHolderProvider);
  if (engine == null) {
    throw StateError('LexoEngine not initialized yet');
  }
  return engine;
}

// ─────────────────────────────────────────────────────────────────────────────
// Engine output providers
// ─────────────────────────────────────────────────────────────────────────────

/// The current engine configuration.
final engineConfigProvider = StateProvider<EngineConfig>((ref) {
  return const EngineConfig();
});

/// Processes the current subtitle through the engine pipeline.
///
/// Reactively re-runs when the active subtitle changes.
/// Waits for [engineInitProvider] so the engine is guaranteed ready.
final engineOutputProvider =
    FutureProvider.autoDispose<EngineOutput?>((ref) async {
  // Yield execution to the Flutter UI event loop so video frame rendering is never blocked on cue changes
  await Future.delayed(const Duration(milliseconds: 50));

  // Wait for the engine to be fully initialized before processing.
  await ref.watch(engineInitProvider.future);
  // Ensure the database switcher has completed so DB is open.
  await ref.watch(unifiedDictSwitcherProvider.future);

  final engine = ref.read(_lexoEngineHolderProvider);
  if (engine == null) return null;

  final activeText = ref.watch(activeSubtitleTextProvider);
  if (activeText == null || activeText.isEmpty) return null;

  final subtitleIndex = ref.watch(activeSubtitleIndexProvider) ?? 0;
  final config = ref.watch(engineConfigProvider);

  // Get previous and next subtitle texts for sliding window context
  final prevText = ref.watch(previousSubtitleTextProvider);
  final nextText = ref.watch(nextSubtitleTextProvider);
  final timestamp = ref.watch(activeSubtitleTimestampProvider);

  try {
    final output = await engine.processSubtitle(
      subtitleId: subtitleIndex,
      timestamp: timestamp ?? '00:00:00,000 --> 00:00:05,000',
      targetText: activeText,
      prevText: prevText,
      nextText: nextText,
      config: config,
    );
    developer.log(
        'Engine output: ${output.hierarchicalSpans.length} spans for "${activeText.substring(0, activeText.length.clamp(0, 50))}..."',
        name: 'LexoEngine');
    return output;
  } catch (e, stack) {
    developer.log('Engine processing error: $e\n$stack',
        name: 'LexoEngine', level: 1000);
    return null;
  }
});
