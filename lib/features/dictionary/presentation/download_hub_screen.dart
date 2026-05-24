import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';

import 'package:lexo_player/core/models/manifest_models.dart';
import 'package:lexo_player/features/dictionary/data/manifest_providers.dart';
import 'package:lexo_player/features/dictionary/data/dict_selection_providers.dart';

class DownloadHubScreen extends ConsumerWidget {
  const DownloadHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header & Back Button ─────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back_rounded),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Dictionaries',
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        'LEXOPLAYER',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: theme.colorScheme.primary,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                ),
                
                // ── Main Content ─────────────────────────────────────────
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _SectionTitle('ACTIVE CONFIGURATION'),
                        const SizedBox(height: 16),
                        const _ActiveDictSelector(isMonolingual: true),
                        const SizedBox(height: 8),
                        const _ActiveDictSelector(isMonolingual: false),
                        const SizedBox(height: 24),
                        
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => _importLocalDict(context, ref),
                            icon: const Icon(Icons.unarchive_rounded),
                            label: const Text('Import Local Dictionary (.db)'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        
                        const SizedBox(height: 40),
                        Divider(color: theme.colorScheme.outlineVariant),
                        const SizedBox(height: 32),
                        
                        const _SectionTitle('DOWNLOAD HUB'),
                        const SizedBox(height: 20),
                        const _DownloadMarketplace(),
                        const SizedBox(height: 48),
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

  Future<void> _importLocalDict(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['db'],
      dialogTitle: 'Select Dictionary Database',
    );
    if (!context.mounted) return;
    if (result == null || result.files.single.path == null) return;

    final sourcePath = result.files.single.path!;
    final fileName = result.files.single.name.replaceAll('.db', '');
    final messenger = ScaffoldMessenger.of(context);

    try {
      final storage = ref.read(dictStorageManagerProvider);
      final storageManager = ref.read(dictStorageManagerProvider);

      await storage.importLocalDbFile(sourcePath, fileName);

      final entry = DictionaryEntry(
        id: fileName,
        sourceLanguage: 'en',
        nativeLanguage: null,
        displayName: fileName,
        description: 'Manually imported dictionary.',
        remoteUrl: '',
        fileSizeBytes: 0,
        md5Checksum: '',
        type: DictionaryType.monolingual,
      );

      await storageManager.addManualDictEntry(entry);

      final ids = await storage.getDownloadedIds();
      ref.read(downloadedDictIdsProvider.notifier).state = ids;

      final manualEntries = await storage.getManualDictEntries();
      ref.read(manualDictEntriesProvider.notifier).state = manualEntries;

      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Successfully imported "$fileName"'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Import failed: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      title,
      style: theme.textTheme.labelMedium?.copyWith(
        fontWeight: FontWeight.bold,
        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
        letterSpacing: 2,
      ),
    );
  }
}

class _ActiveDictSelector extends ConsumerWidget {
  final bool isMonolingual;
  const _ActiveDictSelector({required this.isMonolingual});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final available = isMonolingual
        ? ref.watch(availableMonolingualProvider)
        : ref.watch(availableBilingualProvider);
        
    final selectedId = isMonolingual
        ? ref.watch(selectedMonolingualIdProvider)
        : ref.watch(selectedBilingualIdProvider);

    final effectiveValue = (selectedId == null || !available.any((dict) => dict.id == selectedId))
        ? 'none'
        : selectedId;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant,
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isMonolingual ? Icons.translate_rounded : Icons.g_translate_rounded,
                  color: theme.colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isMonolingual ? 'Primary Definition Dictionary' : 'Secondary Translation Dictionary',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.colorScheme.outline),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: effectiveValue,
                  isExpanded: true,
                  dropdownColor: theme.colorScheme.surface,
                  icon: Icon(Icons.keyboard_arrow_down, color: theme.colorScheme.primary),
                  style: theme.textTheme.bodyLarge,
                  items: [
                    DropdownMenuItem(
                      value: 'none',
                      child: Text(
                        'None (Disabled)',
                        style: TextStyle(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
                      ),
                    ),
                    for (final dict in available)
                      DropdownMenuItem(
                        value: dict.id,
                        child: Text(dict.displayName),
                      ),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      if (isMonolingual) {
                        ref.read(selectedMonolingualIdProvider.notifier).state = val;
                      } else {
                        ref.read(selectedBilingualIdProvider.notifier).state = val;
                      }
                      saveSelections(ref);
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DownloadMarketplace extends ConsumerWidget {
  const _DownloadMarketplace();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manifestAsync = ref.watch(manifestDataProvider);
    final theme = Theme.of(context);

    return manifestAsync.when(
      loading: () => Center(child: CircularProgressIndicator(color: theme.colorScheme.primary)),
      error: (e, _) => Text('Error loading hub: $e', style: TextStyle(color: theme.colorScheme.error)),
      data: (manifest) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (manifest.monolingual.isNotEmpty) ...[
              Text(
                'Monolingual',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              for (final entry in manifest.monolingual) _MarketItem(entry: entry),
              const SizedBox(height: 32),
            ],
            if (manifest.bilingual.isNotEmpty) ...[
              Text(
                'Bilingual',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              for (final entry in manifest.bilingual) _MarketItem(entry: entry),
            ],
          ],
        );
      },
    );
  }
}

class _MarketItem extends ConsumerStatefulWidget {
  final DictionaryEntry entry;
  const _MarketItem({required this.entry});

  @override
  ConsumerState<_MarketItem> createState() => _MarketItemState();
}

class _MarketItemState extends ConsumerState<_MarketItem> {
  bool _isProcessing = false;

  Future<void> _handleDownload() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    final downloadService = ref.read(dictDownloadServiceProvider);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await downloadService.downloadDictionary(
        widget.entry,
        onProgress: (received, total) {
          final progress = total > 0 ? received / total : 0.0;
          ref.read(downloadProgressProvider.notifier).state = {
            ...ref.read(downloadProgressProvider),
            widget.entry.id: progress,
          };
        },
      );

      final ids = await ref.read(dictStorageManagerProvider).getDownloadedIds();
      ref.read(downloadedDictIdsProvider.notifier).state = ids;

      ref.read(downloadProgressProvider.notifier).state = Map<String, double>.from(
        ref.read(downloadProgressProvider),
      )..remove(widget.entry.id);

      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('"${widget.entry.displayName}" installed and ready to use'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      ref.read(downloadProgressProvider.notifier).state = Map<String, double>.from(
        ref.read(downloadProgressProvider),
      )..remove(widget.entry.id);

      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Download failed: ${e.toString().split('\n').first}'),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _handleDelete() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    final messenger = ScaffoldMessenger.of(context);

    try {
      await ref.read(dictDownloadServiceProvider).deleteDictionary(widget.entry.id);

      final ids = await ref.read(dictStorageManagerProvider).getDownloadedIds();
      ref.read(downloadedDictIdsProvider.notifier).state = ids;

      // Deselect if the deleted dictionary was active
      final monoId = ref.read(selectedMonolingualIdProvider);
      final biId = ref.read(selectedBilingualIdProvider);
      if (monoId == widget.entry.id) {
        ref.read(selectedMonolingualIdProvider.notifier).state = null;
        await ref.read(dictStorageManagerProvider).setSelectedMonolingualId(null);
      }
      if (biId == widget.entry.id) {
        ref.read(selectedBilingualIdProvider.notifier).state = null;
        await ref.read(dictStorageManagerProvider).setSelectedBilingualId(null);
      }
      saveSelections(ref);

      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('"${widget.entry.displayName}" removed'),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Delete failed: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    if (mounted) {
      setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final installedList = ref.watch(downloadedDictIdsProvider);
    final isInstalled = installedList.contains(widget.entry.id);

    final progressMap = ref.watch(downloadProgressProvider);
    final progress = progressMap[widget.entry.id];
    final isDownloading = progress != null;
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant,
          width: 1,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: theme.colorScheme.secondaryContainer,
          ),
          child: Icon(
            Icons.book_rounded,
            color: theme.colorScheme.onSecondaryContainer,
            size: 24,
          ),
        ),
        title: Text(
          widget.entry.displayName,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          widget.entry.description,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: SizedBox(
          width: isDownloading ? 100 : 110,
          child: _isProcessing && isDownloading
              ? _DownloadProgressBar(progress: progress)
              : isInstalled
                  ? Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _handleDelete,
                        icon: Icon(Icons.delete_outline_rounded, size: 16, color: theme.colorScheme.error),
                        label: Text(
                          'REMOVE',
                          style: TextStyle(
                            color: theme.colorScheme.error,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                            letterSpacing: 0.5,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          backgroundColor: theme.colorScheme.errorContainer.withValues(alpha: 0.1),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(
                              color: theme.colorScheme.error.withValues(alpha: 0.3),
                              width: 1,
                            ),
                          ),
                        ),
                      ),
                    )
                  : Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _handleDownload,
                        icon: Icon(Icons.file_download_outlined, size: 16, color: theme.colorScheme.primary),
                        label: Text(
                          'GET',
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                            letterSpacing: 0.5,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          backgroundColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.2),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(
                              color: theme.colorScheme.primary.withValues(alpha: 0.3),
                              width: 1,
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

class _DownloadProgressBar extends StatelessWidget {
  final double? progress;
  const _DownloadProgressBar({this.progress});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pct = (progress ?? 0.0) * 100;
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        LinearProgressIndicator(
          value: progress,
          minHeight: 4,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: 4),
        Text(
          '${pct.toStringAsFixed(0)}%',
          style: TextStyle(
            color: theme.colorScheme.primary,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }
}
