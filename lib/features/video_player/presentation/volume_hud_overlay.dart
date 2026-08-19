import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexo_player/features/video_player/providers/player_provider.dart';
import 'package:lexo_player/core/theme/app_colors.dart';

/// A modern, right-edge vertical Volume HUD indicator (iOS / macOS / IINA style).
class VolumeHudOverlay extends ConsumerStatefulWidget {
  const VolumeHudOverlay({super.key});

  @override
  ConsumerState<VolumeHudOverlay> createState() => _VolumeHudOverlayState();
}

class _VolumeHudOverlayState extends ConsumerState<VolumeHudOverlay> {
  Timer? _hideTimer;
  bool _isVisible = false;
  VolumeHudData? _lastData;

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _triggerHud(VolumeHudData data) {
    _hideTimer?.cancel();
    setState(() {
      _lastData = data;
      _isVisible = true;
    });

    _hideTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() {
          _isVisible = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<VolumeHudData?>(volumeHudProvider, (previous, next) {
      if (next != null) {
        _triggerHud(next);
      }
    });

    if (_lastData == null) return const SizedBox.shrink();

    final volume = _lastData!.volume;
    final isMuted = _lastData!.isMuted || volume == 0;
    final isBoosted = volume > 100.0;
    final percentage = volume.round();

    IconData volumeIcon;
    if (isMuted) {
      volumeIcon = Icons.volume_off_rounded;
    } else if (volume < 33) {
      volumeIcon = Icons.volume_mute_rounded;
    } else if (volume < 66) {
      volumeIcon = Icons.volume_down_rounded;
    } else if (isBoosted) {
      volumeIcon = Icons.bolt_rounded;
    } else {
      volumeIcon = Icons.volume_up_rounded;
    }

    final activeColor = isMuted
        ? Colors.redAccent
        : (isBoosted ? const Color(0xFFFF9100) : AppColors.primary);

    return Positioned(
      right: 32,
      top: 0,
      bottom: 0,
      child: Center(
        child: AnimatedOpacity(
          opacity: _isVisible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: AnimatedSlide(
            offset: _isVisible ? Offset.zero : const Offset(0.3, 0),
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  width: 56,
                  height: 180,
                  padding:
                      const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16161A).withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: isBoosted
                          ? const Color(0xFFFF9100).withValues(alpha: 0.4)
                          : Colors.white.withValues(alpha: 0.15),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Icon(
                        volumeIcon,
                        color: activeColor,
                        size: 20,
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: RotatedBox(
                          quarterTurns:
                              3, // Vertical orientation (bottom to top)
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: isMuted
                                  ? 0.0
                                  : (volume / 200.0).clamp(0.0, 1.0),
                              backgroundColor: Colors.white12,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(activeColor),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          isMuted ? 'OFF' : '$percentage%',
                          maxLines: 1,
                          softWrap: false,
                          style: TextStyle(
                            color: isMuted
                                ? Colors.redAccent
                                : (isBoosted
                                    ? const Color(0xFFFF9100)
                                    : Colors.white),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            fontFeatures: const [FontFeature.tabularFigures()],
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
      ),
    );
  }
}
