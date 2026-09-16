import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:lexo_player/core/database/database_service.dart';
import 'package:lexo_player/core/models/dictionary_result.dart';
import 'package:lexo_player/features/dictionary/data/dual_dictionary_repository.dart';
import 'package:lexo_player/features/dictionary/data/dict_selection_providers.dart';
import 'package:lexo_player/features/dictionary/data/manifest_providers.dart';
import 'package:lexo_player/features/video_player/providers/player_provider.dart';
import 'package:lexo_player/core/utils/word_tokenizer.dart';
import 'package:lexo_player/features/dictionary/domain/word_candidate_generator.dart';
import 'package:lexo_player/features/dictionary/domain/dictionary_lookup_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Database service singleton
// ─────────────────────────────────────────────────────────────────────────────

/// Global [DatabaseService] instance.
final databaseServiceProvider = Provider<DatabaseService>((ref) {
  final service = DatabaseService();
  ref.onDispose(() => service.closeAll());
  return service;
});

// ─────────────────────────────────────────────────────────────────────────────
// Dictionary repository singleton
// ─────────────────────────────────────────────────────────────────────────────

/// The [DualDictionaryRepository] backed by the database service.
///
/// This provider is a long-lived singleton. The active databases are switched
/// reactively by [dictionarySwitcherProvider] whenever the user changes their
/// dictionary selection.
final dictionaryRepositoryProvider = Provider<DualDictionaryRepository>((ref) {
  final dbService = ref.watch(databaseServiceProvider);
  final repo = DualDictionaryRepository(dbService);
  ref.onDispose(() => repo.dispose());
  return repo;
});

// ─────────────────────────────────────────────────────────────────────────────
// Reactive database switcher
// ─────────────────────────────────────────────────────────────────────────────

/// Watches the selected monolingual/bilingual IDs and reactively calls
/// [DualDictionaryRepository.switchDatabases] whenever they change.
///
/// This provider should be watched early in the widget tree (e.g. in the
/// root app widget) so that database switches happen immediately.
final dictionarySwitcherProvider = FutureProvider<void>((ref) async {
  final repo = ref.read(dictionaryRepositoryProvider);
  final storage = ref.read(dictStorageManagerProvider);

  final monoId = ref.watch(selectedMonolingualIdProvider);
  final biId = ref.watch(selectedBilingualIdProvider);

  String? monoPath;
  String? biPath;

  if (monoId != null && monoId != 'none') {
    monoPath = await storage.getDictPath(monoId);
  }
  if (biId != null && biId != 'none') {
    biPath = await storage.getDictPath(biId);
  }

  await repo.switchDatabases(
    monolingualPath: monoPath,
    bilingualPath: biPath,
  );

  developer.log(
    'DictionarySwitcher: Active databases updated — '
    'mono=${monoId ?? "none"}, bi=${biId ?? "none"}',
    name: 'DictSwitcher',
  );
});

// ─────────────────────────────────────────────────────────────────────────────
// Candidate generator & Lookup domain service singletons
// ─────────────────────────────────────────────────────────────────────────────

/// Provider for [IWordCandidateGenerator].
final wordCandidateGeneratorProvider = Provider<IWordCandidateGenerator>((ref) {
  return const WordCandidateGenerator(maxWords: 8);
});

/// Provider for [DictionaryLookupService].
final dictionaryLookupServiceProvider =
    Provider<DictionaryLookupService>((ref) {
  final repo = ref.watch(dictionaryRepositoryProvider);
  final candidateGen = ref.watch(wordCandidateGeneratorProvider);
  return DictionaryLookupService(
    repository: repo,
    candidateGenerator: candidateGen,
  );
});

// ─────────────────────────────────────────────────────────────────────────────
// User interaction state
// ─────────────────────────────────────────────────────────────────────────────

class SelectedTokenData {
  final List<TokenSpan> lineTokens;
  final int tokenIndex;

  SelectedTokenData(this.lineTokens, this.tokenIndex);
}

/// The token data currently selected by the user for lookup.
/// `null` means no word is selected and the popup should be hidden.
final selectedTokenProvider = StateProvider<SelectedTokenData?>((ref) => null);

/// The [LayerLink] of the word widget that triggered the popup.
/// Used by [CompositedTransformFollower] on desktop to position the popup.
final selectedTokenLayerLinkProvider = StateProvider<LayerLink?>((ref) => null);

/// The [BuildContext] of the word widget that triggered the popup.
/// Used to calculate viewport boundaries for popup positioning.
final selectedTokenContextProvider =
    StateProvider<BuildContext?>((ref) => null);

// ─────────────────────────────────────────────────────────────────────────────
// Lookup result provider (async)
// ─────────────────────────────────────────────────────────────────────────────

/// Performs the dictionary lookup when [selectedTokenProvider] changes.
///
/// Returns an empty list when no token is selected or no dictionaries are loaded;
/// otherwise returns a list of [DictionaryResult]s matching the generated phrases.
final lookupResultProvider =
    FutureProvider.autoDispose<List<DictionaryResult>>((ref) async {
  final data = ref.watch(selectedTokenProvider);
  if (data == null) return [];

  // Ensure the switcher has completed so DBs are ready.
  await ref.watch(dictionarySwitcherProvider.future);

  final lookupService = ref.read(dictionaryLookupServiceProvider);
  return lookupService.lookupToken(
    lineTokens: data.lineTokens,
    targetIndex: data.tokenIndex,
  );
});

// ─────────────────────────────────────────────────────────────────────────────
// Hover Interaction and Auto-playback debouncing
// ─────────────────────────────────────────────────────────────────────────────

/// Provider for coordinating hover lookup and playback auto-resume debouncing.
final hoverPlaybackTimerProvider = Provider<HoverPlaybackTimer>((ref) {
  return HoverPlaybackTimer(ref);
});

/// Controls the pause/play and lookup behavior on token hover.
///
/// Implements a debounced transition strategy to prevent rapid start/stop calls
/// to the underlying media player when the user sweeps their mouse across
/// sequential words in the subtitle track.
class HoverPlaybackTimer {
  final Ref _ref;
  Timer? _debounceTimer;
  bool _wasPlaying = false;

  /// Key of the last explicitly tapped word (`index:text`), if pinned.
  String? _pinnedKey;
  bool _pinnedWasPlaying = false;

  HoverPlaybackTimer(this._ref);

  String _tapKey(List<TokenSpan> lineTokens, int tokenIndex) {
    final text = (tokenIndex >= 0 && tokenIndex < lineTokens.length)
        ? lineTokens[tokenIndex].text
        : '$tokenIndex';
    return '$tokenIndex:$text:${lineTokens.length}';
  }

  /// Triggered when the pointer enters a word token in the subtitle track.
  void onHoverEnter(List<TokenSpan> lineTokens, int tokenIndex,
      LayerLink layerLink, BuildContext context) {
    final key = _tapKey(lineTokens, tokenIndex);
    if (_pinnedKey != null && _pinnedKey == key) {
      _debounceTimer?.cancel();
      _debounceTimer = null;
      return;
    }

    final player = _ref.read(playerProvider);

    // If a transition timer was already running, cancel it so we don't
    // resume playback, and keep the previous _wasPlaying state.
    if (_debounceTimer != null) {
      _debounceTimer!.cancel();
      _debounceTimer = null;
    } else if (_pinnedKey != null) {
      _wasPlaying = _pinnedWasPlaying;
      _pinnedKey = null;
      _pinnedWasPlaying = false;
    } else {
      _wasPlaying = player.state.playing;
    }

    if (player.state.playing) {
      PlayerActions.pause(player);
    }

    _ref.read(selectedTokenProvider.notifier).state =
        SelectedTokenData(lineTokens, tokenIndex);
    _ref.read(selectedTokenLayerLinkProvider.notifier).state = layerLink;
    _ref.read(selectedTokenContextProvider.notifier).state = context;
  }

  /// Triggered when the pointer exits a word token in the subtitle track.
  /// Ignored while a tap-pinned popup is open (dismiss via second tap).
  void onHoverExit() {
    if (_pinnedKey != null) return;
    _startDebounceTimer();
  }

  /// Triggered when the pointer enters the dictionary popup container.
  ///
  /// Cancels the debounce timer so the definition remains open and the video
  /// remains paused while the user is reading or interacting with the popup.
  void onPopupHoverEnter() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }

  /// Triggered when the pointer exits the dictionary popup container.
  /// Ignored while pinned.
  void onPopupHoverExit() {
    if (_pinnedKey != null) return;
    _startDebounceTimer();
  }

  /// Triggered on an explicit click/tap.
  ///
  /// Tapping the same pinned word again toggles closed + resumes when
  /// appropriate (touch-friendly, no hover needed).
  void onTap(List<TokenSpan> lineTokens, int tokenIndex, LayerLink layerLink,
      BuildContext context) {
    final player = _ref.read(playerProvider);
    final key = _tapKey(lineTokens, tokenIndex);
    final current = _ref.read(selectedTokenProvider);

    if (_pinnedKey != null &&
        _pinnedKey == key &&
        current != null &&
        current.tokenIndex == tokenIndex) {
      _debounceTimer?.cancel();
      _debounceTimer = null;
      _ref.read(selectedTokenProvider.notifier).state = null;
      _ref.read(selectedTokenLayerLinkProvider.notifier).state = null;
      _ref.read(selectedTokenContextProvider.notifier).state = null;
      final shouldResume = _pinnedWasPlaying;
      _pinnedKey = null;
      _pinnedWasPlaying = false;
      _wasPlaying = false;
      if (shouldResume) {
        PlayerActions.play(player);
      }
      return;
    }

    _debounceTimer?.cancel();
    _debounceTimer = null;
    final wasPlayingBefore =
        player.state.playing || _wasPlaying || _pinnedWasPlaying;
    _pinnedKey = key;
    _pinnedWasPlaying = wasPlayingBefore;
    _wasPlaying = false; // Disable auto-resume for explicit clicks.

    PlayerActions.pause(player);

    _ref.read(selectedTokenProvider.notifier).state =
        SelectedTokenData(lineTokens, tokenIndex);
    _ref.read(selectedTokenLayerLinkProvider.notifier).state = layerLink;
    _ref.read(selectedTokenContextProvider.notifier).state = context;
  }

  /// Closes the popup and resumes only if playback was active before.
  void closePopup() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _ref.read(selectedTokenProvider.notifier).state = null;
    _ref.read(selectedTokenLayerLinkProvider.notifier).state = null;
    _ref.read(selectedTokenContextProvider.notifier).state = null;
    final shouldResume = _wasPlaying || _pinnedWasPlaying;
    _wasPlaying = false;
    _pinnedWasPlaying = false;
    _pinnedKey = null;
    if (shouldResume) {
      PlayerActions.play(_ref.read(playerProvider));
    }
  }

  void _startDebounceTimer() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 250), () {
      final player = _ref.read(playerProvider);

      // Clear lookup providers to hide the definition popup.
      _ref.read(selectedTokenProvider.notifier).state = null;
      _ref.read(selectedTokenLayerLinkProvider.notifier).state = null;
      _ref.read(selectedTokenContextProvider.notifier).state = null;

      // Resume playing if the video was active prior to hovering.
      if (_wasPlaying) {
        PlayerActions.play(player);
        _wasPlaying = false;
      }
      _debounceTimer = null;
    });
  }
}
