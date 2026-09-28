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

/// A session that embeds a whole grid, so even the cell keys repeat across
/// sessions and only the full ancestor chain identifies one cell.
Widget _session(String sessionKey, List<Widget> cells) {
  return Expanded(
    child: Column(
      key: ValueKey(sessionKey),
      mainAxisSize: MainAxisSize.min,
      children: cells,
    ),
  );
}

Widget _app(List<Widget> children) {
  return MaterialApp(
    home: Scaffold(body: Row(children: children)),
  );
}

Widget _grid(List<Widget> cells) {
  return _app([for (final cell in cells) Expanded(child: cell)]);
}

List<KeyMatcher> _ancestors(List<String> keys) {
  return [for (final key in keys) KeyMatcher(key)];
}

void main() {
  group('WidgetFinder.findElement with ancestors', () {
    testWidgets('matches inside the requested scope, not the first cell',
        (tester) async {
      await tester.pumpWidget(_grid([
        _cell(cellKey: 'grid.cell_1', label: 'First'),
        _cell(cellKey: 'grid.cell_2', label: 'Second'),
      ]));

      final element = WidgetFinder().findElement(
        const KeyMatcher('cell.joinButton'),
        _configuration,
        ancestors: _ancestors(['grid.cell_2']),
      );

      expect(
        element,
        tester.element(find.widgetWithText(ElevatedButton, 'Join Second')),
        reason: 'a tree-wide search would have matched the first cell',
      );
    });

    testWidgets('resolves each ancestor inside the previous one',
        (tester) async {
      await tester.pumpWidget(_app([
        _session('session_1', [
          _cell(cellKey: 'grid.cell_1', label: 'A1'),
          _cell(cellKey: 'grid.cell_2', label: 'A2'),
        ]),
        _session('session_2', [
          _cell(cellKey: 'grid.cell_1', label: 'B1'),
          _cell(cellKey: 'grid.cell_2', label: 'B2'),
        ]),
      ]));

      final element = WidgetFinder().findElement(
        const KeyMatcher('cell.joinButton'),
        _configuration,
        ancestors: _ancestors(['session_2', 'grid.cell_2']),
      );

      expect(
        element,
        tester.element(find.widgetWithText(ElevatedButton, 'Join B2')),
        reason: 'scoping to grid.cell_2 alone would have matched the cell in '
            'the first session',
      );
    });

    testWidgets('searches the whole tree when no ancestors are given',
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

    testWidgets('throws naming the ancestor key that was not found',
        (tester) async {
      await tester.pumpWidget(_grid([
        _cell(cellKey: 'grid.cell_1', label: 'First'),
      ]));

      expect(
        () => WidgetFinder().findElement(
          const KeyMatcher('cell.joinButton'),
          _configuration,
          ancestors: _ancestors(['grid.cell_2']),
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            allOf(contains('grid.cell_2'), contains('ancestor_keys[0]')),
          ),
        ),
      );
    });

    testWidgets(
      'throws naming the failing link and its parent for a nested chain',
      (tester) async {
        await tester.pumpWidget(_app([
          _session('session_1', [
            _cell(cellKey: 'grid.cell_2', label: 'A2'),
          ]),
          _session('session_2', [
            _cell(cellKey: 'grid.cell_1', label: 'B1'),
          ]),
        ]));

        expect(
          () => WidgetFinder().findElement(
            const KeyMatcher('cell.joinButton'),
            _configuration,
            ancestors: _ancestors(['session_2', 'grid.cell_2']),
          ),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              allOf(
                contains('grid.cell_2'),
                contains('ancestor_keys[1]'),
                contains('session_2'),
              ),
            ),
          ),
          reason: 'grid.cell_2 exists, but not inside session_2 — the error '
              'must say which link of the chain broke and where',
        );
      },
    );

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
            ancestors: _ancestors(['grid.cell_2']),
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

  group('WidgetFinder.findHittableElement with ancestors', () {
    testWidgets('matches inside the requested scope', (tester) async {
      await tester.pumpWidget(_grid([
        _cell(cellKey: 'grid.cell_1', label: 'First'),
        _cell(cellKey: 'grid.cell_2', label: 'Second'),
      ]));

      final element = WidgetFinder().findHittableElement(
        const KeyMatcher('cell.joinButton'),
        _configuration,
        ancestors: _ancestors(['grid.cell_2']),
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
          ancestors: _ancestors(['grid.cell_2']),
        ),
        isNull,
        reason: 'the scoped target is behind an IgnorePointer',
      );
      expect(
        finder.findElement(
          const KeyMatcher('cell.joinButton'),
          _configuration,
          ancestors: _ancestors(['grid.cell_2']),
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

    testWidgets('throws naming the ancestor key that was not found',
        (tester) async {
      await tester.pumpWidget(_grid([
        _cell(cellKey: 'grid.cell_1', label: 'First'),
      ]));

      expect(
        () => WidgetFinder().findHittableElement(
          const KeyMatcher('cell.joinButton'),
          _configuration,
          ancestors: _ancestors(['grid.cell_2']),
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            allOf(contains('grid.cell_2'), contains('ancestor_keys[0]')),
          ),
        ),
      );
    });
  });
}
