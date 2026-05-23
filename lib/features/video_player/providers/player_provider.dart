import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
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
  ref.onDispose(() {
    developer.log('Disposing native Player instance', name: 'playerProvider');
    player.dispose();
  });
  return player;
});

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
    String finalUri = uri;
    // If it's a local file path and doesn't have a URI scheme, convert it.
    if (!uri.startsWith('http://') &&
        !uri.startsWith('https://') &&
        !uri.startsWith('rtsp://') &&
        !uri.startsWith('rtmp://')) {
      finalUri = Uri.file(uri).toString();
    }
    developer.log('Opening media: $finalUri', name: 'PlayerActions');
    await player.open(Media(finalUri));
    // Suppress native subtitle track – we render our own overlay.
    await player.setSubtitleTrack(SubtitleTrack.no());
  }

  static Future<void> play(Player player) => player.play();
  static Future<void> pause(Player player) => player.pause();
  static Future<void> playOrPause(Player player) => player.playOrPause();
  static Future<void> stop(Player player) => player.stop();

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
