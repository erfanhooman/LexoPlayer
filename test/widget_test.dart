import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lexo_player/main.dart';
import 'package:lexo_player/features/subtitles/providers/subtitle_providers.dart';
import 'package:lexo_player/core/engine/engine_providers.dart';

import 'package:lexo_player/core/services/now_playing_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('App smoke test - renders LexoPlayer app', (WidgetTester tester) async {
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('overflowed')) return;
      originalOnError?.call(details);
    };
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerSubtitleSyncProvider.overrideWith((ref) {}),
          nowPlayingSyncProvider.overrideWith((ref) {}),
          unifiedDictSwitcherProvider.overrideWith((ref) async {}),
          engineInitProvider.overrideWith((ref) async {}),
        ],
        child: const LexoPlayerApp(),
      ),
    );

    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(LexoPlayerApp), findsOneWidget);
  });
}
