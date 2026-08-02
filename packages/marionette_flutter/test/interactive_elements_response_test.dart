import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/src/binding/extensions/info_extensions.dart';

void main() {
  test('response includes a versioned JSON-safe context snapshot', () {
    final response = buildInteractiveElementsResponse(
      <Map<String, dynamic>>[
        <String, dynamic>{'type': 'Button', 'text': 'Continue'},
      ],
      contextProvider: () => <String, Object?>{
        'route': '/checkout',
        'screen': 'Checkout',
      },
    );

    expect(response, <String, Object?>{
      'schemaVersion': 1,
      'context': <String, Object?>{'route': '/checkout', 'screen': 'Checkout'},
      'elements': <Map<String, dynamic>>[
        <String, dynamic>{'type': 'Button', 'text': 'Continue'},
      ],
    });
    expect(() => jsonEncode(response), returnsNormally);
  });

  test('legacy callers can still read the unchanged elements field', () {
    final elements = <Map<String, dynamic>>[
      <String, dynamic>{'type': 'TextField'},
    ];

    final response = buildInteractiveElementsResponse(elements);

    expect(response['elements'], same(elements));
    expect(response['schemaVersion'], 1);
    expect(response, isNot(contains('context')));
  });

  test('invalid optional context does not fail element discovery', () {
    final throwing = buildInteractiveElementsResponse(
      const <Map<String, dynamic>>[],
      contextProvider: () => throw StateError('navigation is unavailable'),
    );
    final nonJson = buildInteractiveElementsResponse(
      const <Map<String, dynamic>>[],
      contextProvider: () => <String, Object?>{'value': Object()},
    );
    final empty = buildInteractiveElementsResponse(
      const <Map<String, dynamic>>[],
      contextProvider: () => const <String, Object?>{},
    );

    expect(throwing, isNot(contains('context')));
    expect(nonJson, isNot(contains('context')));
    expect(empty, isNot(contains('context')));
  });
}
