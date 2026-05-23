import 'package:flutter_test/flutter_test.dart';
import 'package:lexo_player/core/models/subtitle_block.dart';
import 'package:lexo_player/features/subtitles/logic/binary_search_sync.dart';

void main() {
  group('BinarySearchSync', () {
    final blocks = [
      SubtitleBlock(
        startTime: const Duration(seconds: 1),
        endTime: const Duration(seconds: 4),
        text: 'First subtitle',
      ),
      SubtitleBlock(
        startTime: const Duration(seconds: 6),
        endTime: const Duration(seconds: 9),
        text: 'Second subtitle',
      ),
      SubtitleBlock(
        startTime: const Duration(seconds: 12),
        endTime: const Duration(seconds: 15),
        text: 'Third subtitle',
      ),
      SubtitleBlock(
        startTime: const Duration(seconds: 20),
        endTime: const Duration(seconds: 25),
        text: 'Fourth subtitle',
      ),
    ];

    group('findActiveIndex', () {
      test('returns null for empty list', () {
        expect(BinarySearchSync.findActiveIndex([], Duration.zero), isNull);
      });

      test('returns null when position is before first block', () {
        expect(
          BinarySearchSync.findActiveIndex(
              blocks, const Duration(milliseconds: 500)),
          isNull,
        );
      });

      test('returns null when position is after last block', () {
        expect(
          BinarySearchSync.findActiveIndex(
              blocks, const Duration(seconds: 30)),
          isNull,
        );
      });

      test('returns null when position is in a gap between blocks', () {
        expect(
          BinarySearchSync.findActiveIndex(
              blocks, const Duration(seconds: 5)),
          isNull,
        );
      });

      test('returns correct index when position is at exact startTime', () {
        expect(
          BinarySearchSync.findActiveIndex(
              blocks, const Duration(seconds: 6)),
          equals(1),
        );
      });

      test('returns correct index when position is at exact endTime', () {
        expect(
          BinarySearchSync.findActiveIndex(
              blocks, const Duration(seconds: 9)),
          equals(1),
        );
      });

      test('returns correct index when position is within a block', () {
        expect(
          BinarySearchSync.findActiveIndex(
              blocks, const Duration(seconds: 13)),
          equals(2),
        );
      });

      test('works with first block', () {
        expect(
          BinarySearchSync.findActiveIndex(
              blocks, const Duration(seconds: 2)),
          equals(0),
        );
      });

      test('works with last block', () {
        expect(
          BinarySearchSync.findActiveIndex(
              blocks, const Duration(seconds: 22)),
          equals(3),
        );
      });

      test('works with single-element list', () {
        final single = [
          SubtitleBlock(
            startTime: const Duration(seconds: 5),
            endTime: const Duration(seconds: 10),
            text: 'Only one',
          ),
        ];
        expect(
          BinarySearchSync.findActiveIndex(
              single, const Duration(seconds: 7)),
          equals(0),
        );
        expect(
          BinarySearchSync.findActiveIndex(
              single, const Duration(seconds: 3)),
          isNull,
        );
      });
    });

    group('findInsertionPoint', () {
      test('returns 0 when position is before all blocks', () {
        expect(
          BinarySearchSync.findInsertionPoint(
              blocks, const Duration(milliseconds: 500)),
          equals(0),
        );
      });

      test('returns blocks.length when position is after all blocks', () {
        expect(
          BinarySearchSync.findInsertionPoint(
              blocks, const Duration(seconds: 30)),
          equals(4),
        );
      });

      test('returns next block index when in gap', () {
        expect(
          BinarySearchSync.findInsertionPoint(
              blocks, const Duration(seconds: 5)),
          equals(1), // next subtitle starts at index 1
        );
      });
    });
  });
}
