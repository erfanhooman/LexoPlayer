import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:lexo_player/core/engine/engine_providers.dart';
import 'package:lexo_player/core/models/engine_output.dart';
import 'package:lexo_player/core/theme/app_colors.dart';
import 'package:lexo_player/core/utils/word_tokenizer.dart';
import 'package:lexo_player/features/subtitles/presentation/subtitle_word_widget.dart';
import 'package:lexo_player/features/subtitles/providers/subtitle_providers.dart';
import 'package:lexo_player/features/video_player/providers/player_provider.dart';
import 'package:lexo_player/features/subtitles/presentation/shadowing_box_widget.dart';

/// Displays the active subtitle text at the bottom of the video player.
///
/// Supports dual subtitles (Primary + Secondary translation).
/// The secondary translation subtitle is stacked above the primary text,
/// rendered in a slightly smaller font size, and can be toggled via a minimal
/// pill button that ONLY appears when hovering over the subtitle container.
class InteractiveSubtitleOverlay extends ConsumerStatefulWidget {
  const InteractiveSubtitleOverlay({super.key});

  @override
  ConsumerState<InteractiveSubtitleOverlay> createState() =>
      _InteractiveSubtitleOverlayState();
}

class _InteractiveSubtitleOverlayState
    extends ConsumerState<InteractiveSubtitleOverlay> {
  bool _isHovered = false;

  /// Cue timings captured when shadowing practice opens, so the shadowing
  /// box can replay the actual movie audio for the practiced sentence.
  Duration? _shadowingCueStart;
  Duration? _shadowingCueEnd;

  /// Matches right-to-left scripts (Hebrew, Arabic, Persian, Urdu, etc.).
  static final RegExp _rtlRegex = RegExp(
    r'[\u0590-\u05FF\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\uFB1D-\uFB4F\uFB50-\uFDFF\uFE70-\uFEFF]',
  );

  @override
  Widget build(BuildContext context) {
    final subtitleText = ref.watch(activeSubtitleTextProvider);
    final secondaryText = ref.watch(activeSecondarySubtitleTextProvider);
    final isSecondaryVisible = ref.watch(isSecondarySubtitleVisibleProvider);
    final hasSecondaryTrack =
        ref.watch(selectedSecondarySubtitleProvider) != null &&
            ref.watch(selectedSecondarySubtitleProvider)!.id != 'none';

    final isVisible = ref.watch(subtitleVisibilityProvider);
    final engineOutputAsync = ref.watch(engineOutputProvider);

    const bottomOffset = 110.0;

    if ((subtitleText == null && secondaryText == null) || !isVisible) {
      return AnimatedPositioned(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        bottom: bottomOffset,
        left: 0,
        right: 0,
        child: const SizedBox.shrink(),
      );
    }

    final engineOutput = engineOutputAsync.valueOrNull;
    final displayText = engineOutput?.targetSentence ?? subtitleText ?? '';
    final spans = engineOutput?.hierarchicalSpans ?? const <SpanModel>[];

    final isPersian = ref.watch(appLanguageProvider) == 'fa';

    // ── Active Shadowing Box View ───────────────────────────────────────────
    final isShadowingActive = ref.watch(activeShadowingStateProvider);
    if (isShadowingActive && displayText.isNotEmpty) {
      return AnimatedPositioned(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        bottom: bottomOffset,
        left: 0,
        right: 0,
        child: Center(
          child: ShadowingBoxWidget(
            targetSentence: displayText,
            cueStart: _shadowingCueStart,
            cueEnd: _shadowingCueEnd,
            onResume: () {
              ref.read(activeShadowingStateProvider.notifier).state = false;
              final player = ref.read(playerProvider);
              PlayerActions.play(player);
            },
            onClose: () {
              ref.read(activeShadowingStateProvider.notifier).state = false;
            },
          ),
        ),
      );
    }

    final isShadowingEnabled = ref.watch(isShadowingModeEnabledProvider);
    final isSpoilerMode = ref.watch(isSubtitleSpoilerModeEnabledProvider);
    final activeIndex = ref.watch(activeSubtitleIndexProvider);
    final revealedIndex = ref.watch(activeRevealedSubtitleCueIndexProvider);
    final isSpoilerBlurred =
        isSpoilerMode && (activeIndex == null || revealedIndex != activeIndex);

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      bottom: bottomOffset,
      left: 0,
      right: 0,
      child: Center(
        child: MouseRegion(
          hitTestBehavior: HitTestBehavior.opaque,
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Secondary Translation Subtitle — Stacked Non-Overlapping above Primary
                if (secondaryText != null && isSecondaryVisible)
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Container(
                      key: ValueKey<String>('sec_$secondaryText'),
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: Color(ref.watch(subtitleBgColorProvider))
                            .withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white12, width: 0.8),
                      ),
                      child: Text(
                        secondaryText,
                        textAlign: TextAlign.center,
                        textDirection:
                            RegExp(r'[\u0600-\u06FF]').hasMatch(secondaryText)
                                ? TextDirection.rtl
                                : TextDirection.ltr,
                        style: _secondaryStyle(ref),
                      ),
                    ),
                  ),

                // Primary Interactive Subtitle Container
                if (displayText.isNotEmpty)
                  Container(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      _isHovered ? 8 : 10,
                      16,
                      10,
                    ),
                    decoration: BoxDecoration(
                      color: Color(ref.watch(subtitleBgColorProvider)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Action row: translation toggle, shadowing mic & spoiler blur.
                        // Always present so the spoiler toggle is discoverable
                        // right on the video (buttons self-hide off-hover).
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (hasSecondaryTrack)
                              _TranslationToggle(
                                isHovered: _isHovered,
                                isSecondaryVisible: isSecondaryVisible,
                                isPersian: isPersian,
                                onToggle: () {
                                  ref
                                      .read(isSecondarySubtitleVisibleProvider
                                          .notifier)
                                      .state = !isSecondaryVisible;
                                },
                                onFocusChange: (focused) {
                                  if (focused) {
                                    setState(() => _isHovered = true);
                                  }
                                },
                              ),
                            if (hasSecondaryTrack && isShadowingEnabled)
                              const SizedBox(width: 8),
                            if (isShadowingEnabled)
                              _ShadowingButton(
                                isHovered: _isHovered,
                                isPersian: isPersian,
                                onTap: () {
                                  final player = ref.read(playerProvider);
                                  // Capture the practiced cue's timings before
                                  // pausing, so the shadowing box can replay
                                  // the actual movie audio for this sentence.
                                  final block = ref.read(
                                      activeSubtitleBlockProvider);
                                  final fallbackStart =
                                      player.state.position;
                                  _shadowingCueStart = block?.startTime ??
                                      fallbackStart;
                                  final blockEnd = block?.endTime;
                                  _shadowingCueEnd =
                                      (blockEnd != null &&
                                              blockEnd >
                                                  _shadowingCueStart!)
                                          ? blockEnd
                                          : _shadowingCueStart! +
                                              const Duration(seconds: 4);
                                  PlayerActions.pause(player);
                                  ref
                                      .read(
                                          activeShadowingStateProvider.notifier)
                                      .state = true;
                                },
                              ),
                            if (hasSecondaryTrack || isShadowingEnabled)
                              const SizedBox(width: 8),
                            _SpoilerButton(
                              isHovered: _isHovered,
                              isPersian: isPersian,
                              isActive: isSpoilerMode,
                              onTap: () {
                                final next = !isSpoilerMode;
                                ref
                                    .read(isSubtitleSpoilerModeEnabledProvider
                                        .notifier)
                                    .state = next;
                                if (next) {
                                  // Blur the current cue immediately instead
                                  // of leaving a previously revealed one open.
                                  ref
                                      .read(
                                          activeRevealedSubtitleCueIndexProvider
                                              .notifier)
                                      .state = null;
                                }
                                saveSubtitleSpoilerMode(next);
                              },
                            ),
                          ],
                        ),

                        // Interactive Primary Subtitle Text (with optional Spoiler Blur)
                        if (isSpoilerBlurred)
                          Semantics(
                            button: true,
                            label: isPersian
                                ? 'کلیک کنید برای مشاهده'
                                : 'Click to reveal subtitle',
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                if (activeIndex != null) {
                                  ref
                                      .read(
                                          activeRevealedSubtitleCueIndexProvider
                                              .notifier)
                                      .state = activeIndex;
                                }
                              },
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  // NOTE: intentionally non-interactive plain
                                  // text here. Using _buildTokens() would mount
                                  // SubtitleWordWidgets with their own tap /
                                  // hover recognizers that win the gesture
                                  // arena and prevent the reveal tap from
                                  // firing (tap did nothing).
                                  ImageFiltered(
                                    imageFilter: ImageFilter.blur(
                                        sigmaX: 7.0, sigmaY: 7.0),
                                    child: _buildSpoilerBlurredText(
                                        displayText, ref),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.black
                                          .withValues(alpha: 0.75),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                          color: Colors.white24, width: 0.8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                            Icons.visibility_off_rounded,
                                            color: Colors.white70, size: 14),
                                        const SizedBox(width: 6),
                                        Text(
                                          isPersian
                                              ? 'کلیک کنید برای مشاهده'
                                              : 'Click to reveal subtitle',
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          _buildTokens(displayText, spans, ref),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Plain non-interactive text used for the spoiler-blurred state, so the
  /// outer reveal [GestureDetector] reliably wins the gesture arena.
  Widget _buildSpoilerBlurredText(
    String displayText,
    WidgetRef ref,
  ) {
    final isRtl = _rtlRegex.hasMatch(displayText);
    return Text(
      displayText,
      textAlign: TextAlign.center,
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      style: _baseStyle(ref),
    );
  }

  /// Tokenizes [displayText] word-by-word and maps each word to the span
  /// that contains its character range.
  Widget _buildTokens(
    String displayText,
    List<SpanModel> spans,
    WidgetRef ref,
  ) {
    // Right-to-left text (Persian/Arabic/Hebrew) must not be split into tokens:
    // reordering words would scramble the reading order. Render it as a single
    // directional Text instead.
    if (_rtlRegex.hasMatch(displayText)) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1),
        child: Text(
          displayText,
          textAlign: TextAlign.center,
          textDirection: TextDirection.rtl,
          style: _baseStyle(ref),
        ),
      );
    }

    final tokens = WordTokenizer.tokenize(displayText);

    int offset = 0;
    final tokenStarts = <int>[];
    for (final t in tokens) {
      tokenStarts.add(offset);
      offset += t.text.length;
    }

    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (int i = 0; i < tokens.length; i++)
          _buildTokenWidget(tokens[i], tokenStarts[i], spans, ref),
      ],
    );
  }

  Widget _buildTokenWidget(
    TokenSpan token,
    int charStart,
    List<SpanModel> spans,
    WidgetRef ref,
  ) {
    if (!token.isWord) {
      final text = token.text.replaceAll(RegExp(r'[\r\n\t]'), ' ');
      return Text(text, style: _baseStyle(ref));
    }

    final charEnd = charStart + token.text.length;

    SpanModel? matchedSpan;
    for (final span in spans) {
      if (charStart >= span.startChar && charEnd <= span.endChar) {
        matchedSpan = span;
        break;
      }
    }

    matchedSpan ??= spans
        .where((s) => charStart < s.endChar && charEnd > s.startChar)
        .firstOrNull;

    final cleanTok = token.text.toLowerCase().replaceAll(RegExp(r"[^\w']"), '');
    if (cleanTok.isNotEmpty) {
      matchedSpan ??= spans.where((s) {
        final cleanSpanText =
            s.text.toLowerCase().replaceAll(RegExp(r"[^\w']"), '');
        return cleanSpanText == cleanTok;
      }).firstOrNull;
    }

    matchedSpan ??= SpanModel(
      spanId: 'fallback_$charStart',
      type: SpanType.singleWord,
      category: 'WORD',
      text: token.text,
      startChar: charStart,
      endChar: charEnd,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: SubtitleWordWidget(
        text: token.text,
        span: matchedSpan,
      ),
    );
  }

  TextStyle _baseStyle(WidgetRef ref) {
    final size = ref.watch(subtitleSizeProvider);
    final colorVal = ref.watch(subtitleColorProvider);
    final outlineWidth = ref.watch(subtitleOutlineWidthProvider);
    final font = ref.watch(subtitleFontFamilyProvider);

    return TextStyle(
      color: Color(colorVal),
      fontSize: size,
      fontWeight: FontWeight.bold,
      fontFamily: font == 'System' ? null : font,
      shadows: outlineWidth > 0
          ? [
              Shadow(
                  offset: Offset(-outlineWidth, -outlineWidth),
                  color: Colors.black),
              Shadow(
                  offset: Offset(outlineWidth, -outlineWidth),
                  color: Colors.black),
              Shadow(
                  offset: Offset(outlineWidth, outlineWidth),
                  color: Colors.black),
              Shadow(
                  offset: Offset(-outlineWidth, outlineWidth),
                  color: Colors.black),
            ]
          : const [
              Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black),
              Shadow(
                  offset: Offset(-1, -1), blurRadius: 3, color: Colors.black),
            ],
    );
  }

  TextStyle _secondaryStyle(WidgetRef ref) {
    final size = ref.watch(subtitleSizeProvider);
    final colorVal = ref.watch(subtitleColorProvider);
    final outlineWidth = ref.watch(subtitleOutlineWidthProvider);
    final font = ref.watch(subtitleFontFamilyProvider);

    return TextStyle(
      color: Color(colorVal).withValues(alpha: 0.95),
      fontSize: size * 0.82, // Slightly smaller than primary font size
      fontWeight: FontWeight.w600,
      fontFamily: font == 'System' ? null : font,
      shadows: outlineWidth > 0
          ? [
              Shadow(
                  offset: Offset(-outlineWidth * 0.8, -outlineWidth * 0.8),
                  color: Colors.black),
              Shadow(
                  offset: Offset(outlineWidth * 0.8, -outlineWidth * 0.8),
                  color: Colors.black),
              Shadow(
                  offset: Offset(outlineWidth * 0.8, outlineWidth * 0.8),
                  color: Colors.black),
              Shadow(
                  offset: Offset(-outlineWidth * 0.8, outlineWidth * 0.8),
                  color: Colors.black),
            ]
          : const [
              Shadow(offset: Offset(1, 1), blurRadius: 2, color: Colors.black),
            ],
    );
  }
}

/// Translation visibility toggle.
///
/// - Touch / narrow windows: always visible (>=44pt target).
/// - Desktop: visible on hover *or* keyboard focus, with a text label for
///   screen readers and a visible focus indicator via [InkWell].
class _TranslationToggle extends StatelessWidget {
  final bool isHovered;
  final bool isSecondaryVisible;
  final bool isPersian;
  final VoidCallback onToggle;
  final ValueChanged<bool> onFocusChange;

  const _TranslationToggle({
    required this.isHovered,
    required this.isSecondaryVisible,
    required this.isPersian,
    required this.onToggle,
    required this.onFocusChange,
  });

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final isTouchOrNarrow = mq.size.width < 600 ||
        Theme.of(context).platform == TargetPlatform.android ||
        Theme.of(context).platform == TargetPlatform.iOS;
    final visible = isTouchOrNarrow || isHovered;
    final animMs = mq.disableAnimations ? 0 : 180;
    final label = isSecondaryVisible
        ? (isPersian ? 'مخفی‌سازی ترجمه' : 'Hide Translation')
        : (isPersian ? 'نمایش ترجمه' : 'Show Translation');

    return AnimatedOpacity(
      opacity: visible ? 1.0 : 0.0,
      duration: Duration(milliseconds: animMs),
      child: AnimatedContainer(
        duration: Duration(milliseconds: animMs),
        height: visible ? 36 : 0,
        margin: EdgeInsets.only(bottom: visible ? 6 : 0),
        child: visible
            ? Semantics(
                button: true,
                label: label,
                child: Focus(
                  onFocusChange: onFocusChange,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: onToggle,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        constraints:
                            const BoxConstraints(minHeight: 32, minWidth: 44),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white24, width: 0.8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isSecondaryVisible
                                  ? Icons.visibility_rounded
                                  : Icons.visibility_off_rounded,
                              color: isSecondaryVisible
                                  ? AppColors.primary
                                  : Colors.white60,
                              size: 14,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              label,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}

class _ShadowingButton extends StatelessWidget {
  final bool isHovered;
  final bool isPersian;
  final VoidCallback onTap;

  const _ShadowingButton({
    required this.isHovered,
    required this.isPersian,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = Platform.isAndroid || Platform.isIOS;
    final visible = isHovered || isMobile;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: visible ? 1.0 : 0.0,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: visible ? 36 : 0,
        margin: EdgeInsets.only(bottom: visible ? 6 : 0),
        child: visible
            ? Semantics(
                button: true,
                label: isPersian ? 'تمرین سایه‌خوانی' : 'Shadow practice',
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onTap,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      constraints:
                          const BoxConstraints(minHeight: 32, minWidth: 44),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.5),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.record_voice_over_rounded,
                            color: AppColors.primary,
                            size: 14,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isPersian ? 'تمرین سایه‌خوانی' : 'Shadow',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}

/// Spoiler blur toggle, always discoverable on the subtitle bar.
///
/// Toggles [isSubtitleSpoilerModeEnabledProvider] (same switch as Settings,
/// persisted the same way). Active state is highlighted in accent.
class _SpoilerButton extends StatelessWidget {
  final bool isHovered;
  final bool isPersian;
  final bool isActive;
  final VoidCallback onTap;

  const _SpoilerButton({
    required this.isHovered,
    required this.isPersian,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = Platform.isAndroid || Platform.isIOS;
    final visible = isHovered || isMobile;
    final label = isPersian
        ? (isActive ? 'اسپویلر فعال' : 'اسپویلر')
        : (isActive ? 'Spoiler on' : 'Spoiler');

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: visible ? 1.0 : 0.0,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: visible ? 36 : 0,
        margin: EdgeInsets.only(bottom: visible ? 6 : 0),
        child: visible
            ? Semantics(
                button: true,
                label: label,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onTap,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      constraints:
                          const BoxConstraints(minHeight: 32, minWidth: 44),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isActive
                            ? AppColors.primary.withValues(alpha: 0.18)
                            : Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isActive
                              ? AppColors.primary.withValues(alpha: 0.5)
                              : Colors.white24,
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isActive
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                            color:
                                isActive ? AppColors.primary : Colors.white60,
                            size: 14,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}
