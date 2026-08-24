import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import 'welcome_providers.dart';
import 'welcome_slides.dart';

/// What the app is, before it asks who you are.
///
/// The first screen of a cold install used to be a password field. This app is
/// for restaurant *staff* — not for guests ordering dinner — and nothing said
/// so until someone was already inside.
///
/// **Shown once per install.** After it is dismissed the app opens on the login
/// screen exactly as it did before; see [welcomeSeenProvider] for the flag and
/// `app/redirect.dart` for the gate.
///
/// **It does not navigate.** Both buttons mark the flag and stop there. The
/// router listens to that flag, re-resolves, and moves to `/login` — the same
/// single authority that decides where every other user belongs. A screen that
/// called `context.go` here would be a second one, and the two would eventually
/// disagree.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    final target = _index + 1;
    if (target >= welcomeSlides.length) return;
    // Reduce motion is a request, not a preference to weigh: honour it.
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.jumpToPage(target);
    } else {
      _controller.animateToPage(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
  }

  void _finish() {
    // Unawaited on purpose: the state flips synchronously inside, which is what
    // moves the router. The disk write is not something anyone should wait on.
    ref.read(welcomeSeenProvider.notifier).markSeen();
  }

  @override
  Widget build(BuildContext context) {
    final last = _index == welcomeSlides.length - 1;
    final primaryLabel = last ? 'Get started' : 'Next';

    final skip = TextButton(
      onPressed: _finish,
      style: TextButton.styleFrom(
        minimumSize: const Size(72, Tokens.tapTarget),
      ),
      child: const Text('Skip'),
    );
    final primary = FilledButton(
      onPressed: last ? _finish : _next,
      style: FilledButton.styleFrom(
        minimumSize: const Size(96, Tokens.tapTarget),
      ),
      child: Text(primaryLabel),
    );

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: welcomeSlides.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) => _Slide(slide: welcomeSlides[i]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              // Two buttons and an indicator do not always fit across one line,
              // and when they do not, Flutter resolves it by clipping the end
              // of a label. **Measure rather than guess**: this first shipped
              // with a text-scale threshold, which missed the case that
              // actually bites — "Get started" is wider than "Next", so the
              // last slide overflowed a 320px phone at *normal* text size while
              // the threshold sat unfired. What matters is whether these
              // particular words fit this particular width, so ask.
              //
              // Stacking is the fallback rather than shrinking, because
              // answering a request for bigger text with smaller text is not an
              // answer.
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final fits =
                      _controlsWidth(context, primaryLabel) <=
                      constraints.maxWidth;
                  if (!fits) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Dots(index: _index),
                        const SizedBox(height: 12),
                        primary,
                        const SizedBox(height: 4),
                        skip,
                      ],
                    );
                  }
                  return Row(
                    children: [
                      // Kept on every slide, including the last. It does
                      // exactly what "Get started" does, and showing it
                      // throughout means the row never changes width under
                      // the dots.
                      skip,
                      Expanded(child: _Dots(index: _index)),
                      primary,
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What the one-line controls row would need, in logical pixels.
///
/// Measured with the same [TextScaler] and text style the buttons will draw
/// with, because the two things that move this — the phone's text size and the
/// metrics of whichever font resolves — are exactly the two a hardcoded
/// threshold cannot see.
double _controlsWidth(BuildContext context, String primaryLabel) {
  final theme = Theme.of(context);
  final scaler = MediaQuery.textScalerOf(context);

  double measure(String text) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: theme.textTheme.labelLarge),
      textDirection: Directionality.of(context),
      textScaler: scaler,
    )..layout();
    return painter.width;
  }

  // Each button's own horizontal padding, plus the dots and a little air. The
  // dots are a fixed 20 + 3 × 8 with 6 of margin each.
  const skipPadding = 32.0;
  const primaryPadding = 48.0;
  const dots = 68.0;
  const air = 16.0;

  return measure('Skip') +
      skipPadding +
      measure(primaryLabel) +
      primaryPadding +
      dots +
      air;
}

/// Whether text has grown enough that the layout has to give something up.
///
/// One threshold, used twice: it drops the illustration and it stacks the
/// controls. Two separate numbers would drift, and the point at which a slide
/// stops fitting is one fact about the screen, not two.
bool tightOnText(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(16) > 22;

class _Slide extends StatelessWidget {
  const _Slide({required this.slide});

  final WelcomeSlide slide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // The drawing is decoration and the words are the product, so past a point
    // the drawing goes rather than squeezing the sentence it illustrates.
    final roomForArt = !tightOnText(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (roomForArt) ...[
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 210),
                  child: slide.art,
                ),
                const SizedBox(height: 32),
              ],
              Text(slide.headline, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                slide.body,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Where you are in the four.
///
/// Not tappable: an 8px dot cannot honestly carry a 44px target, and four hit
/// areas sitting on the swipe would fight it. The position is announced instead.
///
/// The active dot differs in **width and fill**, not in opacity — an
/// opacity-only indicator is the classic thing that vanishes in greyscale.
class _Dots extends StatelessWidget {
  const _Dots({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180);

    return Semantics(
      label: 'Slide ${index + 1} of ${welcomeSlides.length}',
      child: ExcludeSemantics(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < welcomeSlides.length; i++)
              AnimatedContainer(
                duration: duration,
                curve: Curves.easeOut,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == index ? 20 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: i == index ? scheme.primary : Colors.transparent,
                  border: Border.all(
                    color: i == index ? scheme.primary : scheme.outlineVariant,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
