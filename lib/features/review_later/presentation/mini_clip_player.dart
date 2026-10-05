import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:lexo_player/core/theme/app_colors.dart';

/// Embedded mini video player for practicing a specific subtitle sentence clip.
/// Plays strictly from [startTime] to [endTime], auto-pauses at [endTime],
/// and provides an instant replay button.
class MiniClipPlayer extends StatefulWidget {
  final String videoPath;
  final Duration startTime;
  final Duration endTime;
  final VoidCallback? onClose;

  const MiniClipPlayer({
    super.key,
    required this.videoPath,
    required this.startTime,
    required this.endTime,
    this.onClose,
  });

  @override
  State<MiniClipPlayer> createState() => _MiniClipPlayerState();
}

class _MiniClipPlayerState extends State<MiniClipPlayer> {
  Player? _player;
  VideoController? _controller;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<bool>? _playingSub;
  bool _isPlaying = false;
  bool _reachedEnd = false;
  bool _fileMissing = false;
  Duration _currentPos = Duration.zero;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    final path = _normalizeVideoPath(widget.videoPath);
    if (!_isRemotePath(path) && !await File(path).exists()) {
      if (!mounted) return;
      setState(() => _fileMissing = true);
      return;
    }

    // Native player creation itself can fail (missing codecs/plugins) —
    // never let that escape as an unhandled async error.
    Player? player;
    try {
      player = Player(
        configuration: const PlayerConfiguration(
          title: 'ClipPractice',
          logLevel: MPVLogLevel.error,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _fileMissing = true);
      return;
    }
    final newPlayer = player;
    final controller = VideoController(newPlayer);

    _posSub = newPlayer.stream.position.listen((pos) {
      if (!mounted) return;
      setState(() => _currentPos = pos);
      if (pos >= widget.endTime && _isPlaying) {
        newPlayer.pause();
        if (!mounted) return;
        setState(() {
          _isPlaying = false;
          _reachedEnd = true;
        });
      }
    });

    _playingSub = newPlayer.stream.playing.listen((playing) {
      if (!mounted) return;
      setState(() => _isPlaying = playing);
    });

    // The widget may have been disposed while the native player was being
    // created (e.g. clip closed instantly or another clip opened) — release
    // the orphan instead of leaking a background player.
    if (!mounted) {
      await _posSub?.cancel();
      await _playingSub?.cancel();
      await _disposeQuietly(newPlayer);
      return;
    }
    setState(() {
      _player = newPlayer;
      _controller = controller;
    });

    try {
      await newPlayer.open(Media(path), play: false);
      if (!mounted) {
        await _disposeQuietly(newPlayer);
        return;
      }
      await newPlayer.seek(widget.startTime);
      if (!mounted) {
        await _disposeQuietly(newPlayer);
        return;
      }
      await newPlayer.play();
    } catch (_) {
      if (!mounted) return;
      setState(() => _fileMissing = true);
    }
  }

  /// `file://` URIs (from drag-drop / open-with flows) → plain paths so the
  /// existence check and the media engine agree on the same file.
  String _normalizeVideoPath(String raw) {
    final trimmed = raw.trim();
    if (trimmed.startsWith('file://')) {
      try {
        return Uri.parse(trimmed).toFilePath();
      } catch (_) {
        return trimmed;
      }
    }
    return trimmed;
  }

  bool _isRemotePath(String path) =>
      path.startsWith('http://') || path.startsWith('https://');

  /// Dispose that tolerates an already-disposed player (teardown may have
  /// run first when init and dispose race each other).
  Future<void> _disposeQuietly(Player player) async {
    try {
      await player.dispose();
    } catch (_) {}
  }

  Future<void> _replay() async {
    final player = _player;
    if (player == null || !mounted) return;
    setState(() => _reachedEnd = false);
    try {
      await player.seek(widget.startTime);
      if (!mounted) return;
      await player.play();
    } catch (_) {}
  }

  Future<void> _togglePlayPause() async {
    final player = _player;
    if (player == null || !mounted) return;
    try {
      if (_isPlaying) {
        await player.pause();
      } else {
        if (_reachedEnd || _currentPos >= widget.endTime) {
          await player.seek(widget.startTime);
          if (!mounted) return;
          setState(() => _reachedEnd = false);
        }
        await player.play();
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    try {
      _posSub?.cancel();
      _playingSub?.cancel();
    } catch (_) {}
    // Null first so in-flight init cannot double-dispose through this path.
    final player = _player;
    _player = null;
    if (player != null) {
      _disposeQuietly(player);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_fileMissing) {
      return Container(
        height: 180,
        decoration: BoxDecoration(
          color: const Color(0xFF1B1923),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
        ),
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.broken_image_rounded,
                  color: Colors.redAccent, size: 36),
              const SizedBox(height: 8),
              const Text(
                'Video file not found or moved',
                style:
                    TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                widget.videoPath,
                style: const TextStyle(color: Color(0xFF8A8A93), fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      );
    }

    if (_controller == null) {
      return Container(
        height: 200,
        decoration: BoxDecoration(
          color: const Color(0xFF141318),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: CircularProgressIndicator(
              color: AppColors.primary, strokeWidth: 2),
        ),
      );
    }

    final clipDuration = widget.endTime - widget.startTime;
    final elapsedInClip = (_currentPos - widget.startTime).inMilliseconds.clamp(
          0,
          clipDuration.inMilliseconds > 0 ? clipDuration.inMilliseconds : 1,
        );
    final progress = clipDuration.inMilliseconds > 0
        ? (elapsedInClip / clipDuration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 220,
        color: Colors.black,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            // Video Output
            Center(
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Video(
                  controller: _controller!,
                  controls: NoVideoControls,
                ),
              ),
            ),

            // Controls Gradient Overlay
            Container(
              height: 52,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withValues(alpha: 0.85),
                    Colors.transparent,
                  ],
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                ),
              ),
            ),

            // Clip Progress Bar
            Positioned(
              bottom: 40,
              left: 12,
              right: 12,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 3,
                  backgroundColor: Colors.white24,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              ),
            ),

            // Control Buttons Bar
            Positioned(
              bottom: 4,
              left: 8,
              right: 8,
              child: Row(
                children: [
                  // Play / Pause
                  IconButton(
                    icon: Icon(
                      _isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                    onPressed: _togglePlayPause,
                  ),

                  // Replay Button
                  IconButton(
                    tooltip: 'Replay Clip',
                    icon: const Icon(
                      Icons.replay_rounded,
                      color: AppColors.primary,
                      size: 22,
                    ),
                    onPressed: _replay,
                  ),

                  const SizedBox(width: 8),

                  // Time indicator
                  Text(
                    '${(elapsedInClip / 1000).toStringAsFixed(1)}s / ${(clipDuration.inMilliseconds / 1000).toStringAsFixed(1)}s',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                  const Spacer(),

                  // Close button
                  if (widget.onClose != null)
                    IconButton(
                      tooltip: 'Close Video',
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white60,
                        size: 20,
                      ),
                      onPressed: widget.onClose,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
