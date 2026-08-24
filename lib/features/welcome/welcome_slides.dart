import 'package:flutter/widgets.dart';

import 'welcome_art.dart';

/// What the carousel says, kept apart from how it is laid out.
///
/// Data rather than four hardcoded pages, so the widget test and the design
/// gallery can name a slide without a second copy of the words.
///
/// **Every claim here is true of what ships.** The app is a *staff* app: it
/// does not edit the menu beyond variants, and it has no loyalty or online
/// store — those are the web's. A carousel that promises them is a carousel
/// that gets someone to install the wrong thing.
@immutable
class WelcomeSlide {
  const WelcomeSlide({
    required this.headline,
    required this.body,
    required this.art,
  });

  final String headline;
  final String body;
  final Widget art;
}

const welcomeSlides = <WelcomeSlide>[
  WelcomeSlide(
    headline: "Takes orders when the wifi doesn't.",
    body:
        'Orders and changes queue on the phone and send themselves when you '
        'are back. The kitchen gets each one exactly once.',
    art: OfflineQueueArt(),
  ),
  WelcomeSlide(
    headline: 'The whole floor, in one app.',
    body:
        'Tables, orders, bills and the kitchen board — take the order, '
        'advance the ticket, split the bill.',
    art: FloorArt(),
  ),
  WelcomeSlide(
    headline: "Today's numbers, and the day closed.",
    body:
        'Live revenue, open orders and what is running low. Then the day-close '
        'report, from the same figures the web shows.',
    art: DayCloseArt(),
  ),
  WelcomeSlide(
    headline: 'Print from the phone.',
    body:
        'Pair a Bluetooth or WiFi thermal printer, send a test print, and the '
        'tickets go out with the order.',
    art: PrintArt(),
  ),
];
