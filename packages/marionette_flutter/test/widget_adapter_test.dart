import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/marionette_flutter.dart';
import 'package:marionette_flutter/src/binding/extensions/info_extensions.dart';
import 'package:marionette_flutter/src/services/element_tree_finder.dart';
import 'package:marionette_flutter/src/services/gesture_dispatcher.dart';
import 'package:marionette_flutter/src/services/text_input_simulator.dart';
import 'package:marionette_flutter/src/services/widget_finder.dart';

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

class _CountingCompositeButtonAdapter implements MarionetteWidgetAdapter {
  final calls = <Element, int>{};

  @override
  MarionetteWidgetDescriptor? describe(Element element) {
    calls.update(element, (count) => count + 1, ifAbsent: () => 1);
    if (element.widget is! _CompositeButton) return null;
    return const MarionetteWidgetDescriptor(
      type: 'CompositeButton',
      key: 'counted',
      traversalPolicy: MarionetteTraversalPolicy.ownSubtree,
    );
  }
}

class _NonJsonValue {}

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

class _DelegatingCompositeControl extends SingleChildRenderObjectWidget {
  const _DelegatingCompositeControl({super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _DelegatingCompositeRenderBox();
}

class _DelegatingCompositeRenderBox extends RenderProxyBox {
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final target = child;
    return target != null && target.hitTest(result, position: position);
  }
}

class _DelegatingCompositeAdapter implements MarionetteWidgetAdapter {
  const _DelegatingCompositeAdapter();

  @override
  MarionetteWidgetDescriptor? describe(Element element) {
    if (element.widget is! _DelegatingCompositeControl) {
      return null;
    }
    return const MarionetteWidgetDescriptor(
      type: 'DelegatingCompositeControl',
      key: 'delegating-control',
      actions: <String>['tap'],
      traversalPolicy: MarionetteTraversalPolicy.ownSubtree,
    );
  }
}

/// A composite whose center hits nothing of its own: the two gesture targets
/// sit at its ends, so only a descendant is hittable, and not where a gesture
/// on the composite lands.
class _SplitComposite extends StatelessWidget {
  const _SplitComposite({required this.onEnd});

  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 300,
      height: 48,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onEnd,
            child: const SizedBox(width: 40, height: 40),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onEnd,
            child: const SizedBox(width: 40, height: 40),
          ),
        ],
      ),
    );
  }
}

class _SplitCompositeAdapter implements MarionetteWidgetAdapter {
  const _SplitCompositeAdapter();

  @override
  MarionetteWidgetDescriptor? describe(Element element) {
    if (element.widget is! _SplitComposite) {
      return null;
    }
    return const MarionetteWidgetDescriptor(
      type: 'SplitComposite',
      key: 'split',
      traversalPolicy: MarionetteTraversalPolicy.ownSubtree,
    );
  }
}

/// A design-system text field that owns its subtree: only the composite is
/// shown to the agent, but `enter_text` still has to reach its EditableText.
class _CompositeField extends StatelessWidget {
  const _CompositeField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: 240, child: TextField(controller: controller));
  }
}

class _CompositeFieldAdapter implements MarionetteWidgetAdapter {
  const _CompositeFieldAdapter();

  @override
  MarionetteWidgetDescriptor? describe(Element element) {
    if (element.widget is! _CompositeField) {
      return null;
    }
    return const MarionetteWidgetDescriptor(
      type: 'CompositeField',
      role: 'textField',
      key: 'email',
      traversalPolicy: MarionetteTraversalPolicy.ownSubtree,
    );
  }
}

/// A repeated panel identified only through its descriptor key.
class _Panel extends StatelessWidget {
  const _Panel({required this.id, required this.child});

  final String id;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

class _PanelAdapter implements MarionetteWidgetAdapter {
  const _PanelAdapter();

  @override
  MarionetteWidgetDescriptor? describe(Element element) {
    final widget = element.widget;
    if (widget is! _Panel) {
      return null;
    }
    return MarionetteWidgetDescriptor(type: 'Panel', key: widget.id);
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

  test('descriptor rejects non-JSON values at the descriptor boundary', () {
    final descriptor = MarionetteWidgetDescriptor(
      type: 'CompositeButton',
      state: <String, Object?>{'bad': _NonJsonValue()},
    );

    expect(
      descriptor.toJson,
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.message,
          'message',
          contains('JSON-encodable'),
        ),
      ),
    );
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

  testWidgets('hittable matching describes each visited element at most once', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: _CompositeButton(label: 'Continue')),
      ),
    );
    final adapter = _CountingCompositeButtonAdapter();
    final countedConfiguration = MarionetteConfiguration(
      widgetAdapters: <MarionetteWidgetAdapter>[adapter],
    );
    final target = tester.element(find.byType(_CompositeButton));

    final found = WidgetFinder().findHittableElement(
      const KeyMatcher('counted'),
      countedConfiguration,
    );

    expect(found, target);
    expect(adapter.calls[target], 1);
    expect(adapter.calls.values, everyElement(1));
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

  testWidgets('a hittable descendant makes an adapted composite actionable', (
    tester,
  ) async {
    const delegatedConfiguration = MarionetteConfiguration(
      widgetAdapters: <MarionetteWidgetAdapter>[_DelegatingCompositeAdapter()],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: _DelegatingCompositeControl(
            child: ElevatedButton(
              onPressed: () {},
              child: const Text('Private gesture target'),
            ),
          ),
        ),
      ),
    );

    const treeFinder = ElementTreeFinder(delegatedConfiguration);
    final elements = treeFinder.findInteractiveElements();
    final matched = WidgetFinder().findHittableElement(
      const KeyMatcher('delegating-control'),
      delegatedConfiguration,
    );

    expect(
      elements.any(
        (element) => element['type'] == 'DelegatingCompositeControl',
      ),
      isTrue,
    );
    expect(matched?.widget, isA<_DelegatingCompositeControl>());
  });

  group('hit testing an adapted composite', () {
    testWidgets('a tap on a matched delegating composite reaches its handler',
        (tester) async {
      var presses = 0;
      const delegatedConfiguration = MarionetteConfiguration(
        widgetAdapters: <MarionetteWidgetAdapter>[
          _DelegatingCompositeAdapter(),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: _DelegatingCompositeControl(
                child: ElevatedButton(
                  onPressed: () => presses++,
                  child: const Text('Private gesture target'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.runAsync(
        () => GestureDispatcher().tap(
          const KeyMatcher('delegating-control'),
          WidgetFinder(),
          delegatedConfiguration,
        ),
      );
      await tester.pumpAndSettle();

      expect(presses, 1);
    });

    testWidgets(
        'a composite whose center hits nothing of its own is not actionable',
        (tester) async {
      var taps = 0;
      const splitConfiguration = MarionetteConfiguration(
        widgetAdapters: <MarionetteWidgetAdapter>[_SplitCompositeAdapter()],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(child: _SplitComposite(onEnd: () => taps++)),
          ),
        ),
      );

      final elements =
          const ElementTreeFinder(splitConfiguration).findInteractiveElements();
      final matched = WidgetFinder().findHittableElement(
        const KeyMatcher('split'),
        splitConfiguration,
      );

      // A hittable descendant is not enough: the gesture would be dispatched
      // at the composite's center, where nothing of it would receive it.
      expect(
        elements.any((element) => element['type'] == 'SplitComposite'),
        isFalse,
      );
      expect(matched, isNull);
      expect(taps, 0);
    });
  });

  group('matching an owned subtree', () {
    Widget panelWith(Widget child) {
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: KeyedSubtree(key: const ValueKey('panel'), child: child),
          ),
        ),
      );
    }

    testWidgets('does not reach an internal widget of an owning composite',
        (tester) async {
      await tester.pumpWidget(
        panelWith(const _CompositeButton(label: 'Continue')),
      );

      final internal = WidgetFinder().findHittableElement(
        const TypeStringMatcher('GestureDetector'),
        configuration,
        ancestors: const [KeyMatcher('panel')],
      );

      expect(internal, isNull);
    });

    testWidgets('reaches internal widgets under continueTraversal',
        (tester) async {
      const continueConfiguration = MarionetteConfiguration(
        widgetAdapters: <MarionetteWidgetAdapter>[
          _ContinueCompositeButtonAdapter(),
        ],
      );
      await tester.pumpWidget(
        panelWith(const _CompositeButton(label: 'Continue')),
      );

      final internal = WidgetFinder().findHittableElement(
        const TypeStringMatcher('GestureDetector'),
        continueConfiguration,
        ancestors: const [KeyMatcher('panel')],
      );

      expect(internal?.widget, isA<GestureDetector>());
    });

    testWidgets('enter_text still types into an owning composite field',
        (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      const fieldConfiguration = MarionetteConfiguration(
        widgetAdapters: <MarionetteWidgetAdapter>[_CompositeFieldAdapter()],
      );
      await tester.pumpWidget(
        panelWith(_CompositeField(controller: controller)),
      );

      await TextInputSimulator(WidgetFinder()).enterText(
        const KeyMatcher('email'),
        'jan@example.com',
        fieldConfiguration,
      );
      await tester.pump();

      expect(controller.text, 'jan@example.com');
    });
  });

  group('ancestor_keys through descriptor keys', () {
    Widget panels() {
      return MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              for (final id in ['panel-1', 'panel-2'])
                _Panel(
                  id: id,
                  child: Text('Go $id', key: const ValueKey('go')),
                ),
            ],
          ),
        ),
      );
    }

    const panelConfiguration = MarionetteConfiguration(
      widgetAdapters: <MarionetteWidgetAdapter>[_PanelAdapter()],
    );

    testWidgets('a descriptor key scopes a match', (tester) async {
      await tester.pumpWidget(panels());

      final matched = WidgetFinder().findHittableElement(
        const KeyMatcher('go'),
        panelConfiguration,
        ancestors: const [KeyMatcher('panel-2')],
      );

      expect(
        find.descendant(
          of: find.byWidgetPredicate(
            (widget) => widget is _Panel && widget.id == 'panel-2',
          ),
          matching: find.byWidget(matched!.widget),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a descriptor key scopes discovery', (tester) async {
      await tester.pumpWidget(panels());

      final elements = findScopedInteractiveElements(
        {
          'ancestor_keys': jsonEncode(['panel-2'])
        },
        elementTreeFinder: const ElementTreeFinder(panelConfiguration),
        widgetFinder: WidgetFinder(),
        configuration: panelConfiguration,
      );

      expect(elements.any((e) => e['text'] == 'Go panel-2'), isTrue);
      expect(elements.any((e) => e['text'] == 'Go panel-1'), isFalse);
    });
  });
}
