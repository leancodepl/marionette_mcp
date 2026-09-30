import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/marionette_flutter.dart';
import 'package:marionette_flutter/src/binding/extensions/info_extensions.dart';
import 'package:marionette_flutter/src/services/element_tree_finder.dart';
import 'package:marionette_flutter/src/services/widget_finder.dart';

const _configuration = MarionetteConfiguration();

/// Calls the interactiveElements composition with params as they arrive over
/// the VM service: string values, the chain JSON-encoded.
List<Map<String, dynamic>> _list(List<String>? ancestorKeys) {
  return findScopedInteractiveElements(
    {if (ancestorKeys != null) 'ancestor_keys': jsonEncode(ancestorKeys)},
    elementTreeFinder: const ElementTreeFinder(_configuration),
    widgetFinder: WidgetFinder(),
    configuration: _configuration,
  );
}

bool _hasText(List<Map<String, dynamic>> elements, String text) {
  return elements.any((e) => e['text'] == text);
}

/// Two sessions embedding the same grid, so the cell keys repeat.
Widget _sessions() {
  Widget session(String key, String label) {
    return Expanded(
      child: Column(
        key: ValueKey(key),
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final cell in ['grid.cell_1', 'grid.cell_2'])
            Column(
              key: ValueKey(cell),
              mainAxisSize: MainAxisSize.min,
              children: [Text('$label ${cell.split('_').last}')],
            ),
        ],
      ),
    );
  }

  return MaterialApp(
    home: Scaffold(
      body:
          Row(children: [session('session_1', 'A'), session('session_2', 'B')]),
    ),
  );
}

void main() {
  group('marionette.interactiveElements with ancestor_keys', () {
    testWidgets('lists the subtree a nested chain resolves to', (tester) async {
      await tester.pumpWidget(_sessions());

      final elements = _list(['session_2', 'grid.cell_2']);

      expect(_hasText(elements, 'B 2'), isTrue);
      expect(_hasText(elements, 'A 2'), isFalse,
          reason: 'grid.cell_2 alone would be the first session\'s cell');
      expect(_hasText(elements, 'B 1'), isFalse);
    });

    testWidgets('fails naming a key that has no element', (tester) async {
      await tester.pumpWidget(_sessions());

      expect(
        () => _list(['session_2', 'grid.cell_9']),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            allOf(
              contains('"grid.cell_9"'),
              contains('ancestor_keys[1]'),
              contains('inside "session_2"'),
            ),
          ),
        ),
        reason: 'a missing scope must not fall back to the whole tree',
      );
    });

    testWidgets('lists the whole tree without a scope', (tester) async {
      await tester.pumpWidget(_sessions());

      final elements = _list(null);

      for (final text in ['A 1', 'A 2', 'B 1', 'B 2']) {
        expect(_hasText(elements, text), isTrue, reason: text);
      }
    });

    testWidgets('resolves a key repeated on adjacent levels to the inner one',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              key: ValueKey('node'),
              children: [
                Text('outer'),
                Column(key: ValueKey('node'), children: [Text('inner')]),
              ],
            ),
          ),
        ),
      );

      final elements = _list(['node', 'node']);

      expect(_hasText(elements, 'inner'), isTrue);
      expect(_hasText(elements, 'outer'), isFalse);
    });
  });
}
