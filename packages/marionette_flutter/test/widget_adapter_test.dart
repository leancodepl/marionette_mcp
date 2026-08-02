import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/marionette_flutter.dart';
import 'package:marionette_flutter/src/services/element_tree_finder.dart';

class _CompositeButton extends StatelessWidget {
  const _CompositeButton({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {},
      child: SizedBox(
        width: 160,
        height: 48,
        child: Center(child: Text(label)),
      ),
    );
  }
}

class _CompositeButtonAdapter implements MarionetteWidgetAdapter {
  const _CompositeButtonAdapter();

  @override
  MarionetteWidgetDescriptor? describe(Element element) {
    final widget = element.widget;
    if (widget is! _CompositeButton) {
      return null;
    }
    return MarionetteWidgetDescriptor(
      type: 'CompositeButton',
      role: 'button',
      key: 'continue',
      text: widget.label,
      state: const <String, Object?>{'enabled': true},
      actions: const <String>['tap'],
      properties: const <String, Object?>{'variant': 'primary'},
      traversalPolicy: MarionetteTraversalPolicy.ownSubtree,
    );
  }
}

class _ValueOnlyCompositeButtonAdapter implements MarionetteWidgetAdapter {
  const _ValueOnlyCompositeButtonAdapter();

  @override
  MarionetteWidgetDescriptor? describe(Element element) {
    if (element.widget is! _CompositeButton) {
      return null;
    }
    return const MarionetteWidgetDescriptor(
      type: 'CompositeButton',
      value: 'pending',
      traversalPolicy: MarionetteTraversalPolicy.ownSubtree,
    );
  }
}

class _FallbackCompositeButtonAdapter implements MarionetteWidgetAdapter {
  const _FallbackCompositeButtonAdapter();

  @override
  MarionetteWidgetDescriptor? describe(Element element) {
    if (element.widget is! _CompositeButton) {
      return null;
    }
    return const MarionetteWidgetDescriptor(type: 'FallbackButton');
  }
}

class _ContinueCompositeButtonAdapter implements MarionetteWidgetAdapter {
  const _ContinueCompositeButtonAdapter();

  @override
  MarionetteWidgetDescriptor? describe(Element element) {
    final widget = element.widget;
    if (widget is! _CompositeButton) {
      return null;
    }
    return MarionetteWidgetDescriptor(
      type: 'CompositeButton',
      text: widget.label,
    );
  }
}

void main() {
  const configuration = MarionetteConfiguration(
    widgetAdapters: <MarionetteWidgetAdapter>[_CompositeButtonAdapter()],
  );

  test('descriptor properties cannot overwrite stable fields', () {
    const descriptor = MarionetteWidgetDescriptor(
      type: 'CompositeButton',
      role: 'button',
      properties: <String, Object?>{
        'type': 'GestureDetector',
        'role': 'implementation-detail',
      },
    );

    expect(descriptor.toJson(), <String, Object?>{
      'type': 'CompositeButton',
      'role': 'button',
      'properties': <String, Object?>{
        'type': 'GestureDetector',
        'role': 'implementation-detail',
      },
    });
    expect(() => jsonEncode(descriptor.toJson()), returnsNormally);
  });

  testWidgets('adapter emits one logical target for a composite widget', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: _CompositeButton(label: 'Continue')),
      ),
    );

    const finder = ElementTreeFinder(configuration);
    final elements = finder.findInteractiveElements();

    final button = elements.singleWhere(
      (element) => element['type'] == 'CompositeButton',
    );
    expect(button['role'], 'button');
    expect(button['key'], 'continue');
    expect(button['text'], 'Continue');
    expect(button['state'], <String, Object?>{'enabled': true});
    expect(button['actions'], <String>['tap']);
    expect(button['properties'], <String, Object?>{'variant': 'primary'});
    expect(
      elements.any((element) => element['type'] == 'GestureDetector'),
      isFalse,
    );
    expect(elements.any((element) => element['type'] == 'Text'), isFalse);
  });

  testWidgets('descriptor text remains available to text matching', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: _CompositeButton(label: 'Continue')),
      ),
    );

    final element = tester.element(find.byType(_CompositeButton));
    expect(configuration.extractTextFromWidget(element), 'Continue');
    expect(
      const KeyMatcher('continue').matches(element, configuration),
      isTrue,
    );
    expect(
      const TypeStringMatcher(
        'CompositeButton',
      ).matches(element, configuration),
      isTrue,
    );
    expect(
      const TextMatcher('Continue').matches(element, configuration),
      isTrue,
    );
  });

  testWidgets('the first matching adapter wins', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: _CompositeButton(label: 'Continue')),
      ),
    );

    const orderedConfiguration = MarionetteConfiguration(
      widgetAdapters: <MarionetteWidgetAdapter>[
        _CompositeButtonAdapter(),
        _FallbackCompositeButtonAdapter(),
      ],
    );
    final element = tester.element(find.byType(_CompositeButton));

    expect(
      orderedConfiguration.describeWidget(element)?.type,
      'CompositeButton',
    );
  });

  testWidgets('continueTraversal keeps implementation descendants visible', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: _CompositeButton(label: 'Continue')),
      ),
    );

    const continueConfiguration = MarionetteConfiguration(
      widgetAdapters: <MarionetteWidgetAdapter>[
        _ContinueCompositeButtonAdapter(),
      ],
    );
    const finder = ElementTreeFinder(continueConfiguration);
    final elements = finder.findInteractiveElements();

    expect(
      elements.any((element) => element['type'] == 'CompositeButton'),
      isTrue,
    );
    expect(
      elements.any((element) => element['type'] == 'GestureDetector'),
      isTrue,
    );
    expect(elements.any((element) => element['type'] == 'Text'), isTrue);
  });

  testWidgets('descriptor value remains distinct from matchable text', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: _CompositeButton(label: 'Continue')),
      ),
    );

    const valueOnlyConfiguration = MarionetteConfiguration(
      widgetAdapters: <MarionetteWidgetAdapter>[
        _ValueOnlyCompositeButtonAdapter(),
      ],
    );
    const finder = ElementTreeFinder(valueOnlyConfiguration);
    final elements = finder.findInteractiveElements();
    final button = elements.singleWhere(
      (element) => element['type'] == 'CompositeButton',
    );
    final element = tester.element(find.byType(_CompositeButton));

    expect(button['value'], 'pending');
    expect(button, isNot(contains('text')));
    expect(
      const TextMatcher('pending').matches(element, valueOnlyConfiguration),
      isFalse,
    );
  });
}
