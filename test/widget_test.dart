import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lexo_player/main.dart';
import 'package:lexo_player/features/subtitles/providers/subtitle_providers.dart';
import 'package:lexo_player/features/dictionary/data/dictionary_providers.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('App smoke test - renders Library dashboard', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerSubtitleSyncProvider.overrideWith((ref) {}),
          dictionarySwitcherProvider.overrideWith((ref) async {}),
        ],
        child: const LexoPlayerApp(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Library'), findsOneWidget);
  });
}
