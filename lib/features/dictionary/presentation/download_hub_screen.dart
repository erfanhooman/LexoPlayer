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
    return Scaffold(
      backgroundColor: const Color(0xFF070709),
      body: Stack(
        children: [
          // ── Massive Watermark ──────────────────────────────────────────
          Positioned(
            right: -100,
            top: -50,
            child: const IgnorePointer(
              child: Text(
                'DICT',
                style: TextStyle(
                  fontSize: 400,
                  fontWeight: FontWeight.w900,
                  color: Color(0x05FFFFFF), // 2% opacity
                  height: 0.8,
                  letterSpacing: -20,
                  fontFamily: 'Helvetica Neue',
                ),
              ),
            ),
          ),
          
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header & Back Button ─────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(48, 64, 48, 24),
                  child: Row(
                    children: [
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () => Navigator.of(context).pop(),
                          child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 28),
                        ),
                      ),
                      const SizedBox(width: 32),
                      const Text(
                        'Dictionaries.',
                        style: TextStyle(
                          fontSize: 56,
                          fontWeight: FontWeight.w300,
                          color: Colors.white,
                          fontFamily: 'Georgia',
                          letterSpacing: -1,
                        ),
                      ),
                    ],
                  ),
                ),
                
                // ── Main Content ─────────────────────────────────────────
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 24),
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _SectionTitle('ACTIVE CONFIGURATION'),
                        const SizedBox(height: 24),
                        const _ActiveDictSelector(isMonolingual: true),
                        const SizedBox(height: 24),
                        const _ActiveDictSelector(isMonolingual: false),
                        const SizedBox(height: 48),
                        
                        MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: () => _importLocalDict(context, ref),
                            child: const Text(
                              '+ Import Local Dictionary .db',
                              style: TextStyle(
                                color: Color(0xFFFF5500),
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                                fontFamily: 'Helvetica Neue',
                              ),
                            ),
                          ),
                        ),
                        
                        const SizedBox(height: 80),
                        Container(height: 1, color: Colors.white10),
                        const SizedBox(height: 80),
                        
                        const _SectionTitle('DOWNLOAD HUB'),
                        const SizedBox(height: 24),
                        const _DownloadMarketplace(),
                        const SizedBox(height: 100),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _importLocalDict(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['db'],
      dialogTitle: 'Select Dictionary Database',
    );
    if (result != null && result.files.single.path != null) {
      // Stub implementation - needs actual local import logic which was in overlay
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Local import is currently handled via configuration')),
      );
    }
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.bold,
        color: Colors.white30,
        letterSpacing: 4,
        fontFamily: 'Helvetica Neue',
      ),
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Active Dict Selectors
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _ActiveDictSelector extends ConsumerWidget {
  final bool isMonolingual;
  const _ActiveDictSelector({required this.isMonolingual});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final available = isMonolingual
        ? ref.watch(availableMonolingualProvider)
        : ref.watch(availableBilingualProvider);
        
    final selectedId = isMonolingual
        ? ref.watch(selectedMonolingualIdProvider)
        : ref.watch(selectedBilingualIdProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isMonolingual ? 'Primary Definition Dictionary' : 'Secondary Translation Dictionary',
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 16,
            fontFamily: 'Georgia',
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: 400,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white10),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: selectedId,
              isExpanded: true,
              dropdownColor: const Color(0xFF16161A),
              icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFFFF5500)),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontFamily: 'Helvetica Neue',
                fontWeight: FontWeight.w500,
              ),
              items: [
                const DropdownMenuItem(
                  value: 'none',
                  child: Text('None (Disabled)', style: TextStyle(color: Colors.white54)),
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
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Marketplace
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _DownloadMarketplace extends ConsumerWidget {
  const _DownloadMarketplace();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manifestAsync = ref.watch(manifestDataProvider);

    return manifestAsync.when(
      loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFFFF5500))),
      error: (e, _) => Text('Error loading hub: $e', style: const TextStyle(color: Colors.red)),
      data: (manifest) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (manifest.monolingual.isNotEmpty) ...[
              const Text('Monolingual', style: TextStyle(fontSize: 24, fontFamily: 'Georgia', color: Colors.white)),
              const SizedBox(height: 16),
              for (final entry in manifest.monolingual) _MarketItem(entry: entry),
              const SizedBox(height: 32),
            ],
            if (manifest.bilingual.isNotEmpty) ...[
              const Text('Bilingual', style: TextStyle(fontSize: 24, fontFamily: 'Georgia', color: Colors.white)),
              const SizedBox(height: 16),
              for (final entry in manifest.bilingual) _MarketItem(entry: entry),
            ],
          ],
        );
      },
    );
  }
}

class _MarketItem extends ConsumerWidget {
  final DictionaryEntry entry;
  const _MarketItem({required this.entry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final installedList = ref.watch(downloadedDictIdsProvider);
    final isInstalled = installedList.contains(entry.id);
    
    final progressMap = ref.watch(downloadProgressProvider);
    final progress = progressMap[entry.id];
    final isDownloading = progress != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.displayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  entry.description,
                  style: const TextStyle(color: Colors.white54, fontSize: 14),
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          if (isDownloading)
            SizedBox(
              width: 100,
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.white10,
                color: const Color(0xFFFF5500),
              ),
            )
          else if (isInstalled)
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () async {
                  await ref.read(dictDownloadServiceProvider).deleteDictionary(entry.id);
                  final current = ref.read(downloadedDictIdsProvider);
                  ref.read(downloadedDictIdsProvider.notifier).state = List<String>.from(current)..remove(entry.id);
                },
                child: const Text('DELETE', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1)),
              ),
            )
          else
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => ref.read(dictDownloadServiceProvider).downloadDictionary(entry),
                child: const Text('DOWNLOAD', style: TextStyle(color: Color(0xFFFF5500), fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1)),
              ),
            ),
        ],
      ),
    );
  }
}
