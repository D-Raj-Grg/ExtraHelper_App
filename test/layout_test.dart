import 'package:extrahelper/core/layout/breakpoints.dart';
import 'package:extrahelper/core/layout/max_width_body.dart';
import 'package:extrahelper/core/layout/two_pane.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(double width, Widget child) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(size: Size(width, 800)),
    child: Scaffold(body: child),
  ),
);

Future<void> _size(WidgetTester t, double w) async {
  t.view.physicalSize = Size(w, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

void main() {
  test('window size classes', () {
    expect(WindowSize.of(390), WindowSize.compact);
    expect(WindowSize.of(599.9), WindowSize.compact);
    expect(WindowSize.of(744), WindowSize.medium);
    expect(WindowSize.of(1024), WindowSize.expanded);
  });

  group('MaxWidthBody', () {
    testWidgets('is a no-op on a phone', (t) async {
      await _size(t, 390);
      await t.pumpWidget(
        _host(390, const MaxWidthBody(child: SizedBox.expand(key: Key('c')))),
      );
      expect(t.getSize(find.byKey(const Key('c'))), const Size(390, 800));
    });

    testWidgets('caps and centres on an iPad, keeping full height', (t) async {
      await _size(t, 1024);
      await t.pumpWidget(
        _host(1024, const MaxWidthBody(child: SizedBox.expand(key: Key('c')))),
      );
      final box = find.byKey(const Key('c'));
      expect(t.getSize(box).width, Breakpoints.reading);
      expect(t.getSize(box).height, 800);
      expect(t.getCenter(box).dx, 512);
    });
  });

  group('TwoPane', () {
    Widget pane() => TwoPane(
      primary: const SizedBox.expand(key: Key('p')),
      secondary: (context, side) => SizedBox(
        key: Key(side ? 's-side' : 's-stack'),
        width: double.infinity,
        height: 100,
      ),
    );

    testWidgets('stacks on a phone', (t) async {
      await _size(t, 390);
      await t.pumpWidget(_host(390, pane()));
      expect(find.byKey(const Key('s-stack')), findsOneWidget);
      expect(t.getSize(find.byKey(const Key('s-stack'))).width, 390);
      expect(t.getSize(find.byKey(const Key('p'))).height, 700);
    });

    testWidgets('sits side by side on an iPad', (t) async {
      await _size(t, 1024);
      await t.pumpWidget(_host(1024, pane()));
      final side = find.byKey(const Key('s-side'));
      expect(side, findsOneWidget);
      expect(t.getSize(side).width, 360);
      expect(t.getTopLeft(side).dx, greaterThan(600));
      expect(t.getSize(find.byKey(const Key('p'))).height, 800);
    });
  });
}
