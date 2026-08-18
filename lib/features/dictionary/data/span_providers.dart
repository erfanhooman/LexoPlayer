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
class SpanHoverController {
  final Ref _ref;
  Timer? _debounceTimer;
  bool _wasPlaying = false;

  SpanHoverController(this._ref);

  /// Triggered when the pointer enters a word in the subtitle track.
  ///
  /// Cancels any pending resume timer, pauses the video, and pushes the
  /// matched engine span into [selectedSpanProvider] so the definition
  /// popup opens immediately.
  ///
  /// If the span has no meaningful data (no translations, only generic
  /// fallback WSD), the popup is not opened and the video is not paused.
  void onHoverEnter({
    required SpanModel span,
    required LayerLink layerLink,
    required BuildContext context,
  }) {
    // If a transition timer was already running, cancel it so we don't
    // resume playback, and keep the previous _wasPlaying state.
    if (_debounceTimer != null) {
      _debounceTimer!.cancel();
      _debounceTimer = null;
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
  void onHoverExit() {
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
  void onPopupHoverExit() {
    _startDebounceTimer();
  }

  /// Triggered on an explicit click/tap.
  ///
  /// Unlike temporary hover popups, explicit clicks pin the popup and
  /// disable automatic playback resume when the hover exits.
  /// If the span has no meaningful data, nothing happens.
  void onTap({
    required SpanModel span,
    required LayerLink layerLink,
    required BuildContext context,
  }) {
    _debounceTimer?.cancel();
    _debounceTimer = null;

    // Don't open the popup for words with no real data.
    if (!span.hasMeaningfulData) {
      _wasPlaying = false;
      return;
    }

    _wasPlaying = false; // Disable auto-resume for explicit clicks.

    final player = _ref.read(playerProvider);
    PlayerActions.pause(player);

    _ref.read(selectedSpanProvider.notifier).state = SelectedSpanData(
      span: span,
      layerLink: layerLink,
      context: context,
    );
  }

  /// Closes the popup and resumes playback if it was active before hovering.
  void closePopup() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _ref.read(selectedSpanProvider.notifier).state = null;
    if (_wasPlaying) {
      _wasPlaying = false;
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
