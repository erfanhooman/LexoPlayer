import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:developer' as developer;
import 'package:lexo_player/features/subtitles/providers/subtitle_providers.dart';
import 'package:lexo_player/core/models/subtitle_block.dart';
import 'package:lexo_player/main.dart';

/// GlobalKey for accessing the [VideoState] to trigger fullscreen natively.
final videoKeyProvider = Provider.autoDispose<GlobalKey<VideoState>>((ref) {
  return GlobalKey<VideoState>();
});

// ---------------------------------------------------------------------------
// Player & VideoController lifecycle providers
// ---------------------------------------------------------------------------

/// The core media_kit [Player] instance, kept alive for the app's lifetime.
final playerProvider = Provider.autoDispose<Player>((ref) {
  developer.log('Creating new native Player instance', name: 'playerProvider');
  final player = Player(
    configuration: const PlayerConfiguration(
      title: 'LexoPlayer',
    ),
  );

  try {
    final dynamic nativePlayer = player.platform;
    nativePlayer.setProperty('volume-max', '200');
  } catch (_) {}

  String? lastSavedUri;
  int lastSavedSecs = 0;

  final subscription = player.stream.position.listen((position) async {
    final playlist = player.state.playlist;
    if (playlist.index >= 0 && playlist.index < playlist.medias.length) {
      final currentUri = playlist.medias[playlist.index].uri;
      final currentSecs = position.inSeconds;

      // Reset tracking variables if the active media URI changes.
      if (currentUri != lastSavedUri) {
        lastSavedUri = currentUri;
        lastSavedSecs = currentSecs;
        return;
      }

      if (position.inSeconds > 0 && (currentSecs - lastSavedSecs).abs() >= 5) {
        lastSavedSecs = currentSecs;
        final totalDuration = player.state.duration;
        await _savePlaybackPosition(currentUri, position, totalDuration);
      }
    }
  });

  ref.onDispose(() {
    developer.log('Disposing native Player instance', name: 'playerProvider');

    // Save final position on dispose
    final playlist = player.state.playlist;
    if (playlist.index >= 0 && playlist.index < playlist.medias.length) {
      final currentUri = playlist.medias[playlist.index].uri;
      final position = player.state.position;
      final totalDuration = player.state.duration;
      _savePlaybackPosition(currentUri, position, totalDuration);
    }

    subscription.cancel();
    player.dispose();
  });
  return player;
});

// Helper functions for persisting playback position
String _normalizeUriOrPath(String input) {
  String normalized = input;
  try {
    final uri = Uri.parse(input);
    if (uri.isScheme('file')) {
      normalized = uri.toFilePath();
    }
  } catch (_) {
    // If parsing as URI fails, just treat as raw path
  }

  // Normalize Windows path separators and drive letter casing
  normalized = normalized.replaceAll('\\', '/');

  // If it starts with drive letter (e.g. "C:/"), uppercase it consistently.
  final driveLetterRegex = RegExp(r'^([a-zA-Z]):/');
  final match = driveLetterRegex.firstMatch(normalized);
  if (match != null) {
    final drive = match.group(1)!.toUpperCase();
    normalized = normalized.replaceFirst(driveLetterRegex, '$drive:/');
  }

  return normalized;
}

String _getPlaybackPositionKey(String uri) {
  final normalized = _normalizeUriOrPath(uri);
  final bytes = utf8.encode(normalized);
  final digest = md5.convert(bytes);
  return 'video_pos_$digest';
}

Future<void> _savePlaybackPosition(
    String uri, Duration position, Duration totalDuration) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final key = _getPlaybackPositionKey(uri);

    // If we are close to the end (within 5 seconds), reset to start
    final isNearEnd = totalDuration > Duration.zero &&
        (totalDuration - position).inSeconds < 5;

    if (isNearEnd || position.inSeconds <= 0) {
      await prefs.remove(key);
      developer.log('Cleared saved position for $uri (near end or <= 0)',
          name: 'PlayerPosition');
    } else {
      await prefs.setInt(key, position.inMilliseconds);
      developer.log('Saved position for $uri: ${position.inSeconds}s',
          name: 'PlayerPosition');
    }
  } catch (e) {
    developer.log('Error saving playback position: $e',
        name: 'PlayerPosition', level: 900);
  }
}

Future<Duration?> _loadPlaybackPosition(String uri) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final key = _getPlaybackPositionKey(uri);
    final ms = prefs.getInt(key);
    if (ms != null) {
      return Duration(milliseconds: ms);
    }
  } catch (e) {
    developer.log('Error loading playback position: $e',
        name: 'PlayerPosition', level: 900);
  }
  return null;
}

/// The [VideoController] bound to our [Player].
final videoControllerProvider = Provider.autoDispose<VideoController>((ref) {
  final player = ref.watch(playerProvider);
  return VideoController(player);
});

// ---------------------------------------------------------------------------
// Stream-derived state providers (scoped rebuilds only)
// ---------------------------------------------------------------------------

/// Current playback position as a stream.
final positionProvider = StreamProvider.autoDispose<Duration>((ref) {
  final player = ref.watch(playerProvider);
  return player.stream.position;
});

/// Total duration of the loaded media.
final durationProvider = StreamProvider.autoDispose<Duration>((ref) {
  final player = ref.watch(playerProvider);
  return player.stream.duration;
});

/// Whether the player is currently playing.
final playingProvider = StreamProvider.autoDispose<bool>((ref) {
  final player = ref.watch(playerProvider);
  return player.stream.playing;
});

/// Current buffering progress percentage (0.0 – 1.0).
final bufferingProvider = StreamProvider.autoDispose<bool>((ref) {
  final player = ref.watch(playerProvider);
  return player.stream.buffering;
});

/// Current volume (0.0 – 100.0).
final volumeProvider = StreamProvider.autoDispose<double>((ref) {
  final player = ref.watch(playerProvider);
  return player.stream.volume;
});

/// Current playback rate.
final rateProvider = StreamProvider.autoDispose<double>((ref) {
  final player = ref.watch(playerProvider);
  return player.stream.rate;
});

/// Available audio tracks for the loaded media.
final audioTracksProvider = StreamProvider.autoDispose<List<AudioTrack>>((ref) {
  final player = ref.watch(playerProvider);
  return player.stream.tracks.map((tracks) => tracks.audio);
});

/// Currently selected audio track.
final currentAudioTrackProvider = StreamProvider.autoDispose<AudioTrack>((ref) {
  final player = ref.watch(playerProvider);
  return player.stream.track.map((track) => track.audio);
});

// ---------------------------------------------------------------------------
// User-controlled state
// ---------------------------------------------------------------------------

/// Playback speed selection state.
final playbackSpeedProvider = StateProvider.autoDispose<double>((ref) => 1.0);

/// Available speed presets.
const List<double> availableSpeeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

/// Mute toggle state.
final isMutedProvider = StateProvider.autoDispose<bool>((ref) => false);

/// Previous volume before muting (for restore).
final preMuteVolumeProvider = StateProvider.autoDispose<double>((ref) => 100.0);

/// Toggle state for time label: false = elapsed time, true = remaining time (-).
final showRemainingTimeProvider =
    StateProvider.autoDispose<bool>((ref) => false);

/// Data model for the Volume HUD indicator overlay.
class VolumeHudData {
  final double volume;
  final bool isMuted;
  final int id;

  const VolumeHudData({
    required this.volume,
    required this.isMuted,
    required this.id,
  });
}

/// Volume HUD state provider for smooth on-screen percentage toast.
final volumeHudProvider =
    StateProvider.autoDispose<VolumeHudData?>((ref) => null);

/// Aspect ratio mode enumeration.
enum AspectRatioMode { fit, fill, stretch, ratio16x9, ratio4x3 }

/// Current aspect ratio mode.
final aspectRatioProvider =
    StateProvider.autoDispose<AspectRatioMode>((ref) => AspectRatioMode.fit);

/// Fullscreen state.
final isFullscreenProvider = StateProvider.autoDispose<bool>((ref) => false);

/// Whether a video file is currently loaded.
final isVideoLoadedProvider = StateProvider.autoDispose<bool>((ref) => false);

/// Whether the player control bar is currently visible.
final controlsVisibleProvider = StateProvider.autoDispose<bool>((ref) => true);

// ---------------------------------------------------------------------------
// Player control actions as a utility class
// ---------------------------------------------------------------------------

/// Centralised helper for dispatching player commands.
class PlayerActions {
  PlayerActions._();

  /// Opens a media file or network URL and disables native subtitle rendering.
  static Future<void> openMedia(Player player, String uri) async {
    // Save current media position (if any) before opening the new one
    try {
      final playlist = player.state.playlist;
      if (playlist.index >= 0 && playlist.index < playlist.medias.length) {
        final oldUri = playlist.medias[playlist.index].uri;
        final oldPosition = player.state.position;
        final oldDuration = player.state.duration;
        await _savePlaybackPosition(oldUri, oldPosition, oldDuration);
      }
    } catch (e) {
      developer.log('Failed to save previous video state: $e',
          name: 'PlayerActions');
    }

    final mediaPathOrUri = cleanVideoPathOrUri(uri) ?? uri;

    // Load the saved position BEFORE opening the media to prevent race conditions
    // with the position stream listener.
    final savedPosition = await _loadPlaybackPosition(mediaPathOrUri);

    developer.log('Opening media: $mediaPathOrUri', name: 'PlayerActions');
    await player.open(Media(mediaPathOrUri), play: true);
    // Suppress native subtitle track – we render our own overlay.
    await player.setSubtitleTrack(SubtitleTrack.no());

    if (savedPosition != null && savedPosition.inSeconds > 0) {
      developer.log('Resuming playback at: ${savedPosition.inSeconds}s',
          name: 'PlayerActions');
      try {
        Duration dur = player.state.duration;
        if (dur <= Duration.zero) {
          try {
            dur = await player.stream.duration
                .firstWhere((d) => d > Duration.zero)
                .timeout(const Duration(seconds: 4));
          } catch (_) {}
        }

        // If saved position is near the end (within 5 seconds), reset to start instead of jumping to end.
        if (dur > Duration.zero && (dur - savedPosition).inSeconds < 5) {
          developer.log(
              'Saved position is near end of video. Resuming from start.',
              name: 'PlayerActions');
          await player.seek(Duration.zero);
        } else {
          await Future.delayed(const Duration(milliseconds: 200));
          await player.seek(savedPosition);
        }
      } catch (e) {
        developer.log('Error/Timeout during seek: $e', name: 'PlayerActions');
        await player.seek(savedPosition);
      }
    }

    await player.play();
  }

  static Future<void> play(Player player) => player.play();
  static Future<void> pause(Player player) => player.pause();
  static Future<void> playOrPause(Player player) => player.playOrPause();

  /// Stop playback, but explicitly save the position first so it is not lost.
  static Future<void> stop(Player player) async {
    await player.pause();
    await saveCurrentPosition(player);
    await player.stop();
  }

  static Future<void> saveCurrentPosition(Player player) async {
    final playlist = player.state.playlist;
    if (playlist.index >= 0 && playlist.index < playlist.medias.length) {
      final currentUri = playlist.medias[playlist.index].uri;
      final position = player.state.position;
      final totalDuration = player.state.duration;
      await _savePlaybackPosition(currentUri, position, totalDuration);
    }
  }

  static Duration? _pendingSeekPosition;
  static DateTime? _pendingSeekTime;

  static Duration _getEffectivePosition(Player player) {
    if (_pendingSeekPosition != null && _pendingSeekTime != null) {
      if (DateTime.now().difference(_pendingSeekTime!) <
          const Duration(milliseconds: 1200)) {
        return _pendingSeekPosition!;
      }
    }
    return player.state.position;
  }

  /// Seek to an absolute position.
  static Future<void> seek(Player player, Duration position) {
    _pendingSeekPosition = position;
    _pendingSeekTime = DateTime.now();
    return player.seek(position);
  }

  /// Seek forward by a relative [delta].
  static Future<void> seekRelative(Player player, Duration delta) async {
    final current = _getEffectivePosition(player);
    final target = current + delta;
    final clamped = target < Duration.zero ? Duration.zero : target;
    _pendingSeekPosition = clamped;
    _pendingSeekTime = DateTime.now();
    await player.seek(clamped);
  }

  /// Seeks to the start timestamp of the NEXT subtitle sentence if smart seeking is enabled.
  /// If smart seeking is disabled or no upcoming subtitle exists,
  /// falls back to standard +10s relative seeking based on time.
  static Future<void> seekNextSubtitle(
    dynamic ref,
    Player player, {
    Duration fallbackDelta = const Duration(seconds: 10),
  }) async {
    final smartSeekEnabled = ref.read(smartSubtitleSeekProvider);
    if (!smartSeekEnabled) {
      await seekRelative(player, fallbackDelta);
      return;
    }

    final selected = ref.read(selectedSubtitleProvider);
    if (selected == null || selected.id == 'none') {
      await seekRelative(player, fallbackDelta);
      return;
    }

    final initialPos = _getEffectivePosition(player);

    final rawBlocks = selected.externalBlocks ?? ref.read(subtitleListProvider);
    if (rawBlocks.isNotEmpty) {
      // Guarantee strictly sorted list of blocks to prevent random jumps with Persian/custom SRTs
      final blocks = List<SubtitleBlock>.from(rawBlocks)
        ..sort((a, b) => a.startTime.compareTo(b.startTime));

      final upcoming = blocks.where(
        (b) => b.startTime > initialPos + const Duration(milliseconds: 150),
      );

      if (upcoming.isNotEmpty) {
        final target = upcoming.first.startTime;
        _pendingSeekPosition = target;
        _pendingSeekTime = DateTime.now();
        await player.seek(target);
        return;
      }

      // No upcoming subtitle remaining — fallback to time-based seek
      await seekRelative(player, fallbackDelta);
      return;
    }

    // Embedded softsub track – use native MPV sub-seek command
    try {
      final dynamic nativePlayer = player.platform;
      await nativePlayer.command(['sub-seek', '1']);
      await Future.delayed(const Duration(milliseconds: 40));
      final newPos = player.state.position;

      // Update pending seek position to new MPV position
      _pendingSeekPosition = newPos;
      _pendingSeekTime = DateTime.now();
    } catch (_) {
      await seekRelative(player, fallbackDelta);
    }
  }

  /// Seeks to the start timestamp of the PREVIOUS subtitle sentence if smart seeking is enabled.
  /// If smart seeking is disabled or no previous subtitle exists,
  /// falls back to standard -10s relative seeking based on time.
  static Future<void> seekPreviousSubtitle(
    dynamic ref,
    Player player, {
    Duration fallbackDelta = const Duration(seconds: -10),
  }) async {
    final smartSeekEnabled = ref.read(smartSubtitleSeekProvider);
    if (!smartSeekEnabled) {
      await seekRelative(player, fallbackDelta);
      return;
    }

    final selected = ref.read(selectedSubtitleProvider);
    if (selected == null || selected.id == 'none') {
      await seekRelative(player, fallbackDelta);
      return;
    }

    final initialPos = _getEffectivePosition(player);

    final rawBlocks = selected.externalBlocks ?? ref.read(subtitleListProvider);
    if (rawBlocks.isNotEmpty) {
      // Guarantee strictly sorted list of blocks to prevent random jumps with Persian/custom SRTs
      final blocks = List<SubtitleBlock>.from(rawBlocks)
        ..sort((a, b) => a.startTime.compareTo(b.startTime));

      final prevBlocks = blocks.where(
        (b) => b.startTime < initialPos - const Duration(milliseconds: 150),
      );

      if (prevBlocks.isNotEmpty) {
        final target = prevBlocks.last.startTime;
        _pendingSeekPosition = target;
        _pendingSeekTime = DateTime.now();
        await player.seek(target);
        return;
      }

      // No previous subtitle remaining — fallback to time-based seek
      await seekRelative(player, fallbackDelta);
      return;
    }

    // Embedded softsub track – use native MPV sub-seek command
    try {
      final dynamic nativePlayer = player.platform;
      await nativePlayer.command(['sub-seek', '-1']);
      await Future.delayed(const Duration(milliseconds: 40));
      final newPos = player.state.position;

      // Update pending seek position to new MPV position
      _pendingSeekPosition = newPos;
      _pendingSeekTime = DateTime.now();
    } catch (_) {
      await seekRelative(player, fallbackDelta);
    }
  }

  /// Set playback speed.
  static Future<void> setSpeed(Player player, double speed) =>
      player.setRate(speed);

  /// Set volume (0 – 200%) and trigger on-screen HUD indicator.
  static Future<void> setVolume(
      Player player, double volume, WidgetRef ref) async {
    final clamped = volume.clamp(0.0, 200.0);
    await player.setVolume(clamped);
    if (clamped > 0 && ref.read(isMutedProvider)) {
      ref.read(isMutedProvider.notifier).state = false;
    }
    triggerVolumeHud(ref, clamped, clamped == 0 || ref.read(isMutedProvider));
  }

  /// Relative volume adjustment (e.g. +5% or -5%) for keyboard shortcuts.
  static Future<void> adjustVolumeRelative(
      Player player, double delta, WidgetRef ref) async {
    final isMuted = ref.read(isMutedProvider);
    double current = player.state.volume;

    if (isMuted && delta > 0) {
      final preVol = ref.read(preMuteVolumeProvider);
      current = preVol > 0 ? preVol : 50.0;
      ref.read(isMutedProvider.notifier).state = false;
    }

    final target = (current + delta).clamp(0.0, 200.0);
    await player.setVolume(target);
    triggerVolumeHud(ref, target, target == 0 || ref.read(isMutedProvider));
  }

  /// Triggers the floating Volume HUD overlay display on screen.
  static void triggerVolumeHud(WidgetRef ref, double volume, bool isMuted) {
    ref.read(volumeHudProvider.notifier).state = VolumeHudData(
      volume: volume,
      isMuted: isMuted,
      id: DateTime.now().microsecondsSinceEpoch,
    );
  }

  /// Toggle mute on/off, storing the previous volume level.
  static Future<void> toggleMute(
    Player player, {
    required bool currentlyMuted,
    required double preMuteVolume,
    required void Function(bool) setMuted,
    required void Function(double) setPreMuteVolume,
    required WidgetRef ref,
  }) async {
    if (currentlyMuted) {
      final target = preMuteVolume > 0 ? preMuteVolume : 50.0;
      await player.setVolume(target);
      setMuted(false);
      triggerVolumeHud(ref, target, false);
    } else {
      setPreMuteVolume(player.state.volume);
      await player.setVolume(0);
      setMuted(true);
      triggerVolumeHud(ref, 0, true);
    }
  }

  /// Select a specific audio track.
  static Future<void> setAudioTrack(Player player, AudioTrack track) =>
      player.setAudioTrack(track);
}
