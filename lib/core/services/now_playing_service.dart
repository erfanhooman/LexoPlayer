import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexo_player/features/video_player/providers/player_provider.dart';
import 'package:lexo_player/features/main_menu/presentation/main_menu_screen.dart';

const _nowPlayingChannel = MethodChannel('com.lexoplayer/now_playing');

/// Global Riverpod provider that keeps OS Now Playing controls (Menu Bar / Control Center / Media Keys)
/// in sync with active media playback.
final nowPlayingSyncProvider = Provider.autoDispose<void>((ref) {
  final player = ref.watch(playerProvider);

  // Set up incoming callback handler from native OS Remote Command Center (Media keys / Menu Bar)
  _nowPlayingChannel.setMethodCallHandler((call) async {
    switch (call.method) {
      case 'onPlay':
        player.play();
        break;
      case 'onPause':
        player.pause();
        break;
      case 'onTogglePlayPause':
        PlayerActions.playOrPause(player);
        break;
      case 'onNext':
        PlayerActions.seekNextSubtitle(ref, player);
        break;
      case 'onPrevious':
        PlayerActions.seekPreviousSubtitle(ref, player);
        break;
      case 'onSeek':
        if (call.arguments is Map) {
          final posSecs = (call.arguments['position'] as num?)?.toDouble();
          if (posSecs != null) {
            player.seek(Duration(milliseconds: (posSecs * 1000).round()));
          }
        }
        break;
    }
  });

  // Listen to playback state changes and sync with OS Now Playing Info
  ref.listen(playingProvider, (prev, next) {
    _syncNowPlaying(player);
  });

  ref.listen(positionProvider, (prev, next) {
    _syncNowPlaying(player);
  });

  ref.listen(durationProvider, (prev, next) {
    _syncNowPlaying(player);
  });

  // Initial sync
  _syncNowPlaying(player);
});

void _syncNowPlaying(dynamic player) async {
  if (!Platform.isMacOS) return;
  try {
    final playlist = player.state.playlist;
    if (playlist.index < 0 || playlist.index >= playlist.medias.length) {
      await _nowPlayingChannel.invokeMethod('clearNowPlayingInfo');
      return;
    }

    final currentUri = playlist.medias[playlist.index].uri;
    final title = formatMediaTitle(currentUri);
    final isPlaying = player.state.playing;
    final positionSecs = player.state.position.inMilliseconds / 1000.0;
    final durationSecs = player.state.duration.inMilliseconds / 1000.0;

    await _nowPlayingChannel.invokeMethod('updateNowPlayingInfo', {
      'title': title,
      'isPlaying': isPlaying,
      'position': positionSecs,
      'duration': durationSecs,
    });
  } on MissingPluginException catch (_) {
    // Channel not registered yet on native side during hot reload
  } catch (_) {}
}
