
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';

import 'package:lexo_player/core/models/dictionary_result.dart';
import 'package:lexo_player/features/dictionary/data/dictionary_providers.dart';
import 'package:lexo_player/features/video_player/providers/player_provider.dart';

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
    // On mobile, we use a bottom sheet instead (see MobileBottomSheet).
    if (Platform.isAndroid || Platform.isIOS) {
      return _MobileLookupListener();
    }

    // Desktop: watch for lookup results and display overlay.
    ref.listen<AsyncValue<DictionaryResult?>>(lookupResultProvider,
        (prev, next) {
      next.whenData((result) {
        _removeOverlay();
        if (result == null || result.isEmpty) return;

        final layerLink = ref.read(selectedTokenLayerLinkProvider);
        final tokenContext = ref.read(selectedTokenContextProvider);
        if (layerLink == null) return;

        _overlayEntry = _buildOverlayEntry(
          context: context,
          result: result,
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
    required DictionaryResult result,
    required LayerLink layerLink,
    required BuildContext? tokenContext,
  }) {
    return OverlayEntry(
      builder: (overlayContext) {
        final screenSize = MediaQuery.of(context).size;
        const popupWidth = 360.0;

        var targetAnchor = Alignment.topCenter;
        var followerAnchor = Alignment.bottomCenter;
        var targetOffset = const Offset(0, -8);
        var showBelow = false;

        if (tokenContext != null && tokenContext.mounted) {
          final renderBox = tokenContext.findRenderObject() as RenderBox?;
          if (renderBox != null && renderBox.attached) {
            final wordPos = renderBox.localToGlobal(Offset.zero);
            final wordSize = renderBox.size;

            // If word is closer to the top of screen than 220px, show below.
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
                  child: MouseRegion(
                    onEnter: (_) => ref
                        .read(hoverPlaybackTimerProvider)
                        .onPopupHoverEnter(),
                    onExit: (_) =>
                        ref.read(hoverPlaybackTimerProvider).onPopupHoverExit(),
                    child: Material(
                      color: Colors.transparent,
                      child: _DefinitionCard(result: result),
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

class _MobileLookupListener extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<AsyncValue<DictionaryResult?>>(lookupResultProvider,
        (prev, next) {
      next.whenData((result) {
        if (result == null || result.isEmpty) return;
        _showMobileBottomSheet(context, ref, result);
      });
    });
    return const SizedBox.shrink();
  }

  void _showMobileBottomSheet(
    BuildContext context,
    WidgetRef ref,
    DictionaryResult result,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return FractionallySizedBox(
          heightFactor: 0.45,
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
              children: [
                // Drag handle
                Padding(
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
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _DefinitionContent(result: result),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ).whenComplete(() {
      // Resume playback when the bottom sheet is dismissed.
      final player = ref.read(playerProvider);
      player.play();
      ref.read(selectedTokenProvider.notifier).state = null;
    });
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Shared definition card (desktop overlay)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _DefinitionCard extends StatelessWidget {
  final DictionaryResult result;
  const _DefinitionCard({required this.result});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 360,
      constraints: const BoxConstraints(maxHeight: 400),
      decoration: BoxDecoration(
        color: const Color(0xE6141416), // 90% Midnight Charcoal
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
            child: _DefinitionContent(result: result),
          ),
        ),
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
        if (result.hasDefinition)
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
          )
        else
          const Text(
            'No definition available.',
            style: TextStyle(
              color: Color(0xFF8A8A93),
              fontSize: 14,
              fontStyle: FontStyle.italic,
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
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              result.word,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
            ),
            const Spacer(),
            if (result.hasTranslation)
              Flexible(
                child: Directionality(
                  textDirection: _isRtl(result.localizedText!)
                      ? TextDirection.rtl
                      : TextDirection.ltr,
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 48),
                    child: SingleChildScrollView(
                      child: Text(
                        result.localizedText!,
                        style: const TextStyle(
                          color: Color(0xFFFF5500), // Tangerine orange
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.end,
                      ),
                    ),
                  ),
                ),
              ),
          ],
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
                color: Color(0xFFFF5500), // Tangerine orange
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
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: SizedBox(
                width: double.infinity,
                child: Text(
                  meaning.translation!,
                  style: const TextStyle(
                    color: Color(0xFFE4E4E7), // Lighter white-gray
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                  ),
                ),
              ),
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Flexible(
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
        if (result.wasStemmed) ...[
          const SizedBox(width: 8),
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
            child: const Text(
              'stemmed',
              style: TextStyle(
                color: Color(0xFFFF5500),
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
        const Spacer(),
        if (result.hasTranslation)
          Flexible(
            child: Directionality(
              textDirection: _isRtl(result.localizedText!)
                  ? TextDirection.rtl
                  : TextDirection.ltr,
              child: Container(
                constraints: const BoxConstraints(maxHeight: 48),
                child: SingleChildScrollView(
                  child: Text(
                    result.localizedText!,
                    style: const TextStyle(
                      color: Color(0xFFFF5500), // Tangerine orange
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.end,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  static bool _isRtl(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    final firstChar = trimmed.codeUnitAt(0);
    return (firstChar >= 0x0590 && firstChar <= 0x05FF) || // Hebrew
        (firstChar >= 0x0600 && firstChar <= 0x06FF) || // Arabic
        (firstChar >= 0x0750 && firstChar <= 0x077F) || // Arabic Ext
        (firstChar >= 0xFB50 && firstChar <= 0xFDFF) || // Arabic Pres A
        (firstChar >= 0xFE70 && firstChar <= 0xFEFF); // Arabic Pres B
  }
}
