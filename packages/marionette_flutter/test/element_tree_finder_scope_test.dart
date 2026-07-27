import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/marionette_flutter.dart';
import 'package:marionette_flutter/src/services/element_tree_finder.dart';
import 'package:marionette_flutter/src/services/widget_finder.dart';

const _configuration = MarionetteConfiguration();
const _finder = ElementTreeFinder(_configuration);

/// A grid cell whose inner keys are identical in every cell — only the
/// [cellKey] wrapper tells the instances apart.
Widget _cell({
  required String cellKey,
  required String label,
  bool hittable = true,
}) {
  final content = Column(
    key: ValueKey(cellKey),
    mainAxisSize: MainAxisSize.min,
    children: [
      // The only per-cell distinguishable text: the button is a traversal
      // stop widget, so its own Text child is never reached.
      Text(label),
      ElevatedButton(
        key: const ValueKey('cell.joinButton'),
        onPressed: () {},
        child: const Text('Join'),
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

/// A session embedding a whole grid, so even the cell keys repeat across
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

/// Resolves an `ancestor_keys` scope exactly the way the
/// `marionette.interactiveElements` extension does.
Element? _scopeRoot(List<String> keys) {
  return WidgetFinder().resolveScopeRoot(
    [for (final key in keys) KeyMatcher(key)],
    _configuration,
  );
}

bool _hasText(List<Map<String, dynamic>> elements, String text) {
  return elements.any((e) => e['text'] == text);
}

void main() {
  group('ElementTreeFinder.findInteractiveElements with a scope', () {
    testWidgets('lists only the elements inside the scope subtree',
        (tester) async {
      await tester.pumpWidget(_grid([
        _cell(cellKey: 'grid.cell_1', label: 'First'),
        _cell(cellKey: 'grid.cell_2', label: 'Second'),
      ]));

      final elements = _finder.findInteractiveElements(
        startElement: _scopeRoot(['grid.cell_2']),
      );

      expect(_hasText(elements, 'Second'), isTrue);
      expect(
        _hasText(elements, 'First'),
        isFalse,
        reason: 'an unscoped walk would list both cells',
      );
    });

    testWidgets('resolves a nested chain to a cell no single key can name',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                _session('session_1', [
                  _cell(cellKey: 'grid.cell_2', label: 'A2'),
                ]),
                _session('session_2', [
                  _cell(cellKey: 'grid.cell_2', label: 'B2'),
                ]),
              ],
            ),
          ),
        ),
      );

      final elements = _finder.findInteractiveElements(
        startElement: _scopeRoot(['session_2', 'grid.cell_2']),
      );

      expect(
        _hasText(elements, 'B2'),
        isTrue,
        reason: '"grid.cell_2" alone would have listed session_1\'s cell',
      );
      expect(_hasText(elements, 'A2'), isFalse);
    });

    testWidgets('includes the scope element itself', (tester) async {
      await tester.pumpWidget(_grid([
        _cell(cellKey: 'grid.cell_1', label: 'First'),
        _cell(cellKey: 'grid.cell_2', label: 'Second'),
      ]));

      final elements = _finder.findInteractiveElements(
        startElement: _scopeRoot(['grid.cell_2']),
      );

      expect(
        elements.any((e) => e['key'] == 'grid.cell_2'),
        isTrue,
        reason: 'the wrapper is itself actionable with the same ancestor_keys, '
            'and a scope key sitting on an interactive widget would list '
            'nothing at all if the scope element were skipped',
      );
    });

    testWidgets('lists the whole tree when no start element is given',
        (tester) async {
      await tester.pumpWidget(_grid([
        _cell(cellKey: 'grid.cell_1', label: 'First'),
        _cell(cellKey: 'grid.cell_2', label: 'Second'),
      ]));

      final elements = _finder.findInteractiveElements();

      expect(_hasText(elements, 'First'), isTrue);
      expect(_hasText(elements, 'Second'), isTrue);
    });

    testWidgets('still filters non-hittable elements inside the scope',
        (tester) async {
      await tester.pumpWidget(_grid([
        _cell(cellKey: 'grid.cell_1', label: 'First'),
        _cell(cellKey: 'grid.cell_2', label: 'Second', hittable: false),
      ]));

      final elements = _finder.findInteractiveElements(
        startElement: _scopeRoot(['grid.cell_2']),
      );

      expect(
        find.text('Second'),
        findsOneWidget,
        reason: 'the label is in the tree, just behind an IgnorePointer',
      );
      expect(
        _hasText(elements, 'Second'),
        isFalse,
        reason: 'scoping must not weaken the hittability filter',
      );
    });

    testWidgets('throws naming the scope key when the scope element is absent',
        (tester) async {
      await tester.pumpWidget(_grid([
        _cell(cellKey: 'grid.cell_1', label: 'First'),
      ]));

      expect(
        () => _finder.findInteractiveElements(
          startElement: _scopeRoot(['grid.cell_2']),
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            allOf(contains('grid.cell_2'), contains('ancestor_keys')),
          ),
        ),
        reason: 'discovery inherits the fail-loud scope policy instead of '
            'silently listing the whole tree',
      );
    });
  });
}
