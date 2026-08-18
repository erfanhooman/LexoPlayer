import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lexo_player/core/models/subtitle_block.dart';
import 'package:lexo_player/features/subtitles/providers/subtitle_providers.dart';
import 'package:lexo_player/features/subtitles/logic/binary_search_sync.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Dual Subtitle & Persistence Tests', () {
    test('Dual subtitle state derivation & Persian text rendering', () {
      final container = ProviderContainer();

      const primaryOption = SubtitleTrackOption(
        id: 'primary_en',
        name: 'English (Primary)',
        isExternal: true,
        externalBlocks: [
          SubtitleBlock(
            startTime: Duration(seconds: 2),
            endTime: Duration(seconds: 5),
            text: 'Hello world',
          ),
        ],
      );

      const secondaryOption = SubtitleTrackOption(
        id: 'secondary_fa',
        name: 'Persian (Secondary)',
        isExternal: true,
        externalBlocks: [
          SubtitleBlock(
            startTime: Duration(seconds: 2),
            endTime: Duration(seconds: 5),
            text: 'سلام دنیا',
          ),
        ],
      );

      // 1. Set options and blocks
      container.read(selectedSubtitleProvider.notifier).state = primaryOption;
      container.read(subtitleListProvider.notifier).state = primaryOption.externalBlocks!;

      container.read(selectedSecondarySubtitleProvider.notifier).state = secondaryOption;
      container.read(secondarySubtitleListProvider.notifier).state = secondaryOption.externalBlocks!;

      // 2. Set active index at 3 seconds
      final position = const Duration(seconds: 3);
      final pIdx = BinarySearchSync.findActiveIndex(primaryOption.externalBlocks!, position);
      final sIdx = BinarySearchSync.findActiveIndex(secondaryOption.externalBlocks!, position);

      container.read(activeSubtitleIndexProvider.notifier).state = pIdx;
      container.read(activeSecondarySubtitleIndexProvider.notifier).state = sIdx;

      // 3. Verify both primary and secondary texts derive correctly
      expect(container.read(activeSubtitleTextProvider), equals('Hello world'));
      expect(container.read(activeSecondarySubtitleTextProvider), equals('سلام دنیا'));

      // 4. Verify Persian text contains Persian Unicode range
      final secondaryText = container.read(activeSecondarySubtitleTextProvider);
      expect(RegExp(r'[\u0600-\u06FF]').hasMatch(secondaryText!), isTrue);
    });

    test('Media subtitle selection persistence across video re-opens', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      const testUri = '/path/to/movie.mp4';

      const primaryOption = SubtitleTrackOption(
        id: 'external_sub_en',
        name: 'movie.en.srt',
        isExternal: true,
        filePath: '/path/to/movie.en.srt',
      );

      const secondaryOption = SubtitleTrackOption(
        id: 'external_sub_fa',
        name: 'movie.fa.srt',
        isExternal: true,
        filePath: '/path/to/movie.fa.srt',
      );

      // 1. Save selection
      await saveMediaSubtitleSelection(
        videoUri: testUri,
        primaryOption: primaryOption,
        secondaryOption: secondaryOption,
      );

      // 2. Simulate opening video and restoring selections
      final available = [primaryOption, secondaryOption];
      await restoreMediaSubtitleSelection(
        videoUri: testUri,
        ref: container,
        availableOptions: available,
      );

      expect(container.read(selectedSubtitleProvider)?.id, equals('external_sub_en'));
      expect(container.read(selectedSecondarySubtitleProvider)?.id, equals('external_sub_fa'));
    });
  });
}
