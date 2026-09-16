import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:lexo_player/core/models/engine_output.dart';
import 'package:lexo_player/features/video_player/providers/player_provider.dart';

/// Selected span data for the definition popup.
class SelectedSpanData {
  final SpanModel span;
  final LayerLink layerLink;
  final BuildContext context;

  SelectedSpanData({
    required this.span,
    required this.layerLink,
    required this.context,
  });
}

/// Provider for the currently selected span.
final selectedSpanProvider = StateProvider<SelectedSpanData?>((ref) => null);

/// Controller for coordinating hover lookup and playback auto-resume
/// debouncing — mirrors the legacy `HoverPlaybackTimer` behavior but
/// drives the new engine's [selectedSpanProvider].
///
/// Interaction contract (preserved + extended for touch):
/// - **Hover (desktop):** pauses + shows definition, exit resumes (debounced).
/// - **Tap / click (all platforms):** pauses + shows definition (pinned, no
///   auto-resume). Tapping the **same** word again closes the popup and
///   resumes playback if it was playing before (toggle). This gives phones
///   (no hover) a way to open *and* dismiss definitions.
class SpanHoverController {
  final Ref _ref;
  Timer? _debounceTimer;
  bool _wasPlaying = false;

  /// SpanId of the last explicitly tapped (pinned) word, if any.
  String? _pinnedSpanId;

  /// Whether the video was playing before the current pinned selection.
  /// Used to resume on second-tap toggle / explicit close.
  bool _pinnedWasPlaying = false;

  SpanHoverController(this._ref);

  /// Whether a word is currently pinned open via tap.
  bool get isPinned => _pinnedSpanId != null;

  /// Triggered when the pointer enters a word in the subtitle track.
  ///
  /// Cancels any pending resume timer, pauses the video, and pushes the
  /// matched engine span into [selectedSpanProvider] so the definition
  /// popup opens immediately.
  ///
  /// If the span has no meaningful data (no translations, only generic
  /// fallback WSD), the popup is not opened and the video is not paused.
  ///
  /// If a word is currently pinned via tap and the hover moves to a
  /// *different* word, the pin is transferred to the hover flow so the
  /// original playing state is preserved for auto-resume.
  void onHoverEnter({
    required SpanModel span,
    required LayerLink layerLink,
    required BuildContext context,
  }) {
    final key = span.spanId;
    // Hovering the currently pinned word — keep the pinned popup as-is.
    if (_pinnedSpanId != null && _pinnedSpanId == key) {
      _debounceTimer?.cancel();
      _debounceTimer = null;
      return;
    }

    // If a transition timer was already running, cancel it so we don't
    // resume playback, and keep the previous _wasPlaying state.
    if (_debounceTimer != null) {
      _debounceTimer!.cancel();
      _debounceTimer = null;
    } else if (_pinnedSpanId != null) {
      // Moving from a pinned word to a different hovered word: carry the
      // original playing state into the hover flow, then unpin.
      _wasPlaying = _pinnedWasPlaying;
      _pinnedSpanId = null;
      _pinnedWasPlaying = false;
    } else {
      final player = _ref.read(playerProvider);
      _wasPlaying = player.state.playing;
    }

    // Don't open the popup or pause for words with no real data.
    if (!span.hasMeaningfulData) return;

    final player = _ref.read(playerProvider);
    if (player.state.playing) {
      PlayerActions.pause(player);
    }

    _ref.read(selectedSpanProvider.notifier).state = SelectedSpanData(
      span: span,
      layerLink: layerLink,
      context: context,
    );
  }

  /// Triggered when the pointer exits a word in the subtitle track.
  ///
  /// Ignored while a word is pinned via tap — the pinned popup must stay
  /// open until an explicit second tap / outside tap / Escape.
  void onHoverExit() {
    if (_pinnedSpanId != null) return;
    _startDebounceTimer();
  }

  /// Triggered when the pointer enters the definition popup container.
  ///
  /// Cancels the debounce timer so the popup remains open and the video
  /// remains paused while the user is reading or interacting with it.
  void onPopupHoverEnter() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }

  /// Triggered when the pointer exits the definition popup container.
  ///
  /// Ignored while pinned — a tapped word stays open until second tap /
  /// outside tap / Escape. Only unpinned hover previews auto-hide.
  void onPopupHoverExit() {
    if (_pinnedSpanId != null) return;
    _startDebounceTimer();
  }

  /// Triggered on an explicit click/tap.
  ///
  /// Unlike temporary hover popups, explicit clicks pin the popup and
  /// disable automatic playback resume when the hover exits.
  /// If the span has no meaningful data, nothing happens.
  ///
  /// Tapping the *same* pinned word a second time toggles the popup closed
  /// and resumes playback if it was playing before the first tap. This is
  /// the primary open/dismiss gesture on touch devices (no hover).
  void onTap({
    required SpanModel span,
    required LayerLink layerLink,
    required BuildContext context,
  }) {
    final player = _ref.read(playerProvider);
    final key = span.spanId;
    final current = _ref.read(selectedSpanProvider);

    // Toggle-off: second tap on the same pinned word closes + resumes.
    if (_pinnedSpanId != null &&
        _pinnedSpanId == key &&
        current != null &&
        current.span.spanId == key) {
      _debounceTimer?.cancel();
      _debounceTimer = null;
      _ref.read(selectedSpanProvider.notifier).state = null;
      final shouldResume = _pinnedWasPlaying;
      _pinnedSpanId = null;
      _pinnedWasPlaying = false;
      _wasPlaying = false;
      if (shouldResume) {
        PlayerActions.play(player);
      }
      return;
    }

    _debounceTimer?.cancel();
    _debounceTimer = null;

    // Don't open the popup for words with no real data.
    if (!span.hasMeaningfulData) {
      return;
    }

    // Capture the true pre-interaction playing state: the player may
    // already be paused due to an active hover preview (_wasPlaying) or a
    // previous pin on another word (_pinnedWasPlaying).
    final wasPlayingBefore =
        player.state.playing || _wasPlaying || _pinnedWasPlaying;

    _pinnedSpanId = key;
    _pinnedWasPlaying = wasPlayingBefore;
    _wasPlaying = false; // Disable hover auto-resume for explicit clicks.

    PlayerActions.pause(player);

    _ref.read(selectedSpanProvider.notifier).state = SelectedSpanData(
      span: span,
      layerLink: layerLink,
      context: context,
    );
  }

  /// Closes the popup and resumes playback if it was active before hovering
  /// *or* before the pinned tap.
  void closePopup() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _ref.read(selectedSpanProvider.notifier).state = null;
    final shouldResume = _wasPlaying || _pinnedWasPlaying;
    _wasPlaying = false;
    _pinnedWasPlaying = false;
    _pinnedSpanId = null;
    if (shouldResume) {
      PlayerActions.play(_ref.read(playerProvider));
    }
  }

  void _startDebounceTimer() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 250), () {
      // Clear the selected span to hide the definition popup.
      _ref.read(selectedSpanProvider.notifier).state = null;

      // Resume playing if the video was active prior to hovering.
      final player = _ref.read(playerProvider);
      if (_wasPlaying) {
        PlayerActions.play(player);
        _wasPlaying = false;
      }
      _debounceTimer = null;
    });
  }
}

/// Provider for the singleton [SpanHoverController].
final spanHoverControllerProvider = Provider<SpanHoverController>((ref) {
  return SpanHoverController(ref);
});
