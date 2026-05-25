import 'dart:async';
import 'dart:io';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'package:lexo_player/features/video_player/providers/player_provider.dart';
import 'package:lexo_player/features/video_player/presentation/control_bar.dart';
import 'package:lexo_player/features/subtitles/presentation/interactive_subtitle_overlay.dart';
import 'package:lexo_player/features/subtitles/logic/subtitle_parser.dart';
import 'package:lexo_player/features/subtitles/providers/subtitle_providers.dart';
import 'package:lexo_player/features/dictionary/presentation/dual_definition_popup.dart';
import 'package:lexo_player/features/dictionary/data/dict_selection_providers.dart';

/// The main screen housing the video player.
class VideoScreen extends ConsumerStatefulWidget {
  final String? videoUri;
  const VideoScreen({super.key, this.videoUri});

  @override
  ConsumerState<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends ConsumerState<VideoScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.videoUri != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadInitialVideo(widget.videoUri!);
      });
    }
  }

  Future<void> _loadInitialVideo(String uri) async {
    try {
      final player = ref.read(playerProvider);
      await PlayerActions.openMedia(player, uri);
    } catch (e, stack) {
      developer.log('Error loading initial video: $e',
          stackTrace: stack, name: 'VideoScreen');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to open video: $e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // ── File picking ─────────────────────────────────────────────────────────

  Future<void> _pickVideoFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp4', 'mkv', 'avi', 'webm', 'mov'],
        dialogTitle: 'Open Video File',
      );
      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        final player = ref.read(playerProvider);
        await PlayerActions.openMedia(player, path);

        // Reset subtitle selections when loading a new video.
        ref.read(selectedSubtitleProvider.notifier).state =
            const SubtitleTrackOption(
          id: 'none',
          name: 'Off',
          isExternal: false,
        );
        ref.read(externalSubtitleOptionsProvider.notifier).state = const [];

        ref.read(isVideoLoadedProvider.notifier).state = true;
      }
    } catch (e, stack) {
      developer.log('Error opening video file: $e',
          stackTrace: stack, name: 'VideoScreen');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to open video: $e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _pickSubtitleFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['srt', 'vtt'],
        dialogTitle: 'Open Subtitle File',
      );
      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        final blocks = await SubtitleParser.parseFile(path);

        // Create a new SubtitleTrackOption
        final name = result.files.single.name;
        final newOption = SubtitleTrackOption(
          id: 'external_${DateTime.now().millisecondsSinceEpoch}',
          name: '$name (External)',
          isExternal: true,
          filePath: path,
          externalBlocks: blocks,
        );

        // Add to external options list
        final currentExternal = ref.read(externalSubtitleOptionsProvider);
        ref.read(externalSubtitleOptionsProvider.notifier).state = [
          ...currentExternal,
          newOption
        ];

        // Select it as active
        ref.read(selectedSubtitleProvider.notifier).state = newOption;

        // Extract language code from filename if present (e.g. movie.en.srt, movie_de.vtt)
        final fileName = name.toLowerCase();
        final lastDotIdx = fileName.lastIndexOf('.');
        if (lastDotIdx > 0) {
          final baseWithoutExt = fileName.substring(0, lastDotIdx);
          final regExp = RegExp(r'[-_\.]([a-z]{2,3})$');
          final match = regExp.firstMatch(baseWithoutExt);
          if (match != null) {
            final lang = match.group(1)!;
            ref.read(activeSourceLanguageProvider.notifier).state = lang;
            developer.log('Detected active subtitle language: $lang',
                name: 'VideoScreen');
          } else {
            // Fallback to default 'en'
            ref.read(activeSourceLanguageProvider.notifier).state = 'en';
          }
        } else {
          ref.read(activeSourceLanguageProvider.notifier).state = 'en';
        }
      }
    } catch (e, stack) {
      developer.log('Error picking subtitle file: $e',
          stackTrace: stack, name: 'VideoScreen');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load subtitle: $e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Watch subtitle synchronization so it runs active during this screen session.
    ref.watch(playerSubtitleSyncProvider);

    final videoController = ref.watch(videoControllerProvider);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          SizedBox.expand(
            child: Video(
              key: ref.watch(videoKeyProvider),
              controller: videoController,
              controls: (state) => LexoVideoControls(
                videoState: state,
                onPickVideo: _pickVideoFile,
                onPickSubtitle: _pickSubtitleFile,
              ),
              subtitleViewConfiguration: const SubtitleViewConfiguration(
                style: TextStyle(
                  color: Colors.transparent,
                  fontSize: 0.0,
                ),
              ),
            ),
          ),
          
          // Floating Back Button
          Positioned(
            top: 48,
            left: 24,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () {
                  ref.read(isVideoLoadedProvider.notifier).state = false;
                  Navigator.of(context).pop();
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }


}

/// Custom controls widget that encapsulates all overlays (ControlBar, Subtitles, Dictionary).
/// By passing this to the `Video` widget's `controls` property, it ensures the UI
/// is preserved natively when `media_kit_video` pushes a fullscreen route.
class LexoVideoControls extends ConsumerStatefulWidget {
  final VideoState videoState;
  final VoidCallback onPickVideo;
  final VoidCallback onPickSubtitle;

  const LexoVideoControls({
    super.key,
    required this.videoState,
    required this.onPickVideo,
    required this.onPickSubtitle,
  });

  @override
  ConsumerState<LexoVideoControls> createState() => _LexoVideoControlsState();
}

class _LexoVideoControlsState extends ConsumerState<LexoVideoControls> {
  Timer? _hideControlsTimer;

  @override
  void initState() {
    super.initState();
    _resetHideTimer();
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    super.dispose();
  }

  void _resetHideTimer() {
    _hideControlsTimer?.cancel();
    final isVisible = ref.read(controlsVisibleProvider);
    if (!isVisible) {
      ref.read(controlsVisibleProvider.notifier).state = true;
    }
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        ref.read(controlsVisibleProvider.notifier).state = false;
      }
    });
  }

  void _onUserActivity() => _resetHideTimer();

  // ── Keyboard shortcuts (Desktop) ─────────────────────────────────────────

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final player = ref.read(playerProvider);

    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowRight:
        PlayerActions.seekRelative(player, const Duration(seconds: 10));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        PlayerActions.seekRelative(player, const Duration(seconds: -10));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.space:
        PlayerActions.playOrPause(player);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyF:
        _toggleFullscreen();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyM:
        final muted = ref.read(isMutedProvider);
        final preVol = ref.read(preMuteVolumeProvider);
        PlayerActions.toggleMute(
          player,
          currentlyMuted: muted,
          preMuteVolume: preVol,
          setMuted: (v) => ref.read(isMutedProvider.notifier).state = v,
          setPreMuteVolume: (v) =>
              ref.read(preMuteVolumeProvider.notifier).state = v,
        );
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  void _toggleFullscreen() {
    if (widget.videoState.isFullscreen()) {
      widget.videoState.exitFullscreen();
      ref.read(isFullscreenProvider.notifier).state = false;
    } else {
      widget.videoState.enterFullscreen();
      ref.read(isFullscreenProvider.notifier).state = true;
    }
  }

  // ── Double-tap seek (Mobile) ─────────────────────────────────────────────

  void _onDoubleTapDown(TapDownDetails details) {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    final screenWidth = MediaQuery.of(context).size.width;
    final player = ref.read(playerProvider);

    if (details.globalPosition.dx < screenWidth / 2) {
      PlayerActions.seekRelative(player, const Duration(seconds: -10));
    } else {
      PlayerActions.seekRelative(player, const Duration(seconds: 10));
    }
  }

  @override
  Widget build(BuildContext context) {
    final controlsVisible = ref.watch(controlsVisibleProvider);

    return Focus(
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _onUserActivity(),
        onPointerHover: (_) => _onUserActivity(),
        onPointerMove: (_) => _onUserActivity(),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // ── Background GestureDetector (Video Surface Taps/Double-taps) ──
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  final isVisible = ref.read(controlsVisibleProvider);
                  if (isVisible) {
                    ref.read(controlsVisibleProvider.notifier).state = false;
                    _hideControlsTimer?.cancel();
                  } else {
                    _onUserActivity();
                  }
                },
                onDoubleTapDown: _onDoubleTapDown,
                onDoubleTap: () {}, // Required for double-tap-down to fire.
              ),
            ),

            // ── Interactive Subtitle Overlay ──
            const InteractiveSubtitleOverlay(),

            // ── Desktop Dictionary Popup Overlay ──
            const DualDefinitionPopup(),

            // ── Auto-hiding Control Bar ──
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AnimatedOpacity(
                opacity: controlsVisible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: IgnorePointer(
                  ignoring: !controlsVisible,
                  child: ControlBar(
                    onPickVideo: widget.onPickVideo,
                    onPickSubtitle: widget.onPickSubtitle,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
