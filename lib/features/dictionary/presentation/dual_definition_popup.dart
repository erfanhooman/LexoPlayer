import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';

import 'package:lexo_player/core/models/dictionary_result.dart';
import 'package:lexo_player/core/theme/app_colors.dart';
import 'package:lexo_player/features/dictionary/data/dictionary_providers.dart';
import 'package:lexo_player/features/dictionary/presentation/spoiler_translation_widget.dart';

/// Desktop overlay for displaying dual-tier dictionary definitions.
///
/// Uses [CompositedTransformFollower] to position the popup relative to the
/// tapped/hovered word token. Includes programmatic boundary guards that
/// shift the popup inward when the source word is near a screen edge.
class DualDefinitionPopup extends ConsumerStatefulWidget {
  const DualDefinitionPopup({super.key});

  @override
  ConsumerState<DualDefinitionPopup> createState() =>
      _DualDefinitionPopupState();
}

class _DualDefinitionPopupState extends ConsumerState<DualDefinitionPopup> {
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
    // On mobile or narrow windows, we use a bottom sheet instead.
    if (Platform.isAndroid ||
        Platform.isIOS ||
        MediaQuery.of(context).size.width < 600) {
      return _MobileLookupListener();
    }

    // Desktop: watch for lookup results and display overlay.
    ref.listen<AsyncValue<List<DictionaryResult>>>(lookupResultProvider,
        (prev, next) {
      next.whenData((results) {
        _removeOverlay();
        if (results.isEmpty || results.every((r) => r.isEmpty)) return;

        final layerLink = ref.read(selectedTokenLayerLinkProvider);
        final tokenContext = ref.read(selectedTokenContextProvider);
        if (layerLink == null) return;

        _overlayEntry = _buildOverlayEntry(
          context: context,
          results: results,
          layerLink: layerLink,
          tokenContext: tokenContext,
        );
        Overlay.of(context).insert(_overlayEntry!);
      });
    });

    // This widget itself renders nothing; the overlay is inserted above.
    return const SizedBox.shrink();
  }

  OverlayEntry _buildOverlayEntry({
    required BuildContext context,
    required List<DictionaryResult> results,
    required LayerLink layerLink,
    required BuildContext? tokenContext,
  }) {
    return OverlayEntry(
      builder: (overlayContext) {
        final screenSize = MediaQuery.of(context).size;
        final popupWidth =
            (screenSize.width - 16).clamp(0.0, 450.0).toDouble();

        var targetAnchor = Alignment.topCenter;
        var followerAnchor = Alignment.bottomCenter;
        var targetOffset = const Offset(0, -12);
        var showBelow = false;
        var dx = 0.0;

        if (tokenContext != null && tokenContext.mounted) {
          final renderBox = tokenContext.findRenderObject() as RenderBox?;
          if (renderBox != null && renderBox.attached) {
            final wordPos = renderBox.localToGlobal(Offset.zero);
            final wordSize = renderBox.size;

            // If word is closer to the top of screen than 240px, show below.
            if (wordPos.dy < 240) {
              showBelow = true;
              targetAnchor = Alignment.bottomCenter;
              followerAnchor = Alignment.topCenter;
            }

            final wordCenter = wordPos.dx + wordSize.width / 2;
            final popupLeft = wordCenter - popupWidth / 2;
            final popupRight = popupLeft + popupWidth;

            if (popupLeft < 8) {
              dx = 8 - popupLeft;
            } else if (popupRight > screenSize.width - 8) {
              dx = screenSize.width - 8 - popupRight;
            }

            targetOffset = Offset(dx, showBelow ? 12 : -12);
          }
        }

        KeyEventResult handleEsc(FocusNode node, KeyEvent event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            _removeOverlay();
            ref.read(selectedTokenProvider.notifier).state = null;
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        }

        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            _removeOverlay();
            ref.read(selectedTokenProvider.notifier).state = null;
          },
          child: SizedBox.expand(
            child: Stack(
              children: [
                CompositedTransformFollower(
                  link: layerLink,
                  targetAnchor: targetAnchor,
                  followerAnchor: followerAnchor,
                  offset: targetOffset,
                  showWhenUnlinked: false,
                  child: Focus(
                    autofocus: true,
                    onKeyEvent: handleEsc,
                    child: MouseRegion(
                      onEnter: (_) => ref
                          .read(hoverPlaybackTimerProvider)
                          .onPopupHoverEnter(),
                      onExit: (_) => ref
                          .read(hoverPlaybackTimerProvider)
                          .onPopupHoverExit(),
                      child: Material(
                        color: Colors.transparent,
                        child: _DefinitionCard(
                          results: results,
                          popupWidth: popupWidth,
                          caretDx: -dx,
                          showBelow: showBelow,
                        ),
                      ),
                    ),
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

class _MobileLookupListener extends ConsumerStatefulWidget {
  @override
  ConsumerState<_MobileLookupListener> createState() =>
      _MobileLookupListenerState();
}

class _MobileLookupListenerState
    extends ConsumerState<_MobileLookupListener> {
  bool _sheetOpen = false;

  @override
  Widget build(BuildContext context) {
    // Toggle-off / explicit close: dismiss an open sheet without forcing play.
    ref.listen<SelectedTokenData?>(selectedTokenProvider, (prev, next) {
      if (!mounted) return;
      if (next == null && _sheetOpen) {
        _sheetOpen = false;
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      }
    });

    ref.listen<AsyncValue<List<DictionaryResult>>>(lookupResultProvider,
        (prev, next) {
      next.whenData((results) {
        if (!mounted) return;
        if (results.isEmpty || results.every((r) => r.isEmpty)) return;
        if (_sheetOpen) return;
        _showMobileBottomSheet(context, ref, results);
      });
    });
    return const SizedBox.shrink();
  }

  void _showMobileBottomSheet(
    BuildContext context,
    WidgetRef ref,
    List<DictionaryResult> results,
  ) {
    _sheetOpen = true;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return _MobileBottomSheetContent(results: results);
      },
    ).whenComplete(() {
      _sheetOpen = false;
      if (!mounted) return;
      try {
        // Resumes only if playback was active before the tap/hover.
        ref.read(hoverPlaybackTimerProvider).closePopup();
      } catch (_) {
        // Provider disposed — ignore.
      }
    });
  }
}

class _MobileBottomSheetContent extends StatefulWidget {
  final List<DictionaryResult> results;
  const _MobileBottomSheetContent({required this.results});
  @override
  State<_MobileBottomSheetContent> createState() =>
      _MobileBottomSheetContentState();
}

class _MobileBottomSheetContentState extends State<_MobileBottomSheetContent> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0E0E10), // Midnight Charcoal
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
            // Drag handle
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
            if (widget.results.length > 1) ...[
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: List.generate(widget.results.length, (index) {
                    final isSelected = index == _selectedIndex;
                    final label = widget.results[index].word;
                    return Semantics(
                      button: true,
                      selected: isSelected,
                      label: 'Show definition for $label',
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () =>
                              setState(() => _selectedIndex = index),
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            constraints:
                                const BoxConstraints(minHeight: 44),
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.primary
                                      .withValues(alpha: 0.15)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color: isSelected
                                      ? AppColors.primary
                                      : const Color(0xFF2C2C35)),
                            ),
                            child: Text(
                              label,
                              style: TextStyle(
                                color: isSelected
                                    ? AppColors.primary
                                    : const Color(0xFF8A8A93),
                                fontSize: 13,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Flexible(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child:
                    _DefinitionContent(result: widget.results[_selectedIndex]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Shared definition card (desktop overlay)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _DefinitionCard extends StatefulWidget {
  final List<DictionaryResult> results;
  final double popupWidth;
  final double caretDx;
  final bool showBelow;
  const _DefinitionCard({
    required this.results,
    this.popupWidth = 450,
    this.caretDx = 0,
    this.showBelow = false,
  });
  @override
  State<_DefinitionCard> createState() => _DefinitionCardState();
}

class _DefinitionCardState extends State<_DefinitionCard> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final highContrast = mq.highContrast;
    final reduceMotion = mq.disableAnimations;
    final cardWidth = widget.popupWidth.clamp(0.0, 450.0).toDouble();
    final maxH = (mq.size.height * 0.7).clamp(200.0, 550.0).toDouble();
    final card = Container(
      width: cardWidth,
      constraints: BoxConstraints(maxHeight: maxH),
      decoration: BoxDecoration(
        color: highContrast
            ? const Color(0xFF141416)
            : const Color(0xE6141416), // 90% Midnight Charcoal
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: highContrast
                ? const Color(0xFF5A5A66)
                : const Color(0xFF2C2C35),
            width: 1.2),
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
          filter: ImageFilter.blur(
              sigmaX: highContrast ? 0.0 : 12.0,
              sigmaY: highContrast ? 0.0 : 12.0),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: FocusTraversalGroup(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.results.length > 1) ...[
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children:
                            List.generate(widget.results.length, (index) {
                          final isSelected = index == _selectedIndex;
                          final label = widget.results[index].word;
                          return Semantics(
                            button: true,
                            selected: isSelected,
                            label: 'Show definition for $label',
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () =>
                                    setState(() => _selectedIndex = index),
                                borderRadius: BorderRadius.circular(16),
                                child: AnimatedContainer(
                                  duration: Duration(
                                      milliseconds:
                                          reduceMotion ? 0 : 150),
                                  constraints: const BoxConstraints(
                                      minHeight: 32),
                                  margin:
                                      const EdgeInsets.only(right: 8),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? AppColors.primary
                                            .withValues(alpha: 0.15)
                                        : Colors.transparent,
                                    borderRadius:
                                        BorderRadius.circular(16),
                                    border: Border.all(
                                      color: isSelected
                                          ? AppColors.primary
                                          : const Color(0xFF2C2C35),
                                    ),
                                  ),
                                  child: Text(
                                    label,
                                    style: TextStyle(
                                      color: isSelected
                                          ? AppColors.primary
                                          : const Color(0xFF8A8A93),
                                      fontSize: 13,
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Flexible(
                  child: _DefinitionContent(
                      result: widget.results[_selectedIndex]),
                ),
              ],
            ),
            ),
          ),
        ),
      ),
    );

    final cardColor = highContrast
        ? const Color(0xFF141416)
        : const Color(0xE6141416);
    final borderColor = highContrast
        ? const Color(0xFF5A5A66)
        : const Color(0xFF2C2C35);
    final caretLeft =
        (cardWidth / 2 + widget.caretDx - 6).clamp(12.0, cardWidth - 24.0).toDouble();
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          card,
          Positioned(
            left: caretLeft,
            top: widget.showBelow ? -6 : null,
            bottom: widget.showBelow ? null : -6,
            child: IgnorePointer(
              child: Transform.rotate(
                angle: 0.7853982,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: cardColor,
                    border: Border(
                      left: BorderSide(color: borderColor, width: 1.2),
                      top: BorderSide(color: borderColor, width: 1.2),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Definition content layout (shared between desktop & mobile)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class StructuredDefinition {
  final String? partOfSpeech;
  final List<StructuredMeaning> definitions;

  StructuredDefinition({
    this.partOfSpeech,
    required this.definitions,
  });

  factory StructuredDefinition.fromJson(Map<String, dynamic> json) {
    final defsJson = json['definitions'] as List<dynamic>? ?? [];
    final meanings = <StructuredMeaning>[];
    for (final d in defsJson) {
      if (d is Map<String, dynamic>) {
        meanings.add(StructuredMeaning.fromJson(d));
      }
    }
    return StructuredDefinition(
      partOfSpeech: json['part_of_speech']?.toString(),
      definitions: meanings,
    );
  }
}

class StructuredMeaning {
  final String meaning;
  final String? translation;
  final String? example;

  StructuredMeaning({
    required this.meaning,
    this.translation,
    this.example,
  });

  factory StructuredMeaning.fromJson(Map<String, dynamic> json) {
    return StructuredMeaning(
      meaning: json['meaning']?.toString() ?? '',
      translation: json['translation']?.toString(),
      example: json['example']?.toString(),
    );
  }
}

class _DefinitionContent extends StatelessWidget {
  final DictionaryResult result;
  const _DefinitionContent({required this.result});

  StructuredDefinition? _tryParseStructured(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return StructuredDefinition.fromJson(decoded);
      }
    } catch (_) {
      // Fall back to plain HTML
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final structured = result.htmlDefinition != null
        ? _tryParseStructured(result.htmlDefinition!)
        : null;

    if (structured != null) {
      return _buildStructuredLayout(context, structured);
    }
    return _buildLegacyLayout(context);
  }

  Widget _buildLegacyLayout(BuildContext context) {
    if (!result.hasDefinition) {
      return _buildHeader();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Header: word + translation ──────────────────────────────
        _buildHeader(),
        const SizedBox(height: 10),

        // ── Divider ─────────────────────────────────────────────────
        const Divider(color: Color(0xFF2C2C35), height: 1),
        const SizedBox(height: 12),

        // ── HTML definition body ────────────────────────────────────
        Flexible(
          child: SingleChildScrollView(
            child: HtmlWidget(
              result.htmlDefinition!,
              textStyle: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStructuredLayout(
    BuildContext context,
    StructuredDefinition structured,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 1. Main header line: Word [Translation on the right]
        // Locked to LTR so English stays left and Persian stays right
        // regardless of the app UI direction.
        Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                flex: 5,
                child: Semantics(
                  header: true,
                  label: 'Word: ${result.word}',
                  child: Text(
                    result.word,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              if (result.hasTranslation)
                Expanded(
                  flex: 6,
                  child: SpoilerTranslationWidget(
                    rawTranslation: result.localizedText!,
                    compactHeaderMode: true,
                    initialMaxItems: 3,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),

        // 2. Small part of speech label
        if (structured.partOfSpeech != null &&
            structured.partOfSpeech!.isNotEmpty) ...[
          Text(
            structured.partOfSpeech!,
            style: const TextStyle(
              color: Color(0xFF8A8A93), // Slate gray
              fontSize: 13,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
        ],

        const Divider(color: Color(0xFF2C2C35), height: 1),
        const SizedBox(height: 12),

        // 3. Definitions list
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (int i = 0; i < structured.definitions.length; i++) ...[
                  if (i > 0) const SizedBox(height: 16),
                  _buildDefinitionItem(structured.definitions[i], i + 1),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDefinitionItem(StructuredMeaning meaning, int index) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // English meaning text
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$index. ',
              style: const TextStyle(
                color: AppColors.primary, // Tangerine orange
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            Expanded(
              child: Text(
                meaning.meaning,
                style: const TextStyle(
                  color: Colors.white, // Crisp white
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),

        // Persian translation text
        if (meaning.translation != null && meaning.translation!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 14),
            child: SpoilerTranslationWidget(
              rawTranslation: meaning.translation!,
              initialMaxItems: 3,
            ),
          ),
        ],

        // Example sentence
        if (meaning.example != null && meaning.example!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 14),
            child: Text(
              'e.g. "${meaning.example}"',
              style: const TextStyle(
                color: Color(0xFF8A8A93), // Slate gray
                fontSize: 13,
                fontStyle: FontStyle.italic,
                height: 1.3,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildHeader() {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            flex: 5,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Semantics(
                    header: true,
                    label: 'Word: ${result.word}',
                    child: Text(
                      result.word,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                ),
                if (result.wasStemmed) ...[
                  const SizedBox(width: 8),
                  Semantics(
                    label: 'Stemmed form',
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.4),
                          width: 1,
                        ),
                      ),
                      child: const Text(
                        'stemmed',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (result.hasTranslation)
            Expanded(
              flex: 6,
              child: SpoilerTranslationWidget(
                rawTranslation: result.localizedText!,
                compactHeaderMode: true,
                initialMaxItems: 3,
              ),
            ),
        ],
      ),
    );
  }
}
