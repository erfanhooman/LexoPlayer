import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:developer' as developer;

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
  final player = Player();

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

Future<void> _savePlaybackPosition(String uri, Duration position, Duration totalDuration) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final key = _getPlaybackPositionKey(uri);
    
    // If we are close to the end (within 5 seconds), reset to start
    final isNearEnd = totalDuration > Duration.zero && 
        (totalDuration - position).inSeconds < 5;
        
    if (isNearEnd || position.inSeconds <= 0) {
      await prefs.remove(key);
      developer.log('Cleared saved position for $uri (near end or <= 0)', name: 'PlayerPosition');
    } else {
      await prefs.setInt(key, position.inMilliseconds);
      developer.log('Saved position for $uri: ${position.inSeconds}s', name: 'PlayerPosition');
    }
  } catch (e) {
    developer.log('Error saving playback position: $e', name: 'PlayerPosition', level: 900);
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
    developer.log('Error loading playback position: $e', name: 'PlayerPosition', level: 900);
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
      developer.log('Failed to save previous video state: $e', name: 'PlayerActions');
    }

    String finalUri = uri;
    // If it's a local file path and doesn't have a URI scheme, convert it.
    if (!uri.startsWith('http://') &&
        !uri.startsWith('https://') &&
        !uri.startsWith('rtsp://') &&
        !uri.startsWith('rtmp://')) {
      finalUri = Uri.file(uri).toString();
    }
    // Load the saved position BEFORE opening the media to prevent race conditions
    // with the position stream listener.
    final savedPosition = await _loadPlaybackPosition(finalUri);

    developer.log('Opening media: $finalUri', name: 'PlayerActions');
    await player.open(Media(finalUri), play: false);
    // Suppress native subtitle track – we render our own overlay.
    await player.setSubtitleTrack(SubtitleTrack.no());
    if (savedPosition != null && savedPosition.inSeconds > 0) {
      developer.log('Resuming playback at: ${savedPosition.inSeconds}s', name: 'PlayerActions');
      try {
        if (player.state.duration > Duration.zero) {
          developer.log('Duration is already resolved: ${player.state.duration}', name: 'PlayerActions');
          await Future.delayed(const Duration(milliseconds: 300));
          await player.seek(savedPosition);
        } else {
          developer.log('Waiting for duration stream...', name: 'PlayerActions');
          await player.stream.duration.firstWhere((d) => d > Duration.zero).timeout(const Duration(seconds: 4));
          await Future.delayed(const Duration(milliseconds: 300));
          await player.seek(savedPosition);
        }
        await Future.delayed(const Duration(milliseconds: 100));
      } catch (e) {
        developer.log('Error/Timeout during seek: $e', name: 'PlayerActions');
        await player.seek(savedPosition);
        await Future.delayed(const Duration(milliseconds: 100));
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

  /// Seek to an absolute position.
  static Future<void> seek(Player player, Duration position) =>
      player.seek(position);

  /// Seek forward/backward by a relative [delta].
  static Future<void> seekRelative(Player player, Duration delta) async {
    final current = player.state.position;
    final target = current + delta;
    final clamped = target < Duration.zero ? Duration.zero : target;
    await player.seek(clamped);
  }

  /// Set playback speed.
  static Future<void> setSpeed(Player player, double speed) =>
      player.setRate(speed);

  /// Set volume (0 – 100).
  static Future<void> setVolume(Player player, double volume) =>
      player.setVolume(volume);

  /// Toggle mute on/off, storing the previous volume level.
  static Future<void> toggleMute(
    Player player, {
    required bool currentlyMuted,
    required double preMuteVolume,
    required void Function(bool) setMuted,
    required void Function(double) setPreMuteVolume,
  }) async {
    if (currentlyMuted) {
      await player.setVolume(preMuteVolume);
      setMuted(false);
    } else {
      setPreMuteVolume(player.state.volume);
      await player.setVolume(0);
      setMuted(true);
    }
  }

  /// Select a specific audio track.
  static Future<void> setAudioTrack(Player player, AudioTrack track) =>
      player.setAudioTrack(track);
}
