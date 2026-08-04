import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'dart:developer' as developer;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as path;

import 'package:lexo_player/features/video_player/providers/player_provider.dart';
import 'package:lexo_player/features/video_player/presentation/control_bar.dart';
import 'package:lexo_player/features/video_player/presentation/volume_hud_overlay.dart';
import 'package:lexo_player/features/subtitles/presentation/interactive_subtitle_overlay.dart';
import 'package:lexo_player/features/subtitles/logic/subtitle_parser.dart';
import 'package:lexo_player/features/subtitles/providers/subtitle_providers.dart';
import 'package:lexo_player/features/dictionary/presentation/dual_definition_popup.dart';
import 'package:lexo_player/features/dictionary/data/dict_selection_providers.dart';
import 'package:lexo_player/features/main_menu/presentation/main_menu_screen.dart';
import 'package:lexo_player/core/widgets/glass_container.dart';

/// The main screen housing the video player.
class VideoScreen extends ConsumerStatefulWidget {
  final String? videoUri;
  const VideoScreen({super.key, this.videoUri});

  @override
  ConsumerState<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends ConsumerState<VideoScreen> {
  bool _isDraggingFile = false;

  @override
  void initState() {
    super.initState();
    if (widget.videoUri != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadInitialVideo(widget.videoUri!);
      });
    }
  }

  @override
  void dispose() {
    final player = ref.read(playerProvider);
    player.pause();
    PlayerActions.stop(player);
    Future.microtask(() {
      ref.read(isVideoLoadedProvider.notifier).state = false;
    });
    super.dispose();
  }

  Future<void> _loadInitialVideo(String uri) async {
    try {
      // Reset subtitle selection when loading media
      ref.read(selectedSubtitleProvider.notifier).state = const SubtitleTrackOption(
        id: 'none',
        name: 'Off',
        isExternal: false,
      );
      ref.read(externalSubtitleOptionsProvider.notifier).state = const [];

      final player = ref.read(playerProvider);
      await PlayerActions.openMedia(player, uri);
      await _autoDiscoverNearbySubtitles(uri);
      ref.read(isVideoLoadedProvider.notifier).state = true;
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

  Future<void> _autoDiscoverNearbySubtitles(String videoUri) async {
    try {
      final file = File(videoUri);
      if (!await file.exists()) return;

      final dir = file.parent;
      final videoNameWithoutExt = path.basenameWithoutExtension(file.path).toLowerCase();

      final entities = await dir.list().toList();
      final externalOptions = <SubtitleTrackOption>[];

      for (final entity in entities) {
        if (entity is File) {
          final ext = path.extension(entity.path).toLowerCase();
          if (ext == '.srt' || ext == '.vtt') {
            final subName = path.basenameWithoutExtension(entity.path).toLowerCase();
            if (subName.startsWith(videoNameWithoutExt)) {
              try {
                final blocks = await SubtitleParser.parseFile(entity.path);
                if (blocks.isNotEmpty) {
                  final filename = path.basename(entity.path);
                  externalOptions.add(
                    SubtitleTrackOption(
                      id: 'external_${entity.path.hashCode}',
                      name: '$filename (Auto)',
                      isExternal: true,
                      filePath: entity.path,
                      externalBlocks: blocks,
                    ),
                  );
                }
              } catch (_) {}
            }
          }
        }
      }

      if (externalOptions.isNotEmpty && mounted) {
        ref.read(externalSubtitleOptionsProvider.notifier).state = externalOptions;
      }
    } catch (_) {}
  }

  // ── File picking ─────────────────────────────────────────────────────────

  Future<void> _pickVideoFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'mp4', 'MP4', 'mkv', 'MKV', 'avi', 'AVI', 'webm', 'WEBM',
          'mov', 'MOV', 'flv', 'FLV', 'm4v', 'M4V', '3gp', '3GP',
          'ts', 'TS', 'wmv', 'WMV', 'mpg', 'MPG', 'mpeg', 'MPEG'
        ],
        dialogTitle: 'Open Video File',
      );
      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        await _loadInitialVideo(path);
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
        dialogTitle: 'Select Subtitle File',
      );
      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        final blocks = await SubtitleParser.parseFile(path);
        final filename = path.split(Platform.pathSeparator).last;
        final newOption = SubtitleTrackOption(
          id: 'external_${path.hashCode}',
          name: filename,
          isExternal: true,
          filePath: path,
          externalBlocks: blocks,
        );

        final currentExternal = ref.read(externalSubtitleOptionsProvider);
        ref.read(externalSubtitleOptionsProvider.notifier).state = [
          ...currentExternal,
          newOption,
        ];
        ref.read(selectedSubtitleProvider.notifier).state = newOption;
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
    final videoController = ref.watch(videoControllerProvider);
    final theme = Theme.of(context);
    return DropTarget(
      onDragEntered: (_) => setState(() => _isDraggingFile = true),
      onDragExited: (_) => setState(() => _isDraggingFile = false),
      onDragDone: (details) {
        setState(() => _isDraggingFile = false);
        if (details.files.isNotEmpty) {
          final file = details.files.first;
          final path = file.path;
          final lower = path.toLowerCase();
          if (lower.endsWith('.mp4') ||
              lower.endsWith('.mkv') ||
              lower.endsWith('.avi') ||
              lower.endsWith('.mov') ||
              lower.endsWith('.webm') ||
              lower.endsWith('.flv') ||
              lower.endsWith('.m4v') ||
              lower.endsWith('.3gp') ||
              lower.endsWith('.ts')) {
            _loadInitialVideo(path);
          }
        }
      },
      child: Scaffold(
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

            if (_isDraggingFile)
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: Container(
                    color: theme.colorScheme.surface.withValues(alpha: 0.88),
                    child: Center(
                      child: Container(
                        margin: const EdgeInsets.all(32),
                        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 320),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceVariant.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: theme.colorScheme.primary.withValues(alpha: 0.6),
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: theme.colorScheme.primary.withValues(alpha: 0.25),
                              blurRadius: 40,
                              spreadRadius: 4,
                            ),
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.6),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: theme.colorScheme.primary.withValues(alpha: 0.3),
                                  width: 1.5,
                                ),
                              ),
                              child: Icon(
                                Icons.video_library_rounded,
                                size: 48,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              'Drop Video File to Play',
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: theme.colorScheme.onSurface,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.3,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                'Supports MP4, MKV, AVI, WEBM, MOV',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
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
        PlayerActions.seekNextSubtitle(ref, player);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        PlayerActions.seekPreviousSubtitle(ref, player);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
      case LogicalKeyboardKey.audioVolumeUp:
        PlayerActions.adjustVolumeRelative(player, 5.0, ref);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
      case LogicalKeyboardKey.audioVolumeDown:
        PlayerActions.adjustVolumeRelative(player, -5.0, ref);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.space:
      case LogicalKeyboardKey.mediaPlayPause:
      case LogicalKeyboardKey.mediaPlay:
      case LogicalKeyboardKey.mediaPause:
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
          ref: ref,
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

  void _onDoubleTap() {
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      _toggleFullscreen();
    }
  }

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

    return MouseRegion(
      cursor: controlsVisible ? SystemMouseCursors.basic : SystemMouseCursors.none,
      child: Focus(
        autofocus: true,
        onKeyEvent: _handleKeyEvent,
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => _onUserActivity(),
          onPointerHover: (_) => _onUserActivity(),
          onPointerMove: (_) => _onUserActivity(),
        onPointerSignal: (pointerSignal) {
          if (pointerSignal is PointerScrollEvent) {
            _onUserActivity();
            final player = ref.read(playerProvider);
            final delta = pointerSignal.scrollDelta.dy < 0 ? 5.0 : -5.0;
            PlayerActions.adjustVolumeRelative(player, delta, ref);
          }
        },
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
                onDoubleTap: _onDoubleTap,
              ),
            ),

            // ── Interactive Subtitle Overlay ──
            const InteractiveSubtitleOverlay(),

            // ── Desktop Dictionary Popup Overlay ──
            const DualDefinitionPopup(),

            // ── Floating Volume HUD Overlay ──
            const VolumeHudOverlay(),

            // ── Auto-hiding Top Header Bar (Video Title + Back Button) ──
            Positioned(
              left: 24,
              top: 48,
              right: 24,
              child: AnimatedOpacity(
                opacity: controlsVisible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: IgnorePointer(
                  ignoring: !controlsVisible,
                  child: Row(
                    children: [
                      // Back Button
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () {
                            final player = ref.read(playerProvider);
                            player.pause();
                            PlayerActions.stop(player);
                            ref.read(isVideoLoadedProvider.notifier).state = false;
                            Navigator.of(context).pop();
                          },
                          child: GlassContainer(
                            padding: const EdgeInsets.all(12),
                            borderRadius: BorderRadius.circular(24),
                            color: Colors.grey.withValues(alpha: 0.10),
                            borderColor: Colors.grey.shade300.withValues(alpha: 0.14),
                            blur: 10.0,
                            child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      
                      // Video Title Pill
                      const Expanded(child: _VideoTitleHeader()),
                    ],
                  ),
                ),
              ),
            ),

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
    ),
    );
  }
}

/// Clean header displaying the title of the active video file matching app typography.
class _VideoTitleHeader extends ConsumerWidget {
  const _VideoTitleHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerProvider);
    final playlist = player.state.playlist;

    if (playlist.index < 0 || playlist.index >= playlist.medias.length) {
      return const SizedBox.shrink();
    }

    final uri = playlist.medias[playlist.index].uri;
    final title = formatMediaTitle(uri);

    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.95),
          fontSize: 15,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
          shadows: const [
            Shadow(
              color: Colors.black87,
              blurRadius: 10,
              offset: Offset(0, 1),
            ),
          ],
        ),
      ),
    );
  }
}
