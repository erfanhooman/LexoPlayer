// Repro for: opening Shadow + spoiler subtitle mode, then exiting crashes.
//
// Drives the exact user flow at widget level:
//  1. shadowing box opens while spoiler mode is on,
//  2. spoiler mode is toggled off/on around it,
//  3. the shadowing box is closed (X) and resumed,
//  4. the overlay transitions shadowing <-> spoiler-blurred subtitle.
//
// Any exception during pump/dispose fails the test.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lexo_player/core/engine/engine_providers.dart';
import 'package:lexo_player/core/services/stt_service.dart';
import 'package:lexo_player/features/subtitles/presentation/interactive_subtitle_overlay.dart';
import 'package:lexo_player/features/subtitles/presentation/shadowing_box_widget.dart';
import 'package:lexo_player/features/subtitles/providers/subtitle_providers.dart';

/// STT double: mic unavailable -> typing fallback UI.
class _NoMicStt extends SttService {
  @override
  Future<bool> initialize() async => false;
}

/// STT double: controllable listening, captures the result callback so tests
/// can feed recognized speech deterministically (no platform channels).
class _ScriptedStt extends SttService {
  Function(String words)? onResult;
  bool listening = false;

  @override
  Future<bool> initialize() async => true;

  @override
  Future<bool> startListening({
    required Function(String words) onResult,
    String localeId = 'en_US',
  }) async {
    this.onResult = onResult;
    listening = true;
    return true;
  }

  @override
  Future<void> stopListening() async {
    listening = false;
  }

  void hear(String words) => onResult?.call(words);
}

Widget _harness(Widget child, List<Override> overrides) {
  return ProviderScope(
    // Unique key: forces a brand-new container on every pumpWidget.
    // Without it, pumpWidget reuses the root element and the FIRST tree's
    // overrides leak into the second tree.
    key: UniqueKey(),
    overrides: overrides,
    child: MaterialApp(
      home: Scaffold(
        body: Stack(children: [child]),
      ),
    ),
  );
}

void main() {
  SharedPreferences.setMockInitialValues({});

  group('shadowing + spoiler exit crash', () {
    testWidgets('shadowing box opens, spoiler toggles, box closes cleanly',
        (tester) async {
      var closed = false;
      var resumed = false;
      final scriptedStt = _ScriptedStt();

      await tester.pumpWidget(_harness(
        Consumer(builder: (context, ref, _) {
          final spoiler = ref.watch(isSubtitleSpoilerModeEnabledProvider);
          return Column(
            children: [
              Text(spoiler ? 'spoiler-on' : 'spoiler-off'),
              ShadowingBoxWidget(
                targetSentence: 'Hello world',
                onResume: () => resumed = true,
                onClose: () => closed = true,
              ),
            ],
          );
        }),
        [sttServiceProvider.overrideWith((ref) => scriptedStt)],
      ));
      await tester.pump();

      // Listening UI is up (scripted STT reports available).
      expect(find.text('Listening... speak now'), findsOneWidget);

      final container =
          ProviderScope.containerOf(tester.element(find.text('spoiler-off')));

      // Toggle spoiler mode on/off while the box is open.
      container.read(isSubtitleSpoilerModeEnabledProvider.notifier).state =
          true;
      await tester.pump();
      expect(find.text('spoiler-on'), findsOneWidget);
      container.read(isSubtitleSpoilerModeEnabledProvider.notifier).state =
          false;
      await tester.pump();
      expect(find.text('spoiler-off'), findsOneWidget);

      // Feed the full sentence -> completion countdown starts.
      scriptedStt.hear('Hello world');
      await tester.pump();
      expect(find.textContaining('Perfect match'), findsOneWidget);

      // Close the box mid-countdown (the reported crash moment).
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();
      expect(closed, isTrue);

      // Mic-unavailable branch: typing fallback completes + resumes.
      await tester.pumpWidget(_harness(
        Consumer(builder: (context, ref, _) {
          return ShadowingBoxWidget(
            targetSentence: 'Hello world',
            onResume: () => resumed = true,
            onClose: () => closed = true,
          );
        }),
        [sttServiceProvider.overrideWith((ref) => _NoMicStt())],
      ));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.byType(TextField), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Hello world');
      await tester.pump();
      await tester.tap(find.text('Resume Now'));
      await tester.pump();
      expect(resumed, isTrue);

      // Unmount everything (second dispose path).
      await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(home: Scaffold(body: SizedBox.shrink())),
      ));
      await tester.pump();
    });

    testWidgets('overlay transitions shadowing <-> spoiler without throwing',
        (tester) async {
      await tester.pumpWidget(_harness(
        const InteractiveSubtitleOverlay(),
        [
          activeSubtitleTextProvider.overrideWith((ref) => 'Hello world'),
          activeSecondarySubtitleTextProvider.overrideWith((ref) => null),
          engineOutputProvider.overrideWith((ref) async => null),
        ],
      ));
      await tester.pump();
      expect(find.byType(InteractiveSubtitleOverlay), findsOneWidget);

      final container = ProviderScope.containerOf(
          tester.element(find.byType(InteractiveSubtitleOverlay)));

      // Spoiler on -> blurred subtitle with reveal badge.
      container.read(isSubtitleSpoilerModeEnabledProvider.notifier).state =
          true;
      container.read(activeSubtitleIndexProvider.notifier).state = 0;
      await tester.pump();
      expect(find.text('Click to reveal subtitle'), findsOneWidget);

      // Reveal the cue, then open shadowing (box replaces overlay).
      await tester.tap(find.text('Click to reveal subtitle'));
      await tester.pump();
      container.read(activeShadowingStateProvider.notifier).state = true;
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(ShadowingBoxWidget), findsOneWidget);

      // Exit shadowing while spoiler is still on (reported crash moment).
      container.read(activeShadowingStateProvider.notifier).state = false;
      await tester.pump();
      expect(find.byType(ShadowingBoxWidget), findsNothing);

      // Turn spoiler off, change cue, hide subtitles entirely.
      container.read(isSubtitleSpoilerModeEnabledProvider.notifier).state =
          false;
      await tester.pump();
      container.read(activeSubtitleIndexProvider.notifier).state = 1;
      await tester.pump();
      container.read(subtitleVisibilityProvider.notifier).state = false;
      await tester.pump();
      container.read(subtitleVisibilityProvider.notifier).state = true;
      await tester.pump();
    });

    testWidgets('spoiler button on the subtitle bar toggles blur',
        (tester) async {
      await tester.pumpWidget(_harness(
        const InteractiveSubtitleOverlay(),
        [
          activeSubtitleTextProvider.overrideWith((ref) => 'Hello world'),
          activeSecondarySubtitleTextProvider.overrideWith((ref) => null),
          engineOutputProvider.overrideWith((ref) async => null),
        ],
      ));
      await tester.pump();

      final container = ProviderScope.containerOf(
          tester.element(find.byType(InteractiveSubtitleOverlay)));

      // Hover the subtitle area so the action row appears (desktop pattern).
      // NOTE: several small pumps, not one big pump — implicit reveal
      // animations need consecutive frames to progress past their initial
      // value (a single pump leaves the button at height 0, unhittable).
      // The pointer stays down throughout: removing it un-hovers and
      // collapses the action row before the taps below.
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      await gesture
          .moveTo(tester.getCenter(find.byType(InteractiveSubtitleOverlay)));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // The spoiler toggle is now hittable next to the subtitle.
      expect(find.text('Spoiler'), findsOneWidget);
      await tester.tap(find.text('Spoiler'));
      await tester.pump();
      expect(container.read(isSubtitleSpoilerModeEnabledProvider), isTrue);
      expect(find.text('Click to reveal subtitle'), findsOneWidget);

      // Current cue blurs immediately (revealed index cleared on enable).
      expect(container.read(activeRevealedSubtitleCueIndexProvider), isNull);

      // Toggle back off from the same button.
      await tester.tap(find.text('Spoiler on'));
      await tester.pump();
      expect(container.read(isSubtitleSpoilerModeEnabledProvider), isFalse);
      expect(find.text('Click to reveal subtitle'), findsNothing);
      await gesture.removePointer();
    });
  });
}
