// Shadowing box replays the actual movie audio (no TTS).
//
// Covers: the hear button is a movie-audio replay control, and tapping it
// degrades gracefully when no player is available (e.g. widget tests) by
// resuming mic capture instead of throwing.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lexo_player/core/services/stt_service.dart';
import 'package:lexo_player/features/subtitles/presentation/shadowing_box_widget.dart';

/// STT double: mic available, captures the result callback.
class _ScriptedStt extends SttService {
  Function(String words)? onResult;
  @override
  Future<bool> initialize() async => true;
  @override
  Future<bool> startListening({
    required Function(String words) onResult,
    String localeId = 'en_US',
  }) async {
    this.onResult = onResult;
    return true;
  }

  @override
  Future<void> stopListening() async {}
}

void main() {
  SharedPreferences.setMockInitialValues({});

  group('shadowing movie-audio replay', () {
    testWidgets('hear button offers movie replay, not TTS', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [sttServiceProvider.overrideWith((ref) => _ScriptedStt())],
          child: const MaterialApp(
            home: Scaffold(
              body: ShadowingBoxWidget(
                targetSentence: 'Hello world',
                cueStart: Duration.zero,
                cueEnd: Duration(seconds: 2),
                onResume: _noop,
                onClose: _noop,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Replay control present with movie-audio semantics.
      expect(find.byIcon(Icons.replay_rounded), findsOneWidget);
      expect(find.byIcon(Icons.volume_up_rounded), findsNothing);
    });

    testWidgets('replay tap without a player resumes listening, no crash',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [sttServiceProvider.overrideWith((ref) => _ScriptedStt())],
          child: const MaterialApp(
            home: Scaffold(
              body: ShadowingBoxWidget(
                targetSentence: 'Hello world',
                cueStart: Duration.zero,
                cueEnd: Duration(seconds: 2),
                onResume: _noop,
                onClose: _noop,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Listening... speak now'), findsOneWidget);

      // No native player exists in widget tests: the tap must be absorbed
      // and mic capture resumed instead of throwing.
      await tester.tap(find.byIcon(Icons.replay_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Listening... speak now'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

void _noop() {}
