import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexo_player/features/video_player/providers/player_provider.dart';
import 'package:lexo_player/features/subtitles/providers/subtitle_providers.dart';
import 'package:lexo_player/features/subtitles/presentation/subtitle_settings_overlay.dart';
import 'package:lexo_player/features/subtitles/presentation/open_subtitles_search_dialog.dart';
import 'package:lexo_player/core/widgets/glass_container.dart';
import 'package:lexo_player/core/theme/app_colors.dart';
import 'package:lexo_player/core/engine/engine_providers.dart';

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
  bool _isPopupOpen = false;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 480;
    final isTouchOrNarrow =
        Platform.isAndroid || Platform.isIOS || screenWidth < 600;
    final isEffectiveHover = _isHovered || isTouchOrNarrow;

    // Compute dynamic widths based on the actual screen size.
    final expandedWidth =
        (screenWidth - (isCompact ? 16 : 32)).clamp(160.0, 820.0);
    final collapsedWidth = (screenWidth - 32).clamp(120.0, 200.0);
    final targetWidth = isEffectiveHover ? expandedWidth : collapsedWidth;
    final barHeight = isCompact ? 52.0 : 64.0;

    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.only(bottom: isCompact ? 12 : 32),
        child: MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) {
            if (!_isPopupOpen) setState(() => _isHovered = false);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutExpo,
            height: barHeight,
            width: targetWidth,
            child: GlassContainer(
              borderRadius: BorderRadius.circular(999),
              color: Colors.grey.withValues(alpha: 0.10),
              borderColor: Colors.grey.shade300.withValues(alpha: 0.14),
              blur: 10.0,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
              child: Stack(
                children: [
                  // Collapsed State (Centered)
                  AnimatedOpacity(
                    opacity: isEffectiveHover ? 0.0 : 1.0,
                    duration: const Duration(milliseconds: 200),
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const _PlayPauseButton(),
                          const SizedBox(width: 8),
                          _TimeLabel(isHovered: false),
                        ],
                      ),
                    ),
                  ),

                  // Expanded State
                  AnimatedOpacity(
                    opacity: isEffectiveHover ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 300),
                    child: IgnorePointer(
                      ignoring: !isEffectiveHover,
                      child: OverflowBox(
                        minWidth: expandedWidth,
                        maxWidth: expandedWidth,
                        alignment: Alignment.centerLeft,
                        child: SizedBox(
                          width: expandedWidth,
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                                horizontal: isCompact ? 6 : 12),
                            child: Row(
                              children: [
                                const _PlayPauseButton(),
                                SizedBox(width: isCompact ? 3 : 6),
                                _TimeLabel(isHovered: isEffectiveHover),
                                SizedBox(width: isCompact ? 4 : 8),
                                Expanded(child: _TimelineSlider()),
                                SizedBox(width: isCompact ? 4 : 8),
                                if (screenWidth >= 520) ...[
                                  const _VolumeControl(),
                                  const SizedBox(width: 6),
                                ],
                                _SpeedButton(),
                                const SizedBox(width: 4),
                                _SubtitleFileButton(
                                  onPickSubtitle: widget.onPickSubtitle,
                                  onPopupChanged: (open) =>
                                      setState(() => _isPopupOpen = open),
                                ),
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
  DateTime _lastLiveSeekTime = DateTime.now();
  bool _isHovering = false;
  double _hoverPositionFraction = 0.0;

  void _onSliderChanged(double value) {
    setState(() {
      _dragValue = value;
    });

    // Real-time video frame scrubbing update (throttled to 35ms for smooth video frame updates)
    final now = DateTime.now();
    if (now.difference(_lastLiveSeekTime).inMilliseconds >= 35) {
      _lastLiveSeekTime = now;
      final player = ref.read(playerProvider);
      PlayerActions.seek(player, Duration(milliseconds: value.toInt()));
    }
  }

  void _onSliderChangeEnd(double value) async {
    final player = ref.read(playerProvider);
    await PlayerActions.seek(player, Duration(milliseconds: value.toInt()));
    if (mounted) {
      setState(() {
        _dragValue = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final posAsync = ref.watch(positionProvider);
    final durAsync = ref.watch(durationProvider);

    final position = posAsync.valueOrNull ?? Duration.zero;
    final duration = durAsync.valueOrNull ?? const Duration(seconds: 1);

    final maxVal =
        duration.inMilliseconds.toDouble().clamp(1.0, double.infinity);
    final curVal = position.inMilliseconds.toDouble().clamp(0.0, maxVal);
    final sliderValue = (_dragValue ?? curVal).clamp(0.0, maxVal);

    return LayoutBuilder(
      builder: (context, constraints) {
        final hoverMillis =
            (_hoverPositionFraction * maxVal).clamp(0.0, maxVal);
        final hoverDuration = Duration(milliseconds: hoverMillis.toInt());

        return MouseRegion(
          onEnter: (_) => setState(() => _isHovering = true),
          onExit: (_) => setState(() => _isHovering = false),
          onHover: (event) {
            if (constraints.maxWidth > 0) {
              setState(() {
                _hoverPositionFraction =
                    (event.localPosition.dx / constraints.maxWidth)
                        .clamp(0.0, 1.0);
              });
            }
          },
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Live Hover Time Badge (Shows exact timestamp above mouse/thumb when hovering or scrubbing)
              if (_isHovering || _dragValue != null)
                Positioned(
                  left: ((_dragValue != null
                              ? (_dragValue! / maxVal)
                              : _hoverPositionFraction) *
                          (constraints.maxWidth - 40))
                      .clamp(0.0, constraints.maxWidth - 60),
                  bottom: 32,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B1923),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.5),
                          width: 1),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Text(
                      _formatDuration(_dragValue != null
                          ? Duration(milliseconds: _dragValue!.toInt())
                          : hoverDuration),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

              Listener(
                onPointerSignal: (pointerSignal) {
                  if (pointerSignal is PointerScrollEvent) {
                    final player = ref.read(playerProvider);
                    final delta = pointerSignal.scrollDelta.dy < 0 ? 5.0 : -5.0;
                    PlayerActions.adjustVolumeRelative(player, delta, ref);
                  }
                },
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 4,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 7),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 14),
                    activeTrackColor: AppColors.primary,
                    inactiveTrackColor: Colors.white.withValues(alpha: 0.15),
                    thumbColor: AppColors.primary,
                    overlayColor: AppColors.primary.withValues(alpha: 0.25),
                  ),
                  child: Slider(
                    min: 0,
                    max: maxVal,
                    value: sliderValue,
                    onChanged: _onSliderChanged,
                    onChangeEnd: _onSliderChangeEnd,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) return '$hours:$minutes:$seconds';
    return '$minutes:$seconds';
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
        color: AppColors.primary,
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
//  Interactive Time label (Passed / Remaining toggle + Hover Total)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _TimeLabel extends ConsumerWidget {
  final bool isHovered;
  const _TimeLabel({this.isHovered = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posAsync = ref.watch(positionProvider);
    final durAsync = ref.watch(durationProvider);
    final showRemaining = ref.watch(showRemainingTimeProvider);

    final position = posAsync.valueOrNull ?? Duration.zero;
    final duration = durAsync.valueOrNull ?? Duration.zero;

    final diff = duration - position;
    final remaining = diff.isNegative ? Duration.zero : diff;

    final primaryStr = showRemaining
        ? '-${_formatDuration(remaining)}'
        : _formatDuration(position);

    final totalStr = _formatDuration(duration);

    final screenWidth = MediaQuery.of(context).size.width;
    final displayText = (isHovered && screenWidth >= 420)
        ? '$primaryStr / $totalStr'
        : primaryStr;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          ref.read(showRemainingTimeProvider.notifier).state = !showRemaining;
        },
        child: Tooltip(
          message: showRemaining
              ? 'Click to show time passed'
              : 'Click to show remaining time',
          child: Text(
            displayText,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 13,
              fontWeight: FontWeight.w600,
              fontFamily: 'Helvetica Neue',
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
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

class _VolumeControl extends ConsumerStatefulWidget {
  const _VolumeControl();

  @override
  ConsumerState<_VolumeControl> createState() => _VolumeControlState();
}

class _VolumeControlState extends ConsumerState<_VolumeControl> {
  bool _isHovered = false;
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final volumeAsync = ref.watch(volumeProvider);
    final currentVolume = volumeAsync.valueOrNull ?? 100.0;
    final isMuted = ref.watch(isMutedProvider);

    final displayVolume =
        isMuted ? 0.0 : (_dragValue ?? currentVolume).clamp(0.0, 200.0);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Listener(
        onPointerSignal: (pointerSignal) {
          if (pointerSignal is PointerScrollEvent) {
            final player = ref.read(playerProvider);
            final delta = pointerSignal.scrollDelta.dy < 0 ? 5.0 : -5.0;
            PlayerActions.adjustVolumeRelative(player, delta, ref);
          }
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                isMuted || displayVolume == 0
                    ? Icons.volume_off_rounded
                    : displayVolume < 50
                        ? Icons.volume_down_rounded
                        : Icons.volume_up_rounded,
                color: isMuted
                    ? Colors.redAccent
                    : Colors.white.withValues(alpha: 0.7),
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
                  setPreMuteVolume: (v) =>
                      ref.read(preMuteVolumeProvider.notifier).state = v,
                  ref: ref,
                );
              },
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              width: _isHovered ? 75.0 : 45.0,
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 3,
                  thumbShape: RoundSliderThumbShape(
                      enabledThumbRadius: _isHovered ? 6 : 4),
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 10),
                  activeTrackColor: displayVolume > 100.0
                      ? const Color(0xFFFF9100)
                      : (isMuted ? Colors.redAccent : AppColors.primary),
                  inactiveTrackColor: Colors.white.withValues(alpha: 0.15),
                  thumbColor: displayVolume > 100.0
                      ? const Color(0xFFFF9100)
                      : (isMuted ? Colors.redAccent : AppColors.primary),
                  overlayColor: AppColors.primary.withValues(alpha: 0.2),
                ),
                child: Slider(
                  min: 0.0,
                  max: 200.0,
                  value: displayVolume.clamp(0.0, 200.0),
                  onChanged: (val) {
                    setState(() {
                      _dragValue = val;
                    });
                    final player = ref.read(playerProvider);
                    PlayerActions.setVolume(player, val, ref);
                  },
                  onChangeEnd: (_) {
                    if (mounted) {
                      setState(() {
                        _dragValue = null;
                      });
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      ),
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
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.7),
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
                  color: s == speed
                      ? AppColors.primary
                      : Colors.white.withValues(alpha: 0.7),
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

class _SubtitleFileButton extends ConsumerStatefulWidget {
  final VoidCallback onPickSubtitle;
  final ValueChanged<bool> onPopupChanged;
  const _SubtitleFileButton(
      {required this.onPickSubtitle, required this.onPopupChanged});

  @override
  ConsumerState<_SubtitleFileButton> createState() =>
      _SubtitleFileButtonState();
}

class _SubtitleFileButtonState extends ConsumerState<_SubtitleFileButton> {
  final GlobalKey _buttonKey = GlobalKey();

  void _openMenu() async {
    widget.onPopupChanged(true);
    final RenderBox? renderBox =
        _buttonKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) {
      widget.onPopupChanged(false);
      return;
    }

    final buttonPos = renderBox.localToGlobal(Offset.zero);
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        buttonPos.dx,
        buttonPos.dy - 400,
        buttonPos.dx + renderBox.size.width,
        buttonPos.dy + renderBox.size.height + 8,
      ),
      color: const Color(0xFF16161A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      items: _buildMenuItems(),
    );

    widget.onPopupChanged(false);
    if (result != null) _handleSelection(result);
  }

  @override
  Widget build(BuildContext context) {
    final available = ref.watch(availableSubtitlesProvider);
    final selectedPrimary =
        ref.watch(selectedSubtitleProvider) ?? available.firstOrNull;
    final isPersian = ref.watch(appLanguageProvider) == 'fa';

    return IconButton(
      key: _buttonKey,
      tooltip: isPersian ? 'زیرنویس و واژه‌نامه' : 'Subtitles & Dictionary',
      icon: Icon(
        Icons.subtitles_rounded,
        color: (selectedPrimary != null && selectedPrimary.id != 'none')
            ? AppColors.primary
            : Colors.white.withValues(alpha: 0.7),
        size: 20,
      ),
      onPressed: _openMenu,
    );
  }

  List<PopupMenuEntry<String>> _buildMenuItems() {
    final available = ref.read(availableSubtitlesProvider);
    final selectedPrimary =
        ref.read(selectedSubtitleProvider) ?? available.firstOrNull;
    final selectedSecondary = ref.read(selectedSecondarySubtitleProvider);
    final isSecondaryVisible = ref.read(isSecondarySubtitleVisibleProvider);
    final isPersian = ref.read(appLanguageProvider) == 'fa';
    final List<PopupMenuEntry<String>> items = [];

    // ── Primary Subtitle Section Header ──
    items.add(
      PopupMenuItem<String>(
        enabled: false,
        child: Text(
          isPersian
              ? 'زیرنویس اصلی (زبان در حال یادگیری)'
              : 'PRIMARY SUBTITLE (MAIN)',
          style: const TextStyle(
            color: Color(0xFFFF5500),
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.8,
          ),
        ),
      ),
    );

    for (final option in available) {
      final displayName =
          option.name == 'Off' ? (isPersian ? 'خاموش' : 'Off') : option.name;
      final isSelected = selectedPrimary?.id == option.id;
      items.add(PopupMenuItem<String>(
        value: 'primary_${option.id}',
        child: Row(
          children: [
            Icon(
              isSelected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: isSelected ? const Color(0xFFFF5500) : Colors.white38,
              size: 16,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                displayName,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ));
    }

    items.add(const PopupMenuDivider());

    // ── Secondary Subtitle Section Header ──
    items.add(
      PopupMenuItem<String>(
        enabled: false,
        child: Text(
          isPersian
              ? 'زیرنویس دوم (ترجمه / فارسی)'
              : 'SECONDARY SUBTITLE (TRANSLATION)',
          style: const TextStyle(
            color: Color(0xFF00E5FF),
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.8,
          ),
        ),
      ),
    );

    for (final option in available) {
      final displayName =
          option.name == 'Off' ? (isPersian ? 'خاموش' : 'Off') : option.name;
      final isSelected = selectedSecondary?.id == option.id;
      items.add(PopupMenuItem<String>(
        value: 'secondary_${option.id}',
        child: Row(
          children: [
            Icon(
              isSelected
                  ? Icons.check_box_rounded
                  : Icons.check_box_outline_blank_rounded,
              color: isSelected ? const Color(0xFF00E5FF) : Colors.white38,
              size: 16,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                displayName,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ));
    }

    // Toggle Secondary Translation visibility option
    if (selectedSecondary != null && selectedSecondary.id != 'none') {
      items.add(const PopupMenuDivider());
      items.add(
        PopupMenuItem<String>(
          value: 'toggle_secondary_visibility',
          child: Row(
            children: [
              Icon(
                isSecondaryVisible
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
                color: Colors.amberAccent,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                isSecondaryVisible
                    ? (isPersian
                        ? 'مخفی‌سازی زیرنویس ترجمه'
                        : 'Hide Translation Subtitle')
                    : (isPersian
                        ? 'نمایش زیرنویس ترجمه'
                        : 'Show Translation Subtitle'),
                style: const TextStyle(
                  color: Colors.amberAccent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    items.add(const PopupMenuDivider());

    items.add(PopupMenuItem<String>(
      value: 'auto_search_opensubtitles',
      child: Row(
        children: [
          const Icon(Icons.auto_awesome_rounded,
              color: Color(0xFFFF5500), size: 18),
          const SizedBox(width: 8),
          Text(
            isPersian
                ? 'جستجوی خودکار زیرنویس (OpenSubtitles)...'
                : 'Auto Search OpenSubtitles...',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.95),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ));

    items.add(PopupMenuItem<String>(
      value: 'load_external',
      child: Row(
        children: [
          Icon(Icons.folder_open_rounded,
              color: Colors.white.withValues(alpha: 0.7), size: 18),
          const SizedBox(width: 8),
          Text(
            isPersian ? 'افزودن فایل زیرنویس...' : 'Load External File...',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
          ),
        ],
      ),
    ));

    items.add(PopupMenuItem<String>(
      value: 'subtitle_settings',
      child: Row(
        children: [
          Icon(Icons.subtitles_outlined,
              color: Colors.white.withValues(alpha: 0.7), size: 18),
          const SizedBox(width: 8),
          Text(
            isPersian ? 'تنظیمات زیرنویس...' : 'Subtitle Style & Tracks...',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
          ),
        ],
      ),
    ));

    return items;
  }

  void _handleSelection(String value) {
    final available = ref.read(availableSubtitlesProvider);
    final isSecondaryVisible = ref.read(isSecondarySubtitleVisibleProvider);
    if (value == 'auto_search_opensubtitles') {
      OpenSubtitlesSearchDialog.show(context);
    } else if (value == 'load_external') {
      widget.onPickSubtitle();
    } else if (value == 'subtitle_settings') {
      SubtitleSettingsOverlay.show(context);
    } else if (value == 'toggle_secondary_visibility') {
      ref.read(isSecondarySubtitleVisibleProvider.notifier).state =
          !isSecondaryVisible;
    } else if (value.startsWith('secondary_')) {
      final realId = value.replaceFirst('secondary_', '');
      final target = available.firstWhere((opt) => opt.id == realId);
      ref.read(selectedSecondarySubtitleProvider.notifier).state = target;
    } else if (value.startsWith('primary_')) {
      final realId = value.replaceFirst('primary_', '');
      final target = available.firstWhere((opt) => opt.id == realId);
      ref.read(selectedSubtitleProvider.notifier).state = target;
    }
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Fullscreen toggle button
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _FullscreenButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFs = ref.watch(isFullscreenProvider);
    final isPersian = ref.watch(appLanguageProvider) == 'fa';

    return IconButton(
      icon: Icon(
        isFs ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
        color: Colors.white.withValues(alpha: 0.7),
        size: 24,
      ),
      tooltip: isFs
          ? (isPersian ? 'خروج از تمام‌صفحه' : 'Exit Fullscreen')
          : (isPersian ? 'تمام‌صفحه' : 'Fullscreen'),
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
