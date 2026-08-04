import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexo_player/features/dictionary/presentation/spoiler_translation_widget.dart';

void main() {
  group('SpoilerTranslationWidget', () {
    testWidgets('parses comma-separated translations into chips', (tester) async {
      const rawText = 'دوست داشتن, مایل بودن, دل خواستن';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SpoilerTranslationWidget(
              rawTranslation: rawText,
              initialMaxItems: 5,
            ),
          ),
        ),
      );

      // Verify that "Reveal translation" button is rendered
      expect(find.text('Reveal translation'), findsOneWidget);

      // Verify text items exist within chips
      expect(find.text('دوست داشتن'), findsOneWidget);
      expect(find.text('مایل بودن'), findsOneWidget);
      expect(find.text('دل خواستن'), findsOneWidget);
    });

    testWidgets('shows max items and +X more button for long lists', (tester) async {
      const rawText = 'item1, item2, item3, item4, item5, item6';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SpoilerTranslationWidget(
              rawTranslation: rawText,
              initialMaxItems: 3,
            ),
          ),
        ),
      );

      // Verify only first 3 items are rendered initially
      expect(find.text('item1'), findsOneWidget);
      expect(find.text('item2'), findsOneWidget);
      expect(find.text('item3'), findsOneWidget);
      expect(find.text('item4'), findsNothing);

      // Verify +3 more button exists
      expect(find.text('+3 more'), findsOneWidget);

      // Tap +3 more button to expand
      await tester.tap(find.text('+3 more'));
      await tester.pump();

      // Now all items should be visible
      expect(find.text('item4'), findsOneWidget);
      expect(find.text('item5'), findsOneWidget);
      expect(find.text('item6'), findsOneWidget);
      expect(find.text('Show less'), findsOneWidget);
    });

    testWidgets('toggling reveal all updates button text to Hide translation', (tester) async {
      const rawText = 'دوست داشتن, مایل بودن';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SpoilerTranslationWidget(
              rawTranslation: rawText,
              initialMaxItems: 3,
            ),
          ),
        ),
      );

      expect(find.text('Reveal translation'), findsOneWidget);

      await tester.tap(find.text('Reveal translation'));
      await tester.pump();

      expect(find.text('Hide translation'), findsOneWidget);
    });
  });
}
