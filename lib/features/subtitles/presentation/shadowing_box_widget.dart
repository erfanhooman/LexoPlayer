import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:lexo_player/core/services/stt_service.dart';
import 'package:lexo_player/core/theme/app_colors.dart';
import 'package:lexo_player/core/utils/speech_matcher.dart';
import 'package:lexo_player/core/widgets/glass_container.dart';
import 'package:lexo_player/core/engine/engine_providers.dart';
import 'package:lexo_player/features/video_player/providers/player_provider.dart';

/// Interactive Shadowing Practice Box overlay.
/// Listens to user speech in real time, compares recognized tokens against
/// [targetSentence], highlights matches in green / mismatches in red,
/// and auto-resumes playback upon 100% completion.
///
/// The "hear" button replays the actual movie audio for the practiced cue
/// ([cueStart]..[cueEnd]) instead of a synthesized voice.
class ShadowingBoxWidget extends ConsumerStatefulWidget {
  final String targetSentence;

  /// Start timestamp of the practiced subtitle cue in the video.
  /// When null, replay falls back to the current player position.
  final Duration? cueStart;

  /// End timestamp of the practiced subtitle cue in the video.
  /// When null, replay plays a short window from [cueStart].
  final Duration? cueEnd;
  final VoidCallback onResume;
  final VoidCallback onClose;

  const ShadowingBoxWidget({
    super.key,
    required this.targetSentence,
    this.cueStart,
    this.cueEnd,
    required this.onResume,
    required this.onClose,
  });

  @override
  ConsumerState<ShadowingBoxWidget> createState() => _ShadowingBoxWidgetState();
}

class _ShadowingBoxWidgetState extends ConsumerState<ShadowingBoxWidget>
    with SingleTickerProviderStateMixin {
  String _spokenText = '';
  bool _isListening = false;
  bool _isComplete = false;
  bool _isMicUnavailable = false;
  bool _isReplaying = false;
  Timer? _autoResumeTimer;
  StreamSubscription<Duration>? _replaySub;
  // Player captured at replay time (never via `ref` in dispose — see below).
  Player? _replayPlayer;
  int _countdownSeconds = 2;
  final TextEditingController _fallbackController = TextEditingController();

  // Captured in initState: `ref` must NOT be used in dispose() (Riverpod
  // detaches it before State.dispose runs, throwing StateError and crashing
  // the app on every exit from this widget).
  late final SttService _stt;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _stt = ref.read(sttServiceProvider);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnimation =
        Tween<double>(begin: 0.85, end: 1.25).animate(_pulseController);

    _startListening();
  }

  Future<void> _startListening({bool clearSpoken = true}) async {
    final available = await _stt.initialize();

    if (!mounted) return;

    if (!available) {
      setState(() {
        _isMicUnavailable = true;
      });
      return;
    }

    setState(() {
      _isListening = true;
      _isComplete = false;
      if (clearSpoken) _spokenText = '';
      _isMicUnavailable = false;
    });

    await _stt.startListening(
      onResult: (recognized) {
        if (!mounted) return;
        setState(() {
          _spokenText = recognized;
        });

        final result = SpeechMatcher.evaluate(
          spokenText: _spokenText,
          targetSentence: widget.targetSentence,
        );

        if (result.isComplete && !_isComplete) {
          _onMatchCompleted();
        }
      },
    );
  }

  void _onMatchCompleted() {
    _autoResumeTimer?.cancel();
    setState(() {
      _isComplete = true;
      _isListening = false;
      _countdownSeconds = 2;
    });

    _stt.stopListening();

    _autoResumeTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_countdownSeconds <= 1) {
        timer.cancel();
        widget.onResume();
      } else {
        setState(() => _countdownSeconds--);
      }
    });
  }

  Future<void> _retry() async {
    _autoResumeTimer?.cancel();
    await _cancelReplay(resumeListening: false);
    _fallbackController.clear();
    setState(() {
      _isComplete = false;
      _spokenText = '';
    });
    await _startListening();
  }

  /// Replays the actual movie audio for the practiced cue ([cueStart]..[cueEnd]).
  ///
  /// Mic capture is paused while the movie plays so the soundtrack is not
  /// transcribed, then resumed without wiping the user's spoken progress.
  /// Tapping again mid-replay stops the replay.
  Future<void> _replayMovieAudio() async {
    if (_isReplaying) {
      await _cancelReplay(resumeListening: true);
      return;
    }

    await _replaySub?.cancel();
    _replaySub = null;
    _autoResumeTimer?.cancel();
    await _stt.stopListening();
    if (!mounted) return;
    setState(() {
      _isListening = false;
      _isComplete = false;
      _isReplaying = true;
    });

    late final Player player;
    try {
      player = ref.read(playerProvider);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isReplaying = false);
      await _startListening(clearSpoken: false);
      return;
    }
    _replayPlayer = player;

    var start = widget.cueStart ?? player.state.position;
    if (start < Duration.zero) start = Duration.zero;
    var end = widget.cueEnd ?? (start + const Duration(seconds: 4));
    if (end <= start) end = start + const Duration(seconds: 4);
    final replayEnd = end;

    try {
      await player.seek(start);
      await player.play();
    } catch (_) {
      if (!mounted) return;
      setState(() => _isReplaying = false);
      await _startListening(clearSpoken: false);
      return;
    }

    _replaySub = player.stream.position.listen((pos) async {
      if (pos >= replayEnd) {
        await _finishReplay();
      }
    });
  }

  /// Called when the replayed cue reaches [cueEnd]: pauses the movie and
  /// resumes mic capture, keeping the user's spoken progress.
  Future<void> _finishReplay() async {
    if (!_isReplaying) return;
    await _replaySub?.cancel();
    _replaySub = null;
    try {
      await _replayPlayer?.pause();
    } catch (_) {}
    _replayPlayer = null;
    if (!mounted) return;
    setState(() => _isReplaying = false);
    await _startListening(clearSpoken: false);
  }

  /// Stops an in-progress replay. When [resumeListening] is true, mic
  /// capture resumes without wiping spoken progress.
  Future<void> _cancelReplay({required bool resumeListening}) async {
    if (!_isReplaying && _replaySub == null && _replayPlayer == null) return;
    await _replaySub?.cancel();
    _replaySub = null;
    try {
      await _replayPlayer?.pause();
    } catch (_) {}
    _replayPlayer = null;
    if (!mounted) return;
    setState(() => _isReplaying = false);
    if (resumeListening) {
      await _startListening(clearSpoken: false);
    }
  }

  @override
  void dispose() {
    _autoResumeTimer?.cancel();
    _replaySub?.cancel();
    _replaySub = null;
    // NOTE: no `ref` use here by design (see field docs above).
    // Best-effort pause so closing mid-replay leaves the video paused.
    _replayPlayer?.pause();
    _replayPlayer = null;
    _pulseController.dispose();
    _fallbackController.dispose();
    _stt.stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPersian = ref.watch(appLanguageProvider) == 'fa';
    final eval = SpeechMatcher.evaluate(
      spokenText: _spokenText,
      targetSentence: widget.targetSentence,
    );

    return Container(
      constraints: const BoxConstraints(maxWidth: 580),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: GlassContainer(
        borderRadius: BorderRadius.circular(18),
        borderColor: _isComplete
            ? Colors.greenAccent.withValues(alpha: 0.6)
            : AppColors.primary.withValues(alpha: 0.4),
        color: const Color(0xFF141318).withValues(alpha: 0.94),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Top Header Bar ──────────────────────────────────────────────
            Row(
              children: [
                ScaleTransition(
                  scale: _isListening
                      ? _pulseAnimation
                      : const AlwaysStoppedAnimation(1.0),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: _isComplete
                          ? Colors.greenAccent.withValues(alpha: 0.2)
                          : AppColors.primary.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isComplete
                          ? Icons.check_circle_rounded
                          : Icons.record_voice_over_rounded,
                      color:
                          _isComplete ? Colors.greenAccent : AppColors.primary,
                      size: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isPersian
                        ? 'تمرین سایه‌خوانی (Shadowing)'
                        : 'Shadowing Practice',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                // Replay the actual movie audio for this sentence
                IconButton(
                  tooltip: isPersian
                      ? (_isReplaying
                          ? 'توقف پخش صدای فیلم'
                          : 'پخش صدای فیلم')
                      : (_isReplaying ? 'Stop movie audio' : 'Replay movie audio'),
                  icon: Icon(
                      _isReplaying
                          ? Icons.stop_circle_outlined
                          : Icons.replay_rounded,
                      color: _isReplaying
                          ? AppColors.primary
                          : Colors.white70,
                      size: 20),
                  onPressed: _replayMovieAudio,
                ),

                // Close Button
                IconButton(
                  tooltip: isPersian ? 'بستن' : 'Close',
                  icon: const Icon(Icons.close_rounded,
                      color: Colors.white60, size: 20),
                  onPressed: widget.onClose,
                ),
              ],
            ),

            const SizedBox(height: 8),

            // ── Target Reference Sentence ───────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                widget.targetSentence,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ),

            const SizedBox(height: 12),

            // ── Live Speech Transcript Box / Typing Fallback ─────────────────
            Container(
              constraints: const BoxConstraints(minHeight: 64),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0C0B0E),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _isComplete
                      ? Colors.greenAccent.withValues(alpha: 0.5)
                      : (_spokenText.isNotEmpty
                          ? const Color(0xFF383745)
                          : const Color(0xFF24232C)),
                ),
              ),
              child: _isMicUnavailable
                  ? _buildFallbackTextInput(isPersian)
                  : _buildLiveSpeechTranscript(eval, isPersian),
            ),

            const SizedBox(height: 12),

            // ── Bottom Action Row ────────────────────────────────────────────
            if (_isComplete)
              _buildSuccessBanner(isPersian)
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      _isReplaying
                          ? (isPersian
                              ? 'در حال پخش صدای فیلم...'
                              : 'Replaying movie audio...')
                          : (_isListening
                              ? (isPersian
                                  ? 'در حال گوش دادن... صحبت کنید'
                                  : 'Listening... speak now')
                              : (isPersian ? 'متوقف شد' : 'Paused')),
                      style: TextStyle(
                        color: (_isListening || _isReplaying)
                            ? AppColors.primary
                            : Colors.white38,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Row(
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: Text(isPersian ? 'تلاش مجدد' : 'Retry'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white70,
                          textStyle: const TextStyle(fontSize: 12),
                        ),
                        onPressed: _retry,
                      ),
                      const SizedBox(width: 6),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white12,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          textStyle: const TextStyle(fontSize: 12),
                        ),
                        onPressed: widget.onResume,
                        child: Text(isPersian ? 'ادامه ویدیو' : 'Resume Video'),
                      ),
                    ],
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveSpeechTranscript(SpeechMatchResult eval, bool isPersian) {
    if (_spokenText.isEmpty) {
      return Center(
        child: Text(
          isPersian
              ? 'جمله را تکرار کنید (صحبت کنید)...'
              : 'Repeat the sentence into your microphone...',
          style: const TextStyle(
              color: Color(0xFF6B6A75),
              fontSize: 13,
              fontStyle: FontStyle.italic),
        ),
      );
    }

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      alignment: WrapAlignment.center,
      children: [
        for (final token in eval.spokenTokens)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: token.isMatch
                  ? Colors.greenAccent.withValues(alpha: 0.18)
                  : Colors.redAccent.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: token.isMatch
                    ? Colors.greenAccent.withValues(alpha: 0.5)
                    : Colors.redAccent.withValues(alpha: 0.5),
                width: 0.8,
              ),
            ),
            child: Text(
              token.text,
              style: TextStyle(
                color: token.isMatch ? Colors.greenAccent : Colors.redAccent,
                fontSize: 14,
                fontWeight: token.isMatch ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildFallbackTextInput(bool isPersian) {
    return TextField(
      controller: _fallbackController,
      onChanged: (val) {
        setState(() => _spokenText = val);
        final result = SpeechMatcher.evaluate(
          spokenText: _spokenText,
          targetSentence: widget.targetSentence,
        );
        if (result.isComplete && !_isComplete) {
          _onMatchCompleted();
        }
      },
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        hintText: isPersian
            ? 'میکروفون در دسترس نیست. جمله را تایپ کنید...'
            : 'Microphone unavailable. Type the sentence to practice...',
        hintStyle: const TextStyle(color: Color(0xFF6B6A75), fontSize: 12),
        border: InputBorder.none,
        isDense: true,
      ),
    );
  }

  Widget _buildSuccessBanner(bool isPersian) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.greenAccent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded,
              color: Colors.greenAccent, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isPersian
                  ? 'عالی! تطابق ۱۰۰٪ — ادامه در $_countdownSeconds ثانیه...'
                  : 'Perfect match! Resuming video in $_countdownSeconds s...',
              style: const TextStyle(
                color: Colors.greenAccent,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              _autoResumeTimer?.cancel();
              _retry();
            },
            child: Text(isPersian ? 'تکرار' : 'Retry',
                style: const TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.greenAccent,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            ),
            onPressed: () {
              _autoResumeTimer?.cancel();
              widget.onResume();
            },
            child: Text(isPersian ? 'ادامه' : 'Resume Now',
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
