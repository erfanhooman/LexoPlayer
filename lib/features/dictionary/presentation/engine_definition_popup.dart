import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexo_player/core/engine/engine_providers.dart';
import 'package:lexo_player/core/models/engine_output.dart';
import 'package:lexo_player/core/utils/word_tokenizer.dart';
import 'package:lexo_player/features/dictionary/data/span_providers.dart';
import 'package:lexo_player/features/dictionary/data/unified_dictionary_repository.dart';
import 'package:lexo_player/features/dictionary/presentation/spoiler_translation_widget.dart';
import 'package:lexo_player/features/video_player/providers/player_provider.dart';

/// Engine-powered definition popup for displaying hierarchical span data.
///
/// - SINGLE_WORD spans: word + lemma + POS header, top-3 Persian translations
///   with a "more" expander, then ranked WSD meanings.
/// - MULTI_WORD_SPAN spans: a slide/carousel — the parent (idiom) view first,
///   then one slide per child word, all rendered with the same style.
class EngineDefinitionPopup extends ConsumerStatefulWidget {
  const EngineDefinitionPopup({super.key});

  @override
  ConsumerState<EngineDefinitionPopup> createState() =>
      _EngineDefinitionPopupState();
}

class _EngineDefinitionPopupState extends ConsumerState<EngineDefinitionPopup> {
  OverlayEntry? _overlayEntry;

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    if (Platform.isAndroid || Platform.isIOS || MediaQuery.of(context).size.width < 600) {
      return _MobileLookupListener();
    }

    ref.listen<SelectedSpanData?>(selectedSpanProvider, (prev, next) {
      _removeOverlay();
      if (next == null) return;

      final player = ref.read(playerProvider);
      PlayerActions.pause(player);

      _overlayEntry = _buildOverlayEntry(
        context: context,
        data: next,
      );
      Overlay.of(context).insert(_overlayEntry!);
    });

    return const SizedBox.shrink();
  }

  OverlayEntry _buildOverlayEntry({
    required BuildContext context,
    required SelectedSpanData data,
  }) {
    return OverlayEntry(
      builder: (overlayContext) {
        final screenSize = MediaQuery.of(context).size;
        const popupWidth = 450.0;

        var targetAnchor = Alignment.topCenter;
        var followerAnchor = Alignment.bottomCenter;
        var targetOffset = const Offset(0, -8);

        final renderBox = data.context.findRenderObject() as RenderBox?;
        if (renderBox != null && renderBox.attached) {
          final wordPos = renderBox.localToGlobal(Offset.zero);
          final wordSize = renderBox.size;

          var showBelow = false;
          if (wordPos.dy < 220) {
            showBelow = true;
            targetAnchor = Alignment.bottomCenter;
            followerAnchor = Alignment.topCenter;
          }

          final wordCenter = wordPos.dx + wordSize.width / 2;
          final popupLeft = wordCenter - popupWidth / 2;
          final popupRight = popupLeft + popupWidth;

          var dx = 0.0;
          if (popupLeft < 8) {
            dx = 8 - popupLeft;
          } else if (popupRight > screenSize.width - 8) {
            dx = screenSize.width - 8 - popupRight;
          }

          targetOffset = Offset(dx, showBelow ? 8 : -8);
        }

        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            _removeOverlay();
            ref.read(spanHoverControllerProvider).closePopup();
          },
          child: SizedBox.expand(
            child: Stack(
              children: [
                CompositedTransformFollower(
                  link: data.layerLink,
                  targetAnchor: targetAnchor,
                  followerAnchor: followerAnchor,
                  offset: targetOffset,
                  showWhenUnlinked: false,
                  child: Material(
                    color: Colors.transparent,
                    child: _EngineDefinitionCard(span: data.span),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Mobile bottom sheet listener
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _MobileLookupListener extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<SelectedSpanData?>(selectedSpanProvider, (prev, next) {
      if (next == null) return;

      final player = ref.read(playerProvider);
      PlayerActions.pause(player);

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) => _MobileBottomSheetContent(span: next.span),
      ).whenComplete(() {
        final player = ref.read(playerProvider);
        player.play();
        ref.read(selectedSpanProvider.notifier).state = null;
      });
    });
    return const SizedBox.shrink();
  }
}

class _MobileBottomSheetContent extends ConsumerStatefulWidget {
  final SpanModel span;
  const _MobileBottomSheetContent({required this.span});

  @override
  ConsumerState<_MobileBottomSheetContent> createState() => _MobileBottomSheetContentState();
}

class _MobileBottomSheetContentState extends ConsumerState<_MobileBottomSheetContent> {
  late List<SpanModel> _history;
  bool _isLoadingNested = false;

  @override
  void initState() {
    super.initState();
    _history = [widget.span];
  }

  void _navigateToWord(String rawWord) async {
    if (_isLoadingNested) return;
    setState(() => _isLoadingNested = true);

    final newSpan = await _fetchWordSpan(ref, rawWord);

    if (mounted) {
      setState(() {
        _isLoadingNested = false;
        if (newSpan != null) {
          _history.add(newSpan);
        }
      });
    }
  }

  void _popHistory() {
    if (_history.length > 1) {
      setState(() {
        _history.removeLast();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentSpan = _history.last;
    final isPersian = ref.watch(appLanguageProvider) == 'fa';

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0E0E10),
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(20),
          ),
          border: Border.all(color: const Color(0xFF2C2C35), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),

            if (_history.length > 1) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    InkWell(
                      onTap: _popHistory,
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF5500).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: const Color(0xFFFF5500).withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isPersian ? Icons.arrow_forward_rounded : Icons.arrow_back_rounded,
                              size: 14,
                              color: const Color(0xFFFF5500),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isPersian
                                  ? 'بازگشت به ${_history[_history.length - 2].text}'
                                  : 'Back to ${_history[_history.length - 2].text}',
                              style: const TextStyle(
                                color: Color(0xFFFF5500),
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_isLoadingNested)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFFFF5500),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],

            Flexible(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: _buildContent(currentSpan),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(SpanModel span) {
    if (span.isMultiWord && span.childrenSubTokens.isNotEmpty) {
      return _HierarchyCarousel(span: span, onWordTap: _navigateToWord);
    }
    return _SingleWordView(span: span, onWordTap: _navigateToWord);
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Shared definition card (desktop overlay)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _EngineDefinitionCard extends ConsumerStatefulWidget {
  final SpanModel span;
  const _EngineDefinitionCard({required this.span});

  @override
  ConsumerState<_EngineDefinitionCard> createState() => _EngineDefinitionCardState();
}

class _EngineDefinitionCardState extends ConsumerState<_EngineDefinitionCard> {
  late List<SpanModel> _history;
  bool _isLoadingNested = false;
  bool _hasMouseEnteredAfterSizeChange = true;

  @override
  void initState() {
    super.initState();
    _history = [widget.span];
  }

  @override
  void didUpdateWidget(covariant _EngineDefinitionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.span.spanId != widget.span.spanId || oldWidget.span.text != widget.span.text) {
      _history = [widget.span];
      _hasMouseEnteredAfterSizeChange = true;
    }
  }

  void _navigateToWord(String rawWord) async {
    if (_isLoadingNested) return;
    setState(() => _isLoadingNested = true);

    // Cancel auto-resume timer while navigating inside popup
    ref.read(spanHoverControllerProvider).onPopupHoverEnter();

    final newSpan = await _fetchWordSpan(ref, rawWord);

    if (mounted) {
      setState(() {
        _isLoadingNested = false;
        if (newSpan != null) {
          _history.add(newSpan);
          // Mark mouse as not re-entered yet for new size
          _hasMouseEnteredAfterSizeChange = false;
        }
      });
    }
  }

  void _popHistory() {
    if (_history.length > 1) {
      setState(() {
        _history.removeLast();
        _hasMouseEnteredAfterSizeChange = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentSpan = _history.last;
    final isPersian = ref.watch(appLanguageProvider) == 'fa';

    return MouseRegion(
      onEnter: (_) {
        setState(() {
          _hasMouseEnteredAfterSizeChange = true;
        });
        ref.read(spanHoverControllerProvider).onPopupHoverEnter();
      },
      onExit: (_) {
        // If the card shrank and left the cursor outside after nested navigation,
        // ignore exit until mouse is actually brought inside and then exits.
        if (_history.length > 1 && !_hasMouseEnteredAfterSizeChange) {
          return;
        }
        ref.read(spanHoverControllerProvider).onPopupHoverExit();
      },
      child: Container(
      width: 450,
      constraints: const BoxConstraints(maxHeight: 550),
      decoration: BoxDecoration(
        color: const Color(0xE6141416),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2C2C35), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.6),
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12.0, sigmaY: 12.0),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Nested Navigation Breadcrumb / Back button ──────
                if (_history.length > 1) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      InkWell(
                        onTap: _popHistory,
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF5500).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                                color: const Color(0xFFFF5500).withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isPersian ? Icons.arrow_forward_rounded : Icons.arrow_back_rounded,
                                size: 14,
                                color: const Color(0xFFFF5500),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isPersian
                                    ? 'بازگشت به ${_history[_history.length - 2].text}'
                                    : 'Back to ${_history[_history.length - 2].text}',
                                style: const TextStyle(
                                  color: Color(0xFFFF5500),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_isLoadingNested)
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFFFF5500),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],

                // ── Main Content View ─────────────────────────────
                Flexible(
                  child: currentSpan.isMultiWord && currentSpan.childrenSubTokens.isNotEmpty
                      ? ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 470),
                          child: _HierarchyCarousel(
                            span: currentSpan,
                            onWordTap: _navigateToWord,
                          ),
                        )
                      : _SingleWordView(
                          span: currentSpan,
                          onWordTap: _navigateToWord,
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
//  Helper function for nested database lookups
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Future<SpanModel?> _fetchWordSpan(WidgetRef ref, String rawToken) async {
  final cleanToken = rawToken.toLowerCase().trim();
  if (cleanToken.isEmpty) return null;

  try {
    final repo = ref.read(unifiedDictionaryRepositoryProvider);
    final result = await repo.lookupWordWithSenses(cleanToken, '', token: cleanToken);

    if (result != null) {
      final word = result.word;
      final wsdList = result.senses.map((s) {
        return WsdSense(
          rank: s.senseIndex,
          score: 1.0,
          definitionEn: s.definitionEn,
          translationFa: s.translationFa,
        );
      }).toList();

      final faTranslations = result.senses
          .map((s) => s.translationFa)
          .whereType<String>()
          .where((t) => t.isNotEmpty)
          .toList();

      final span = SpanModel(
        spanId: 'nested_${word.id}_${DateTime.now().millisecondsSinceEpoch}',
        type: SpanType.singleWord,
        category: 'WORD',
        text: rawToken,
        lemma: word.lemma,
        pos: word.pos.toUpperCase(),
        startChar: 0,
        endChar: rawToken.length,
        primaryTranslationFa: faTranslations.isNotEmpty ? faTranslations.first : null,
        secondaryTranslationFa: faTranslations.length > 1 ? faTranslations[1] : null,
        tertiaryTranslationFa: faTranslations.length > 2 ? faTranslations[2] : null,
        otherTranslationFa: faTranslations.length > 3 ? faTranslations.sublist(3) : const [],
        wsd: wsdList,
      );

      if (span.hasMeaningfulData) {
        return span;
      }
    }
  } catch (e) {
    // Ignore error, return null below
  }

  return null;
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Interactive definition text (clickable words inside definitions)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class InteractiveDefinitionText extends StatelessWidget {
  final String text;
  final TextStyle? baseStyle;
  final Function(String word) onWordTap;

  const InteractiveDefinitionText({
    super.key,
    required this.text,
    this.baseStyle,
    required this.onWordTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = WordTokenizer.tokenize(text);
    final style = baseStyle ??
        const TextStyle(
          color: Colors.white,
          fontSize: 13,
          height: 1.4,
        );

    return Wrap(
      alignment: WrapAlignment.start,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final token in tokens)
          if (token.isWord)
            _InteractiveWordSpan(
              word: token.text,
              baseStyle: style,
              onTap: () => onWordTap(token.text),
            )
          else
            Text(
              token.text.replaceAll(RegExp(r'[\r\n\t]'), ' '),
              style: style,
            ),
      ],
    );
  }
}

class _InteractiveWordSpan extends StatefulWidget {
  final String word;
  final TextStyle baseStyle;
  final VoidCallback onTap;

  const _InteractiveWordSpan({
    required this.word,
    required this.baseStyle,
    required this.onTap,
  });

  @override
  State<_InteractiveWordSpan> createState() => _InteractiveWordSpanState();
}

class _InteractiveWordSpanState extends State<_InteractiveWordSpan> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 100),
          style: _isHovered
              ? widget.baseStyle.copyWith(
                  color: const Color(0xFFFF5500),
                  decoration: TextDecoration.underline,
                  decorationColor: const Color(0xFFFF5500),
                )
              : widget.baseStyle,
          child: Text(widget.word),
        ),
      ),
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Single word view — word + lemma + POS, top-3 Persian + more, ranked WSD
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _SingleWordView extends StatelessWidget {
  final SpanModel span;
  final Function(String word) onWordTap;
  const _SingleWordView({required this.span, required this.onWordTap});

  @override
  Widget build(BuildContext context) {
    final translations = <String>[
      if (span.primaryTranslationFa != null && span.primaryTranslationFa!.isNotEmpty)
        span.primaryTranslationFa!,
      if (span.secondaryTranslationFa != null && span.secondaryTranslationFa!.isNotEmpty)
        span.secondaryTranslationFa!,
      if (span.tertiaryTranslationFa != null && span.tertiaryTranslationFa!.isNotEmpty)
        span.tertiaryTranslationFa!,
      ...span.otherTranslationFa.where((t) => t.isNotEmpty),
    ];

    final note = span.inflectionNote;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header: word + lemma + POS + thunder ──────────────────────
        _WordHeaderRow(
          title: span.text,
          lemma: span.lemma,
          pos: span.pos,
        ),

        if (note != null && note.isNotEmpty) ...[
          const SizedBox(height: 10),
          _InflectionBadge(
            inflectionNote: note,
            onWordTap: onWordTap,
          ),
        ],

        const SizedBox(height: 12),
        const Divider(color: Color(0xFF2C2C35), height: 1),
        const SizedBox(height: 12),

        // ── Persian translations (top 3 + more) ───────────────────────
        if (translations.isNotEmpty) ...[
          const _SectionLabel('Persian'),
          const SizedBox(height: 6),
          _TranslationsRow(translations: translations),
          const SizedBox(height: 12),
        ],

        // ── Ranked WSD meanings ───────────────────────────────────────
        if (span.wsd.isNotEmpty) ...[
          const _SectionLabel('Word Senses'),
          const SizedBox(height: 8),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final sense in span.wsd) ...[
                    _WsdSenseTile(sense: sense, onWordTap: onWordTap),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Inflection Note Badge
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _InflectionBadge extends StatelessWidget {
  final String inflectionNote;
  final Function(String word)? onWordTap;

  const _InflectionBadge({
    required this.inflectionNote,
    this.onWordTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF231C14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFF9900).withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.subdirectory_arrow_right_rounded,
            size: 16,
            color: Color(0xFFFF9900),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: onWordTap != null
                ? InteractiveDefinitionText(
                    text: inflectionNote,
                    baseStyle: const TextStyle(
                      color: Color(0xFFFFC107),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      height: 1.3,
                    ),
                    onWordTap: onWordTap!,
                  )
                : Text(
                    inflectionNote,
                    style: const TextStyle(
                      color: Color(0xFFFFC107),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      height: 1.3,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Hierarchy view — tab bar with phrase + word chips
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _HierarchyCarousel extends StatefulWidget {
  final SpanModel span;
  final Function(String word) onWordTap;
  const _HierarchyCarousel({required this.span, required this.onWordTap});

  @override
  State<_HierarchyCarousel> createState() => _HierarchyCarouselState();
}

class _HierarchyCarouselState extends State<_HierarchyCarousel> {
  int _selectedTab = 0;

  @override
  Widget build(BuildContext context) {
    final span = widget.span;
    final meaning = span.parentMeaning;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header: phrase + category badge + thunder ─────────────────
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                span.text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ],
        ),

        // ── Canonical form ────────────────────────────────────────────
        if (span.canonicalForm != null &&
            span.canonicalForm!.isNotEmpty &&
            span.canonicalForm != span.text) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Consumer(
                builder: (context, ref, child) {
                  final isPersian = ref.watch(appLanguageProvider) == 'fa';
                  return Text(
                    isPersian ? 'شکل ریشه: ' : 'Canonical: ',
                    style: const TextStyle(
                      color: Color(0xFF8A8A93),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  );
                },
              ),
              Text(
                span.canonicalForm!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],

        const SizedBox(height: 12),
        const Divider(color: Color(0xFF2C2C35), height: 1),
        const SizedBox(height: 10),

        // ── Tab bar: phrase chip + each child word chip ───────────────
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              // Tab 0: the idiom phrase itself
              _TabChip(
                label: span.text,
                isSelected: _selectedTab == 0,
                onTap: () => setState(() => _selectedTab = 0),
              ),
              const SizedBox(width: 6),
              // Tabs 1..N: each child word
              for (int i = 0; i < span.childrenSubTokens.length; i++)
                _TabChip(
                  label: span.childrenSubTokens[i].token,
                  isSelected: _selectedTab == i + 1,
                  onTap: () => setState(() => _selectedTab = i + 1),
                ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // ── Content for selected tab (scrollable) ─────────────────────
        Flexible(
          child: SingleChildScrollView(
            child: _selectedTab == 0
                ? _buildParentContent(span, meaning)
                : _buildChildContent(span.childrenSubTokens[_selectedTab - 1]),
          ),
        ),
      ],
    );
  }

  Widget _buildParentContent(SpanModel span, ParentMeaning? meaning) {
    final parentTranslations = <String>[
      if (meaning?.primaryTranslationFa != null &&
          meaning!.primaryTranslationFa!.isNotEmpty)
        meaning.primaryTranslationFa!,
      if (meaning?.secondaryTranslationFa != null &&
          meaning!.secondaryTranslationFa!.isNotEmpty)
        meaning.secondaryTranslationFa!,
      if (meaning?.tertiaryTranslationFa != null &&
          meaning!.tertiaryTranslationFa!.isNotEmpty)
        meaning.tertiaryTranslationFa!,
      ...?meaning?.otherTranslationFa.where((t) => t.isNotEmpty),
    ];

    final note = meaning?.inflectionNote ?? span.inflectionNote;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Inflection note badge ──────────────────────────────────────
        if (note != null && note.isNotEmpty) ...[
          _InflectionBadge(
            inflectionNote: note,
            onWordTap: widget.onWordTap,
          ),
        ],

        // ── English definition ────────────────────────────────────────
        if (meaning?.definitionEn != null &&
            meaning!.definitionEn!.isNotEmpty) ...[
          const _SectionLabel('English'),
          const SizedBox(height: 4),
          InteractiveDefinitionText(
            text: meaning.definitionEn!,
            baseStyle: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              height: 1.5,
            ),
            onWordTap: widget.onWordTap,
          ),
          const SizedBox(height: 12),
        ],

        // ── Persian translations (top 3 + more) ──────────────────────
        if (parentTranslations.isNotEmpty) ...[
          const _SectionLabel('Persian'),
          const SizedBox(height: 6),
          _TranslationsRow(translations: parentTranslations),
        ],
      ],
    );
  }

  Widget _buildChildContent(ChildSubToken child) {
    final childTranslations = <String>[
      if (child.primaryTranslationFa != null &&
          child.primaryTranslationFa!.isNotEmpty)
        child.primaryTranslationFa!,
      if (child.secondaryTranslationFa != null &&
          child.secondaryTranslationFa!.isNotEmpty)
        child.secondaryTranslationFa!,
      if (child.tertiaryTranslationFa != null &&
          child.tertiaryTranslationFa!.isNotEmpty)
        child.tertiaryTranslationFa!,
      ...child.otherTranslationFa.where((t) => t.isNotEmpty),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header: word + lemma + POS ──────────────────────────────
        _WordHeaderRow(
          title: child.token,
          lemma: child.lemma,
          pos: child.pos,
        ),

        const SizedBox(height: 10),
        const Divider(color: Color(0xFF2C2C35), height: 1),
        const SizedBox(height: 10),

        // ── Persian translations (top 3 + more) ─────────────────────
        if (childTranslations.isNotEmpty) ...[
          const _SectionLabel('Persian'),
          const SizedBox(height: 6),
          _TranslationsRow(translations: childTranslations),
          const SizedBox(height: 10),
        ],

        // ── Ranked WSD meanings ─────────────────────────────────────
        if (child.wsd.isNotEmpty) ...[
          const _SectionLabel('Word Senses'),
          const SizedBox(height: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final sense in child.wsd) ...[
                _WsdSenseTile(sense: sense, onWordTap: widget.onWordTap),
                const SizedBox(height: 6),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

/// A selectable chip for switching between phrase and word tabs.
class _TabChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _TabChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFFF5500).withOpacity(0.15)
              : const Color(0xFF1E1E24),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFFF5500).withOpacity(0.5)
                : const Color(0xFF2C2C35),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? const Color(0xFFFF5500) : const Color(0xFF9E9D9F),
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Shared building blocks
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Header row: word title + lemma (italic) + POS badge + thunder button.
class _WordHeaderRow extends StatelessWidget {
  final String title;
  final String? lemma;
  final String? pos;

  const _WordHeaderRow({
    required this.title,
    this.lemma,
    this.pos,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              // Word text
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
              // Lemma of the word
              if (lemma != null && lemma!.isNotEmpty) ...[
                Text(
                  lemma!,
                  style: const TextStyle(
                    color: Color(0xFF8A8A93),
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
              // POS badge
              if (pos != null && pos!.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF5500).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: const Color(0xFFFF5500).withOpacity(0.4),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    pos!,
                    style: const TextStyle(
                      color: Color(0xFFFF5500),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Category badge (e.g. IDIOM, PHRASAL_VERB).
class _CategoryBadge extends StatelessWidget {
  final String label;
  const _CategoryBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFFF5500).withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: const Color(0xFFFF5500).withOpacity(0.4),
          width: 1,
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFFFF5500),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Small uppercase section label (Persian / English / Word Senses).
class _SectionLabel extends ConsumerWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPersian = ref.watch(appLanguageProvider) == 'fa';
    String displayLabel = label;
    if (isPersian) {
      if (label == 'Persian') displayLabel = 'ترجمه فارسی';
      if (label == 'English') displayLabel = 'تعریف انگلیسی';
      if (label == 'Word Senses') displayLabel = 'معانی کاربردی';
    }

    return Text(
      displayLabel,
      style: const TextStyle(
        color: Color(0xFF8A8A93),
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    );
  }
}

/// Persian translations rendered as spoiler chips: the first 3 are shown and
/// the remaining entries are revealed via the built-in "+N more" expander.
class _TranslationsRow extends StatelessWidget {
  final List<String> translations;
  const _TranslationsRow({required this.translations});

  @override
  Widget build(BuildContext context) {
    if (translations.isEmpty) return const SizedBox.shrink();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Align(
        alignment: Alignment.centerRight,
        child: SpoilerTranslationWidget(
          rawTranslation: translations.join(', '),
          initialMaxItems: 3,
        ),
      ),
    );
  }
}



// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  WSD sense tile — rank + definition_en + very small translation_fa
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _WsdSenseTile extends StatelessWidget {
  final WsdSense sense;
  final Function(String word) onWordTap;
  const _WsdSenseTile({required this.sense, required this.onWordTap});

  @override
  Widget build(BuildContext context) {
    final note = sense.inflectionNote;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E24),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF2C2C35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (note != null && note.isNotEmpty) ...[
            _InflectionBadge(
              inflectionNote: note,
              onWordTap: onWordTap,
            ),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${sense.rank}. ',
                style: const TextStyle(
                  color: Color(0xFFFF5500),
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Expanded(
                child: InteractiveDefinitionText(
                  text: sense.definitionEn,
                  onWordTap: onWordTap,
                ),
              ),
            ],
          ),
          if (sense.translationFa != null && sense.translationFa!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 14),
              child: Text(
                sense.translationFa!,
                style: const TextStyle(
                  color: Color(0xFF8A8A93),
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
