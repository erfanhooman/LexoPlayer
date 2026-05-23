import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexo_player/features/video_player/providers/player_provider.dart';
import 'package:lexo_player/features/subtitles/providers/subtitle_providers.dart';
import 'package:lexo_player/features/subtitles/presentation/subtitle_settings_overlay.dart';

class ControlBar extends ConsumerStatefulWidget {
  final VoidCallback onPickVideo;
  final VoidCallback onPickSubtitle;

  const ControlBar({
    super.key,
    required this.onPickVideo,
    required this.onPickSubtitle,
  });

  @override
  ConsumerState<ControlBar> createState() => _ControlBarState();
}

class _ControlBarState extends ConsumerState<ControlBar> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    // Compute dynamic widths based on the actual screen size.
    final expandedWidth = (screenWidth - 32).clamp(200.0, 800.0);
    final collapsedWidth = (screenWidth - 32).clamp(120.0, 200.0);
    final targetWidth = _isHovered ? expandedWidth : collapsedWidth;

    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 32),
        child: MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutExpo,
            height: 64,
            width: targetWidth,
            decoration: BoxDecoration(
              color: const Color(0xFF16161A).withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(32),
              child: Stack(
                children: [
                  // Collapsed State (Centered)
                  AnimatedOpacity(
                    opacity: _isHovered ? 0.0 : 1.0,
                    duration: const Duration(milliseconds: 200),
                    child: const Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _PlayPauseButton(),
                          SizedBox(width: 8),
                          _TimeLabel(),
                        ],
                      ),
                    ),
                  ),
                  
                  // Expanded State
                  AnimatedOpacity(
                    opacity: _isHovered ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 300),
                    child: IgnorePointer(
                      ignoring: !_isHovered,
                      child: OverflowBox(
                        minWidth: expandedWidth,
                        maxWidth: expandedWidth,
                        alignment: Alignment.centerLeft,
                        child: SizedBox(
                          width: expandedWidth,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              children: [
                                const _PlayPauseButton(),
                                const SizedBox(width: 4),
                                const _TimeLabel(),
                                const SizedBox(width: 16),
                                Expanded(child: _TimelineSlider()),
                                const SizedBox(width: 16),
                                _VolumeControl(),
                                const SizedBox(width: 8),
                                _SpeedButton(),
                                const SizedBox(width: 4),
                                _SubtitleFileButton(onPickSubtitle: widget.onPickSubtitle),
                                const SizedBox(width: 4),
                                _FullscreenButton(),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Timeline slider
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _TimelineSlider extends ConsumerStatefulWidget {
  @override
  ConsumerState<_TimelineSlider> createState() => _TimelineSliderState();
}

class _TimelineSliderState extends ConsumerState<_TimelineSlider> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final posAsync = ref.watch(positionProvider);
    final durAsync = ref.watch(durationProvider);

    final position = posAsync.valueOrNull ?? Duration.zero;
    final duration = durAsync.valueOrNull ?? const Duration(seconds: 1);

    final maxVal = duration.inMilliseconds.toDouble().clamp(1.0, double.infinity);
    final curVal = position.inMilliseconds.toDouble().clamp(0.0, maxVal);
    final sliderValue = (_dragValue ?? curVal).clamp(0.0, maxVal);

    return SliderTheme(
      data: SliderThemeData(
        trackHeight: 4,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
        activeTrackColor: const Color(0xFFFF5500),
        inactiveTrackColor: Colors.white24,
        thumbColor: const Color(0xFFFF5500),
        overlayColor: const Color(0xFFFF5500).withValues(alpha: 0.2),
      ),
      child: Slider(
        min: 0,
        max: maxVal,
        value: sliderValue,
        onChanged: (value) {
          setState(() {
            _dragValue = value;
          });
        },
        onChangeEnd: (value) async {
          final player = ref.read(playerProvider);
          await PlayerActions.seek(player, Duration(milliseconds: value.toInt()));
          if (mounted) {
            setState(() {
              _dragValue = null;
            });
          }
        },
      ),
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Play / Pause button
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _PlayPauseButton extends ConsumerWidget {
  const _PlayPauseButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playingAsync = ref.watch(playingProvider);
    final isPlaying = playingAsync.valueOrNull ?? false;

    return IconButton(
      icon: Icon(
        isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
        color: Colors.white,
        size: 28,
      ),
      tooltip: isPlaying ? 'Pause' : 'Play',
      onPressed: () {
        final player = ref.read(playerProvider);
        PlayerActions.playOrPause(player);
      },
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Elapsed / Duration label
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _TimeLabel extends ConsumerWidget {
  const _TimeLabel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posAsync = ref.watch(positionProvider);
    final position = posAsync.valueOrNull ?? Duration.zero;

    return Text(
      _formatDuration(position),
      style: const TextStyle(
        color: Colors.white,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        fontFamily: 'Helvetica Neue',
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    );
  }

  static String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) return '$hours:$minutes:$seconds';
    return '$minutes:$seconds';
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Volume slider + mute toggle
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _VolumeControl extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final volumeAsync = ref.watch(volumeProvider);
    final volume = volumeAsync.valueOrNull ?? 100.0;
    final isMuted = ref.watch(isMutedProvider);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(
            isMuted || volume == 0
                ? Icons.volume_off_rounded
                : volume < 50
                    ? Icons.volume_down_rounded
                    : Icons.volume_up_rounded,
            color: Colors.white70,
            size: 22,
          ),
          tooltip: isMuted ? 'Unmute' : 'Mute',
          onPressed: () {
            final player = ref.read(playerProvider);
            final preVol = ref.read(preMuteVolumeProvider);
            PlayerActions.toggleMute(
              player,
              currentlyMuted: isMuted,
              preMuteVolume: preVol,
              setMuted: (v) => ref.read(isMutedProvider.notifier).state = v,
              setPreMuteVolume: (v) => ref.read(preMuteVolumeProvider.notifier).state = v,
            );
          },
        ),
      ],
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Playback speed button
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _SpeedButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final speed = ref.watch(playbackSpeedProvider);

    return PopupMenuButton<double>(
      tooltip: 'Playback Speed',
      icon: Text(
        '${speed}x',
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      color: const Color(0xFF16161A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      itemBuilder: (_) => availableSpeeds
          .map(
            (s) => PopupMenuItem(
              value: s,
              child: Text(
                '${s}x',
                style: TextStyle(
                  color: s == speed ? const Color(0xFFFF5500) : Colors.white70,
                  fontWeight: s == speed ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          )
          .toList(),
      onSelected: (s) {
        final player = ref.read(playerProvider);
        ref.read(playbackSpeedProvider.notifier).state = s;
        PlayerActions.setSpeed(player, s);
      },
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Subtitle & Settings button
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _SubtitleFileButton extends ConsumerWidget {
  final VoidCallback onPickSubtitle;
  const _SubtitleFileButton({required this.onPickSubtitle});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final available = ref.watch(availableSubtitlesProvider);
    final selected = ref.watch(selectedSubtitleProvider) ?? available.firstOrNull;

    return PopupMenuButton<String>(
      tooltip: 'Subtitles & Dictionary',
      icon: const Icon(Icons.subtitles_rounded, color: Colors.white70, size: 20),
      color: const Color(0xFF16161A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      itemBuilder: (BuildContext context) {
        final List<PopupMenuEntry<String>> items = [];

        for (final option in available) {
          items.add(PopupMenuItem<String>(
            value: option.id,
            child: Row(
              children: [
                if (selected?.id == option.id)
                  const Icon(Icons.check_rounded, color: Color(0xFFFF5500), size: 16)
                else
                  const SizedBox(width: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    option.name,
                    style: TextStyle(
                      color: selected?.id == option.id ? const Color(0xFFFF5500) : Colors.white70,
                      fontWeight: selected?.id == option.id ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              ],
            ),
          ));
        }

        items.add(const PopupMenuDivider());

        items.add(const PopupMenuItem<String>(
          value: 'load_external',
          child: Row(
            children: [
              Icon(Icons.folder_open_rounded, color: Colors.white70, size: 18),
              SizedBox(width: 8),
              Text('Load External File...', style: TextStyle(color: Colors.white70)),
            ],
          ),
        ));

        items.add(const PopupMenuItem<String>(
          value: 'subtitle_settings',
          child: Row(
            children: [
              Icon(Icons.settings_rounded, color: Colors.white70, size: 18),
              SizedBox(width: 8),
              Text('Subtitle Style...', style: TextStyle(color: Colors.white70)),
            ],
          ),
        ));

        return items;
      },
      onSelected: (String value) {
        if (value == 'load_external') {
          onPickSubtitle();
        } else if (value == 'subtitle_settings') {
          SubtitleSettingsOverlay.show(context);
        } else {
          final target = available.firstWhere((opt) => opt.id == value);
          ref.read(selectedSubtitleProvider.notifier).state = target;
        }
      },
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Fullscreen toggle button
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _FullscreenButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFs = ref.watch(isFullscreenProvider);

    return IconButton(
      icon: Icon(
        isFs ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
        color: Colors.white70,
        size: 24,
      ),
      tooltip: isFs ? 'Exit Fullscreen' : 'Fullscreen',
      onPressed: () {
        final videoKey = ref.read(videoKeyProvider);
        final state = videoKey.currentState;
        if (state != null) {
          if (state.isFullscreen()) {
            state.exitFullscreen();
            ref.read(isFullscreenProvider.notifier).state = false;
          } else {
            state.enterFullscreen();
            ref.read(isFullscreenProvider.notifier).state = true;
          }
        }
      },
    );
  }
}
