import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:lexo_player/core/engine/engine_providers.dart';
import 'package:lexo_player/core/models/engine_output.dart';
import 'package:lexo_player/core/theme/app_colors.dart';
import 'package:lexo_player/core/utils/word_tokenizer.dart';
import 'package:lexo_player/features/subtitles/presentation/subtitle_word_widget.dart';
import 'package:lexo_player/features/subtitles/providers/subtitle_providers.dart';

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
                      (_isHovered && hasSecondaryTrack) ? 8 : 10,
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
                        // Translation toggle — always visible on touch
                        // devices, hover-or-focus visible on desktop.
                        if (hasSecondaryTrack)
                          _TranslationToggle(
                            isHovered: _isHovered,
                            isSecondaryVisible: isSecondaryVisible,
                            isPersian: isPersian,
                            onToggle: () {
                              ref
                                  .read(
                                      isSecondarySubtitleVisibleProvider
                                          .notifier)
                                  .state = !isSecondaryVisible;
                            },
                            onFocusChange: (focused) {
                              if (focused) {
                                setState(() => _isHovered = true);
                              }
                            },
                          ),

                        // Interactive Tokenized Primary Subtitle Text
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
                          border: Border.all(
                              color: Colors.white24, width: 0.8),
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
