import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexo_player/features/subtitles/providers/subtitle_providers.dart';

const _kOverlayBg = Color(0xE6141418); // 90% Midnight Charcoal
const _kScaffoldBg = Color(0xFF0C0C0E); // Midnight Charcoal Scaffold
const _kBorder = Color(0xFF25252B); // Sleek card border
const _kAccent = Color(0xFFFF5500); // Burnt Tangerine orange

/// Settings panel specifically for configuring subtitle styling.
///
/// Call [SubtitleSettingsOverlay.show] to present it adaptively:
/// - **Desktop** (macOS / Windows / Linux): centred dialog
/// - **Mobile** (Android / iOS): modal bottom sheet
class SubtitleSettingsOverlay extends ConsumerWidget {
  const SubtitleSettingsOverlay({super.key});

  /// Presents the subtitle settings panel.
  static void show(BuildContext context) {
    final isMobile = Platform.isAndroid || Platform.isIOS;

    if (isMobile) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _MobileSheetWrapper(
          child: const SubtitleSettingsOverlay(),
        ),
      );
    } else {
      showDialog(
        context: context,
        barrierColor: Colors.black54,
        builder: (_) => const Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.symmetric(horizontal: 80, vertical: 60),
          child: SubtitleSettingsOverlay(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rawSize = ref.watch(subtitleSizeProvider);
    final rawColor = ref.watch(subtitleColorProvider);
    final rawBgColor = ref.watch(subtitleBgColorProvider);
    final rawOutline = ref.watch(subtitleOutlineWidthProvider);
    final rawFont = ref.watch(subtitleFontFamilyProvider);

    // Validate and fall back to default options to prevent legacy storage assertion errors.
    final currentSize = const [16.0, 22.0, 28.0, 34.0].contains(rawSize) ? rawSize : 22.0;
    final currentColor = const [0xFFFFFFFF, 0xFFFFF176, 0xFF00E5FF, 0xFF69F0AE, 0xFFFF5500].contains(rawColor) ? rawColor : 0xFFFFFFFF;
    final currentBgColor = const [0x00000000, 0x40000000, 0x99000000, 0xD9000000, 0xFF000000].contains(rawBgColor) ? rawBgColor : 0xD9000000;
    final currentOutline = const [0.0, 0.6, 1.2, 2.2].contains(rawOutline) ? rawOutline : 1.2;
    final currentFont = const ['System', 'Georgia', 'Times New Roman', 'Menlo', 'Courier New', 'Helvetica Neue', 'Avenir'].contains(rawFont) ? rawFont : 'System';

    return Container(
      constraints: const BoxConstraints(maxWidth: 400),
      decoration: BoxDecoration(
        color: _kOverlayBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder, width: 1.2),
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
          filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Title row ──────────────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Subtitle Settings',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                      onPressed: () => Navigator.of(context).pop(),
                      splashRadius: 20,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Font Size
                        _buildSettingDropdown<double>(
                          label: 'Text Size',
                          value: currentSize,
                          items: const [
                            DropdownMenuItem(value: 16.0, child: Text('Small')),
                            DropdownMenuItem(value: 22.0, child: Text('Medium')),
                            DropdownMenuItem(value: 28.0, child: Text('Large')),
                            DropdownMenuItem(value: 34.0, child: Text('Extra Large')),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              ref.read(subtitleSizeProvider.notifier).state = val;
                              saveSubtitleSize(val);
                            }
                          },
                        ),
                        const SizedBox(height: 12),

                        // Text Color
                        _buildSettingDropdown<int>(
                          label: 'Text Color',
                          value: currentColor,
                          items: const [
                            DropdownMenuItem(value: 0xFFFFFFFF, child: Text('White')),
                            DropdownMenuItem(value: 0xFFFFF176, child: Text('Yellow')),
                            DropdownMenuItem(value: 0xFF00E5FF, child: Text('Cyan')),
                            DropdownMenuItem(value: 0xFF69F0AE, child: Text('Green')),
                            DropdownMenuItem(value: 0xFFFF5500, child: Text('Tangerine')),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              ref.read(subtitleColorProvider.notifier).state = val;
                              saveSubtitleColor(val);
                            }
                          },
                        ),
                        const SizedBox(height: 12),

                    // Background
                    _buildSettingDropdown<int>(
                      label: 'Background Style',
                      value: currentBgColor,
                      items: const [
                        DropdownMenuItem(value: 0x00000000, child: Text('None (Transparent)')),
                        DropdownMenuItem(value: 0x40000000, child: Text('Translucent')),
                        DropdownMenuItem(value: 0x99000000, child: Text('Semi-transparent')),
                        DropdownMenuItem(value: 0xD9000000, child: Text('Dark')),
                        DropdownMenuItem(value: 0xFF000000, child: Text('Solid (Black)')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          ref.read(subtitleBgColorProvider.notifier).state = val;
                          saveSubtitleBgColor(val);
                        }
                      },
                    ),
                    const SizedBox(height: 12),

                    // Outline
                    _buildSettingDropdown<double>(
                      label: 'Outline Thickness',
                      value: currentOutline,
                      items: const [
                        DropdownMenuItem(value: 0.0, child: Text('None')),
                        DropdownMenuItem(value: 0.6, child: Text('Thin')),
                        DropdownMenuItem(value: 1.2, child: Text('Medium')),
                        DropdownMenuItem(value: 2.2, child: Text('Thick')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          ref.read(subtitleOutlineWidthProvider.notifier).state = val;
                          saveSubtitleOutlineWidth(val);
                        }
                      },
                    ),
                    const SizedBox(height: 12),

                    // Font Family
                    _buildSettingDropdown<String>(
                      label: 'Font Family',
                      value: currentFont,
                      items: const [
                        DropdownMenuItem(value: 'System', child: Text('System (Default)')),
                        DropdownMenuItem(value: 'Georgia', child: Text('Georgia (Serif)')),
                        DropdownMenuItem(value: 'Times New Roman', child: Text('Times New Roman (Serif)')),
                        DropdownMenuItem(value: 'Menlo', child: Text('Menlo (Monospace)')),
                        DropdownMenuItem(value: 'Courier New', child: Text('Courier New (Monospace)')),
                        DropdownMenuItem(value: 'Helvetica Neue', child: Text('Helvetica Neue (Sans-serif)')),
                        DropdownMenuItem(value: 'Avenir', child: Text('Avenir (Sans-serif)')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          ref.read(subtitleFontFamilyProvider.notifier).state = val;
                          saveSubtitleFontFamily(val);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
    ),
    );
  }

  Widget _buildSettingDropdown<T>({
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _kScaffoldBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _kBorder),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              dropdownColor: _kOverlayBg,
              borderRadius: BorderRadius.circular(8),
              icon: const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: _kAccent,
                size: 20,
              ),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              onChanged: onChanged,
              items: items,
            ),
          ),
        ),
      ],
    );
  }
}

class _MobileSheetWrapper extends StatelessWidget {
  final Widget child;

  const _MobileSheetWrapper({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: _kOverlayBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: child,
          ),
        ],
      ),
    );
  }
}
