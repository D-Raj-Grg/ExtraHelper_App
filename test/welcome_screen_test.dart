import 'package:extrahelper/app/router.dart';
import 'package:extrahelper/core/prefs.dart';
import 'package:extrahelper/data/supabase/supabase_providers.dart';
import 'package:extrahelper/features/tenant/tenant_providers.dart';
import 'package:extrahelper/features/welcome/welcome_providers.dart';
import 'package:extrahelper/features/welcome/welcome_screen.dart';
import 'package:extrahelper/features/welcome/welcome_slides.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The welcome carousel.
///
/// Two things here are easy to break and expensive to notice: the screen must
/// **not** navigate (the router owns that, and a second authority would
/// eventually disagree with it), and reduce-motion must actually skip the
/// animation rather than merely shorten it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(ProviderContainer, SharedPreferences)> setUpPrefs() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWith((ref) => prefs)],
    );
    addTearDown(container.dispose);
    return (container, prefs);
  }

  Future<void> pumpWelcome(
    WidgetTester tester,
    ProviderContainer container, {
    bool disableAnimations = false,
  }) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: disableAnimations),
            child: const WelcomeScreen(),
          ),
        ),
      ),
    );
  }

  testWidgets('opens on the first slide', (tester) async {
    final (container, _) = await setUpPrefs();
    await pumpWelcome(tester, container);

    expect(find.text(welcomeSlides.first.headline), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
    expect(find.text('Get started'), findsNothing);
    expect(find.text('Skip'), findsOneWidget);
  });

  testWidgets('four Nexts reach the last slide and its button', (tester) async {
    final (container, prefs) = await setUpPrefs();
    await pumpWelcome(tester, container);

    for (var i = 0; i < welcomeSlides.length - 1; i++) {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
    }

    expect(find.text(welcomeSlides.last.headline), findsOneWidget);
    expect(find.text('Next'), findsNothing);

    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();

    expect(container.read(welcomeSeenProvider), isTrue);
    expect(prefs.getBool('welcome_seen'), isTrue);
  });

  testWidgets('Skip finishes from the first slide', (tester) async {
    final (container, prefs) = await setUpPrefs();
    await pumpWelcome(tester, container);

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(container.read(welcomeSeenProvider), isTrue);
    expect(prefs.getBool('welcome_seen'), isTrue);
  });

  // The screen must not move itself. If someone adds a `context.go` here this
  // fails, because a bare WelcomeScreen has no router to go anywhere with —
  // which is exactly the point.
  testWidgets('finishing does not navigate', (tester) async {
    final (container, _) = await setUpPrefs();
    await pumpWelcome(tester, container);

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(WelcomeScreen), findsOneWidget);
  });

  // Reduce motion is honoured by jumping, not by animating faster. One pump is
  // the assertion: an animateToPage would still be mid-flight here.
  testWidgets('reduce motion jumps instead of animating', (tester) async {
    final (container, _) = await setUpPrefs();
    await pumpWelcome(tester, container, disableAnimations: true);

    await tester.tap(find.text('Next'));
    await tester.pump();

    expect(find.text(welcomeSlides[1].headline), findsOneWidget);
  });

  testWidgets('the position is announced, not left to the dots', (
    tester,
  ) async {
    final (container, _) = await setUpPrefs();
    await pumpWelcome(tester, container);

    expect(
      find.bySemanticsLabel('Slide 1 of ${welcomeSlides.length}'),
      findsOneWidget,
    );
  });

  // The gap that let two overflows ship: the text-scale suite only exercises
  // 2.0, and at 2.0 the art is dropped — so the drawings were never rendered
  // under test at any size where they are actually shown, and neither was the
  // last slide's wider "Get started" button. Every slide, on the narrow phones,
  // across the range where the art IS drawn.
  for (final scale in const [1.0, 1.15, 1.3, 1.37]) {
    for (final size in const [Size(320, 640), Size(360, 690)]) {
      testWidgets('every slide fits at ${scale}x on ${size.width}px', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final (container, _) = await setUpPrefs();
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              builder: (context, child) => MediaQuery.withClampedTextScaling(
                minScaleFactor: scale,
                maxScaleFactor: scale,
                child: child!,
              ),
              home: const WelcomeScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        for (var i = 0; i < welcomeSlides.length; i++) {
          expect(
            tester.takeException(),
            isNull,
            reason: 'slide $i at ${scale}x on ${size.width}px',
          );
          if (i < welcomeSlides.length - 1) {
            await tester.tap(find.text('Next'));
            await tester.pumpAndSettle();
          }
        }
      });
    }
  }

  // The vignettes are also drawn small, in the debug gallery, where the
  // greyscale check happens.
  testWidgets('the vignettes render at gallery size', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final slide in welcomeSlides)
                SizedBox(height: 130, child: slide.art),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  // The drawing is decoration; the sentence is the product. At a text size this
  // large the art steps aside rather than squeezing the words off the screen.
  // The wiring, end to end, and the part with no precedent in this app: the
  // screen only sets a flag, so if the router does not listen to that flag
  // nothing moves and the carousel is a dead end on a fresh install.
  testWidgets('finishing hands off to login, via the router', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith((ref) => prefs),
        currentUserProvider.overrideWithValue(null),
        authStateProvider.overrideWith((ref) => const Stream<Session?>.empty()),
        membershipsProvider.overrideWith((ref) async => null),
        permissionsProvider.overrideWith((ref) async => <String>{}),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: container.read(routerProvider)),
      ),
    );
    await tester.pumpAndSettle();

    // Cold launch on a fresh install opens on the pitch, not on a password
    // field — `initialLocation` is `/`, so this is the redirect's doing.
    expect(find.text(welcomeSlides.first.headline), findsOneWidget);

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(find.text('Sign in to your restaurant.'), findsOneWidget);
    expect(find.byType(WelcomeScreen), findsNothing);
  });

  testWidgets('the art gives way to the words at large text', (tester) async {
    final (container, _) = await setUpPrefs();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(2)),
            child: WelcomeScreen(),
          ),
        ),
      ),
    );

    expect(find.byType(AspectRatio), findsNothing);
    expect(find.text(welcomeSlides.first.headline), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
