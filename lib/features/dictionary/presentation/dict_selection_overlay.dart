/// Overlay panel for selecting the active monolingual and bilingual
/// dictionaries.
///
/// Adapts its presentation to the platform: a centred dialog on desktop
/// and a draggable modal bottom sheet on mobile. Includes dropdown
/// selectors for each dictionary slot plus a shortcut to the download hub.
library;

import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';

import 'package:lexo_player/core/models/manifest_models.dart';
import 'package:lexo_player/features/dictionary/data/manifest_providers.dart';
import 'package:lexo_player/features/dictionary/data/dict_selection_providers.dart';
import 'package:lexo_player/features/dictionary/presentation/download_hub_screen.dart';

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Constants
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

const _kOverlayBg = Color(0xE6141418); // 90% Midnight Charcoal
const _kScaffoldBg = Color(0xFF0C0C0E); // Midnight Charcoal Scaffold
const _kBorder = Color(0xFF25252B); // Sleek dark border
const _kAccent = Color(0xFFFF5500); // Burnt Tangerine orange

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  DictSelectionOverlay
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Settings panel for choosing the active dictionaries.
///
/// Call [DictSelectionOverlay.show] to present it adaptively:
/// - **Desktop** (macOS / Windows / Linux): centred dialog
/// - **Mobile** (Android / iOS): modal bottom sheet
class DictSelectionOverlay extends ConsumerWidget {
  const DictSelectionOverlay({super.key});

  // ── Static entry point ─────────────────────────────────────────────────

  /// Presents the settings panel using the appropriate platform-native surface.
  static void show(BuildContext context) {
    final isMobile = Platform.isAndroid || Platform.isIOS;

    if (isMobile) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const _MobileSheetWrapper(
          child: DictSelectionOverlay(),
        ),
      );
    } else {
      showDialog(
        context: context,
        barrierColor: Colors.black54,
        builder: (_) => const Dialog(
          backgroundColor: Colors.transparent,
          insetPadding:
              EdgeInsets.symmetric(horizontal: 80, vertical: 60),
          child: DictSelectionOverlay(),
        ),
      );
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final monolingualList = ref.watch(availableMonolingualProvider);
    final bilingualList = ref.watch(availableBilingualProvider);

    final selectedMono = ref.watch(selectedMonolingualIdProvider);
    final selectedBi = ref.watch(selectedBilingualIdProvider);

    return Container(
      constraints: const BoxConstraints(maxWidth: 440),
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
                  children: [
                    const Icon(Icons.book_rounded, color: _kAccent, size: 22),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Dictionary Settings',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    // Close button.
                    IconButton(
                      icon: const Icon(Icons.close_rounded,
                          color: Colors.white38, size: 20),
                      onPressed: () => Navigator.of(context).pop(),
                      splashRadius: 18,
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Section 1: Definition Dictionary ───────────────────────
                        _DictDropdownSection(
                          label: 'Definition Dictionary',
                          hint: 'No dictionaries downloaded',
                          entries: monolingualList,
                          selectedId: selectedMono,
                          onChanged: (id) {
                            ref.read(selectedMonolingualIdProvider.notifier).state = id;
                            ref.read(dictStorageManagerProvider).setSelectedMonolingualId(id);
                          },
                        ),
                        const SizedBox(height: 14),

                        // ── Section 2: Translation Dictionary ─────────────────────
                        _DictDropdownSection(
                          label: 'Translation Dictionary',
                          hint: 'No dictionaries downloaded',
                          entries: bilingualList,
                          selectedId: selectedBi,
                          onChanged: (id) {
                            ref.read(selectedBilingualIdProvider.notifier).state = id;
                            ref.read(dictStorageManagerProvider).setSelectedBilingualId(id);
                          },
                        ),
                        const SizedBox(height: 16),

                        Divider(color: Colors.white.withOpacity(0.08), height: 1),
                        const SizedBox(height: 16),

                        // ── Buttons ────────────────────────────────────────────────
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextButton.icon(
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => const DownloadHubScreen(),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.download_rounded,
                                    size: 18, color: _kAccent),
                                label: const Text(
                                  'Go to Download Hub',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                style: TextButton.styleFrom(
                                  backgroundColor: _kAccent.withOpacity(0.15),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 24, vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    side: const BorderSide(color: _kAccent, width: 1.2),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextButton.icon(
                                onPressed: () => _importLocalDictionary(context, ref),
                                icon: const Icon(Icons.upload_file_rounded,
                                    size: 18, color: Colors.white70),
                                label: const Text(
                                  'Import Local Dictionary (.db)',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                style: TextButton.styleFrom(
                                  backgroundColor: Colors.white.withOpacity(0.05),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 24, vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    side: BorderSide(color: Colors.white.withOpacity(0.15), width: 1.2),
                                  ),
                                ),
                              ),
                            ],
                          ),
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

  Future<void> _importLocalDictionary(
      BuildContext context, WidgetRef ref) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['db'],
        dialogTitle: 'Select Dictionary Database File',
      );

      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        final name = result.files.single.name;
        final defaultName =
            name.endsWith('.db') ? name.substring(0, name.length - 3) : name;

        if (context.mounted) {
          _showImportDialog(context, ref, path, defaultName);
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error picking file: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _showImportDialog(
    BuildContext context,
    WidgetRef ref,
    String filePath,
    String defaultName,
  ) {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => _ImportDictDialog(
        filePath: filePath,
        defaultName: defaultName,
        onImportComplete: () async {
          // Re-fetch manual entries
          final storage = ref.read(dictStorageManagerProvider);
          final entries = await storage.getManualDictEntries();
          ref.read(manualDictEntriesProvider.notifier).state = entries;

          // Re-fetch downloaded IDs
          final ids = await storage.getDownloadedIds();
          ref.read(downloadedDictIdsProvider.notifier).state = ids;
        },
      ),
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Mobile bottom-sheet wrapper
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Wraps the overlay content in a mobile-friendly bottom sheet container
/// with a drag handle and rounded top corners.
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
          // Drag handle.
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
          // Re-use the overlay body but remove its own rounded container.
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: child,
          ),
        ],
      ),
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Dictionary dropdown section
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// A labelled dropdown selector for one dictionary slot.
class _DictDropdownSection extends StatelessWidget {
  final String label;
  final String hint;
  final List<DictionaryEntry> entries;
  final String? selectedId;
  final ValueChanged<String?> onChanged;

  const _DictDropdownSection({
    required this.label,
    required this.hint,
    required this.entries,
    required this.selectedId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isEmpty = entries.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label.
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 8),

        // Dropdown container.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: _kScaffoldBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isEmpty ? _kBorder : _kAccent.withOpacity(0.4),
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _resolveValue(),
              isExpanded: true,
              dropdownColor: _kOverlayBg,
              borderRadius: BorderRadius.circular(10),
              icon: Icon(
                Icons.keyboard_arrow_down_rounded,
                color: isEmpty ? Colors.white24 : Colors.white54,
              ),
              hint: Text(
                hint,
                style: const TextStyle(color: Colors.white30, fontSize: 14),
              ),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              onChanged: isEmpty ? null : onChanged,
              items: entries.map((entry) {
                return DropdownMenuItem<String>(
                  value: entry.id,
                  child: Row(
                    children: [
                      // Small language indicator dot.
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _kAccent.withOpacity(0.7),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          entry.displayName,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  /// Returns the selected ID only if it exists in the current entries list,
  /// avoiding "value not in items" errors when a previously selected
  /// dictionary is uninstalled.
  String? _resolveValue() {
    if (selectedId == null) return null;
    final exists = entries.any((e) => e.id == selectedId);
    return exists ? selectedId : null;
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Manual Import Dialog
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _ImportDictDialog extends ConsumerStatefulWidget {
  final String filePath;
  final String defaultName;
  final VoidCallback onImportComplete;

  const _ImportDictDialog({
    required this.filePath,
    required this.defaultName,
    required this.onImportComplete,
  });

  @override
  ConsumerState<_ImportDictDialog> createState() => _ImportDictDialogState();
}

class _ImportDictDialogState extends ConsumerState<_ImportDictDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _sourceLangController;
  late TextEditingController _nativeLangController;
  DictionaryType _type = DictionaryType.monolingual;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.defaultName);
    _sourceLangController = TextEditingController(text: 'en');
    _nativeLangController = TextEditingController(text: 'fa');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _sourceLangController.dispose();
    _nativeLangController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _importing = true);

    try {
      final storage = ref.read(dictStorageManagerProvider);
      final id = 'local_${DateTime.now().millisecondsSinceEpoch}';

      // Copy database file to dictionaries directory
      await storage.importLocalDbFile(widget.filePath, id);

      // Create manual entry
      final entry = DictionaryEntry(
        id: id,
        sourceLanguage: _sourceLangController.text.trim().toLowerCase(),
        nativeLanguage: _type == DictionaryType.bilingual
            ? _nativeLangController.text.trim().toLowerCase()
            : null,
        displayName: _nameController.text.trim(),
        description: 'Manually imported dictionary database.',
        remoteUrl: '',
        fileSizeBytes: File(widget.filePath).lengthSync(),
        md5Checksum: '',
        type: _type,
      );

      await storage.addManualDictEntry(entry);
      widget.onImportComplete();

      if (mounted) {
        Navigator.of(context).pop(); // Close dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Dictionary database imported successfully!'),
            backgroundColor: Colors.teal,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import failed: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _importing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _kOverlayBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        'Import Dictionary Database',
        style: TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Dictionary Display Name',
                  labelStyle: TextStyle(color: Colors.white70),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24),
                  ),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<DictionaryType>(
                value: _type,
                dropdownColor: _kOverlayBg,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Dictionary Type',
                  labelStyle: TextStyle(color: Colors.white70),
                ),
                items: const [
                  DropdownMenuItem(
                    value: DictionaryType.monolingual,
                    child: Text('Monolingual (Definition)'),
                  ),
                  DropdownMenuItem(
                    value: DictionaryType.bilingual,
                    child: Text('Bilingual (Translation)'),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _type = v);
                  }
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _sourceLangController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Source Language Code (e.g. en)',
                  labelStyle: TextStyle(color: Colors.white70),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24),
                  ),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              if (_type == DictionaryType.bilingual) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nativeLangController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Native Language Code (e.g. fa)',
                    labelStyle: TextStyle(color: Colors.white70),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24),
                    ),
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Required' : null,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _importing ? null : () => Navigator.of(context).pop(),
          child: const Text(
            'Cancel',
            style: TextStyle(color: Colors.white54),
          ),
        ),
        ElevatedButton(
          onPressed: _importing ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: _kAccent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: _importing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text(
                  'Import',
                  style: TextStyle(color: Colors.white),
                ),
        ),
      ],
    );
  }
}
