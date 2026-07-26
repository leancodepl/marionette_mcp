import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/marionette_flutter.dart';
import 'package:marionette_flutter/src/services/widget_finder.dart';

const _configuration = MarionetteConfiguration();

/// A grid cell whose inner keys are identical in every cell — only the
/// [cellKey] wrapper tells the instances apart.
Widget _cell({
  required String cellKey,
  required String label,
  bool hasJoinButton = true,
  bool hittable = true,
}) {
  final content = Column(
    key: ValueKey(cellKey),
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label),
      if (hasJoinButton)
        ElevatedButton(
          key: const ValueKey('cell.joinButton'),
          onPressed: () {},
          child: Text('Join $label'),
        ),
    ],
  );

  return hittable ? content : IgnorePointer(child: content);
}

Widget _grid(List<Widget> cells) {
  return MaterialApp(
    home: Scaffold(
      body: Row(
        children: [for (final cell in cells) Expanded(child: cell)],
      ),
    ),
  );
}

void main() {
  group('WidgetFinder.findElement with scope', () {
    testWidgets('matches inside the requested scope, not the first cell',
        (tester) async {
      await tester.pumpWidget(_grid([
        _cell(cellKey: 'grid.cell_1', label: 'First'),
        _cell(cellKey: 'grid.cell_2', label: 'Second'),
      ]));

      final element = WidgetFinder().findElement(
        const KeyMatcher('cell.joinButton'),
        _configuration,
        scope: const KeyMatcher('grid.cell_2'),
      );

      expect(
        element,
        tester.element(find.widgetWithText(ElevatedButton, 'Join Second')),
        reason: 'a tree-wide search would have matched the first cell',
      );
    });

    testWidgets('searches the whole tree when no scope is given',
        (tester) async {
      await tester.pumpWidget(_grid([
        _cell(cellKey: 'grid.cell_1', label: 'First'),
        _cell(cellKey: 'grid.cell_2', label: 'Second'),
      ]));

      final element = WidgetFinder().findElement(
        const KeyMatcher('cell.joinButton'),
        _configuration,
      );

      expect(
        element,
        tester.element(find.widgetWithText(ElevatedButton, 'Join First')),
      );
    });

    testWidgets('throws naming the scope key when the scope is not found',
        (tester) async {
      await tester.pumpWidget(_grid([
        _cell(cellKey: 'grid.cell_1', label: 'First'),
      ]));

      expect(
        () => WidgetFinder().findElement(
          const KeyMatcher('cell.joinButton'),
          _configuration,
          scope: const KeyMatcher('grid.cell_2'),
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('grid.cell_2'),
          ),
        ),
      );
    });

    testWidgets(
      'returns null instead of falling back to a match outside the scope',
      (tester) async {
        await tester.pumpWidget(_grid([
          _cell(cellKey: 'grid.cell_1', label: 'First'),
          _cell(
            cellKey: 'grid.cell_2',
            label: 'Second',
            hasJoinButton: false,
          ),
        ]));

        final finder = WidgetFinder();

        expect(
          finder.findElement(
            const KeyMatcher('cell.joinButton'),
            _configuration,
            scope: const KeyMatcher('grid.cell_2'),
          ),
          isNull,
        );
        expect(
          finder.findElement(
              const KeyMatcher('cell.joinButton'), _configuration),
          isNotNull,
          reason: 'an identical target does exist outside the scope',
        );
      },
    );
  });

  group('WidgetFinder.findHittableElement with scope', () {
    testWidgets('matches inside the requested scope', (tester) async {
      await tester.pumpWidget(_grid([
        _cell(cellKey: 'grid.cell_1', label: 'First'),
        _cell(cellKey: 'grid.cell_2', label: 'Second'),
      ]));

      final element = WidgetFinder().findHittableElement(
        const KeyMatcher('cell.joinButton'),
        _configuration,
        scope: const KeyMatcher('grid.cell_2'),
      );

      expect(
        element,
        tester.element(find.widgetWithText(ElevatedButton, 'Join Second')),
      );
    });

    testWidgets('still enforces hittability inside the scope', (tester) async {
      await tester.pumpWidget(_grid([
        _cell(cellKey: 'grid.cell_1', label: 'First'),
        _cell(cellKey: 'grid.cell_2', label: 'Second', hittable: false),
      ]));

      final finder = WidgetFinder();

      expect(
        finder.findHittableElement(
          const KeyMatcher('cell.joinButton'),
          _configuration,
          scope: const KeyMatcher('grid.cell_2'),
        ),
        isNull,
        reason: 'the scoped target is behind an IgnorePointer',
      );
      expect(
        finder.findElement(
          const KeyMatcher('cell.joinButton'),
          _configuration,
          scope: const KeyMatcher('grid.cell_2'),
        ),
        isNotNull,
        reason: 'findElement should still find the non-hittable target',
      );
      expect(
        finder.findHittableElement(
          const KeyMatcher('cell.joinButton'),
          _configuration,
        ),
        isNotNull,
        reason: 'a hittable target does exist outside the scope',
      );
    });

    testWidgets('throws naming the scope key when the scope is not found',
        (tester) async {
      await tester.pumpWidget(_grid([
        _cell(cellKey: 'grid.cell_1', label: 'First'),
      ]));

      expect(
        () => WidgetFinder().findHittableElement(
          const KeyMatcher('cell.joinButton'),
          _configuration,
          scope: const KeyMatcher('grid.cell_2'),
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('grid.cell_2'),
          ),
        ),
      );
    });
  });
}
