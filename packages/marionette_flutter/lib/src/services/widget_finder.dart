import 'package:flutter/widgets.dart';
import 'package:marionette_flutter/src/binding/marionette_configuration.dart';
import 'package:marionette_flutter/src/binding/marionette_widget_adapter.dart';
import 'package:marionette_flutter/src/services/hit_test_utils.dart';
import 'package:marionette_flutter/src/services/widget_matcher.dart';

/// A link of an `ancestor_keys` chain that matches no element.
///
/// A typed exception so that a caller able to wait for the scope to be built
/// (`scroll_to`) can tell it apart from other failures. [toString] reads
/// exactly as the plain [Exception] it replaces did, since that text is what
/// reaches the agent.
class ScopeNotFoundException implements Exception {
  const ScopeNotFoundException({
    required this.key,
    required this.index,
    this.parentKey,
  });

  /// The key that matched no element.
  final String key;

  /// Its position in the `ancestor_keys` chain.
  final int index;

  /// The key of the link it was looked for inside, or null for the first one.
  final String? parentKey;

  @override
  String toString() {
    final within =
        parentKey == null ? ' in the widget tree' : ' inside "$parentKey"';
    return 'Exception: Scope element with key "$key" '
        '(ancestor_keys[$index]) not found$within';
  }
}

/// Finds widgets in the Flutter widget tree using various matching criteria.
class WidgetFinder {
  /// Finds the first element that matches the given [matcher].
  ///
  /// Traverses the widget tree starting from the root element and returns
  /// the first element whose widget matches the provided matcher. When
  /// [ancestors] is given, only the descendants of the element it resolves
  /// to are searched — never that element itself.
  ///
  /// The search does not reach past an element whose widget adapter claims
  /// its subtree with [MarionetteTraversalPolicy.ownSubtree], mirroring what
  /// `get_interactive_elements` lists.
  ///
  /// Returns null if no matching element is found.
  ///
  /// Throws when [ancestors] is given but cannot be resolved — a missing scope
  /// is a different failure from a missing target, so it is reported rather
  /// than folded into a null. See [resolveScopeRoot].
  Element? findElement(
    WidgetMatcher matcher,
    MarionetteConfiguration configuration, {
    List<KeyMatcher> ancestors = const [],
  }) {
    final scope = resolveScopeRoot(ancestors, configuration);
    return ancestors.isEmpty
        ? _search(matcher, scope, configuration, hittable: false)
        : _firstBelow(
            scope,
            (child) => _search(matcher, child, configuration, hittable: false),
          );
  }

  /// Finds the first element that matches the given [matcher] within the subtree
  /// rooted at the given [startElement].
  ///
  /// Unlike [findElement], this walks into subtrees that a widget adapter
  /// claims with [MarionetteTraversalPolicy.ownSubtree]. It is meant for
  /// finding an implementation detail inside an element that was already
  /// matched — such as the `EditableText` inside a matched text field — not
  /// for resolving what an agent asked for.
  ///
  /// Returns null if no matching element is found.
  Element? findElementFrom(
    WidgetMatcher matcher,
    Element? startElement,
    MarionetteConfiguration configuration,
  ) {
    return _search(
      matcher,
      startElement,
      configuration,
      hittable: false,
      respectOwnedSubtrees: false,
    );
  }

  /// Finds the first element that matches the given [matcher] and is hittable
  /// (i.e. can receive pointer events and is not behind a modal barrier).
  ///
  /// This should be used by tools that dispatch gestures (tap, enter_text) and
  /// by tools that ask whether the user can reach a widget (scroll_to), where
  /// matching a widget on a covered layer would result in a silent failure.
  /// Use [findElement] where a match the user cannot currently reach is still
  /// a valid answer.
  ///
  /// When [ancestors] is given, only the descendants of the element it
  /// resolves to are searched — never that element itself. Like
  /// [findElement], the search does not reach past an element whose widget
  /// adapter owns its subtree.
  ///
  /// Returns null if no matching element is found, and throws when
  /// [ancestors] is given but cannot be resolved — a missing scope is a
  /// different failure from a missing target, so it is reported rather than
  /// folded into a null. See [resolveScopeRoot].
  Element? findHittableElement(
    WidgetMatcher matcher,
    MarionetteConfiguration configuration, {
    List<KeyMatcher> ancestors = const [],
  }) {
    final scope = resolveScopeRoot(ancestors, configuration);
    return ancestors.isEmpty
        ? _search(matcher, scope, configuration, hittable: true)
        : _firstBelow(
            scope,
            (child) => _search(matcher, child, configuration, hittable: true),
          );
  }

  /// Resolves the element that an `ancestor_keys` chain limits a search to.
  ///
  /// [ancestors] is ordered outermost first and nests: each key is looked up
  /// strictly below the element the one before it resolved to, so a chain can
  /// reach a subtree whose own key repeats elsewhere, including on the level
  /// right above it. An empty chain resolves to the app's root element.
  ///
  /// Throws when a link matches no element: falling back to a tree-wide search
  /// would silently act on a different subtree than the one that was asked
  /// for. The message names the link that broke and where it was looked for.
  Element? resolveScopeRoot(
    List<KeyMatcher> ancestors,
    MarionetteConfiguration configuration,
  ) {
    final scope = tryResolveScope(ancestors, configuration);
    if (scope.missing case final missing?) {
      throw missing;
    }
    return scope.element;
  }

  /// Resolves as much of an `ancestor_keys` chain as is currently built,
  /// without throwing.
  ///
  /// [element] is what the deepest link that resolved points to — the app's
  /// root element when the chain is empty or not even its first link is
  /// built. [missing] is the first link that did not resolve, or null when the
  /// whole chain did. Callers that can wait for a scope to be built, such as
  /// `scroll_to` in a lazily built list, use this instead of
  /// [resolveScopeRoot].
  ({Element? element, ScopeNotFoundException? missing}) tryResolveScope(
    List<KeyMatcher> ancestors,
    MarionetteConfiguration configuration,
  ) {
    Element? scopeRoot = WidgetsBinding.instance.rootElement;

    for (var i = 0; i < ancestors.length; i++) {
      final found = _firstBelow(
        scopeRoot,
        (child) => _search(ancestors[i], child, configuration, hittable: false),
      );
      if (found == null) {
        return (
          element: scopeRoot,
          missing: ScopeNotFoundException(
            key: ancestors[i].keyValue,
            index: i,
            parentKey: i == 0 ? null : ancestors[i - 1].keyValue,
          ),
        );
      }
      scopeRoot = found;
    }

    return (element: scopeRoot, missing: null);
  }

  /// The first element below and including [startElement] that [matcher]
  /// matches, and that is hittable when [hittable] is set.
  ///
  /// Each visited element is described by the configured widget adapters at
  /// most once. With [respectOwnedSubtrees], the search does not descend into
  /// an element whose descriptor claims its subtree with
  /// [MarionetteTraversalPolicy.ownSubtree]: discovery lists such an element as
  /// one target and none of its internals, so matching must not reach past it
  /// to an internal widget the agent was never shown.
  Element? _search(
    WidgetMatcher matcher,
    Element? startElement,
    MarionetteConfiguration configuration, {
    required bool hittable,
    bool respectOwnedSubtrees = true,
  }) {
    if (startElement == null) {
      return null;
    }

    Element? found;

    void visitor(Element element) {
      if (found != null) {
        return;
      }
      MarionetteWidgetDescriptor? descriptor;
      var descriptorIsResolved = false;
      MarionetteWidgetDescriptor? describeWidget() {
        if (!descriptorIsResolved) {
          descriptor = configuration.describeWidget(element);
          descriptorIsResolved = true;
        }
        return descriptor;
      }

      if (matcher.matches(
            element,
            configuration,
            describeWidget: describeWidget,
          ) &&
          (!hittable || _isHittable(element, describeWidget()))) {
        found = element;
        return;
      }
      if (respectOwnedSubtrees &&
          describeWidget()?.traversalPolicy ==
              MarionetteTraversalPolicy.ownSubtree) {
        return;
      }
      element.visitChildren(visitor);
    }

    visitor(startElement);
    return found;
  }

  /// Whether a gesture dispatched at the center of [element] reaches it.
  ///
  /// An adapted composite may forward hit testing to a private render child,
  /// so for one a hit anywhere in its render subtree counts — still probed at
  /// its center, where the gesture will land.
  bool _isHittable(Element element, MarionetteWidgetDescriptor? descriptor) {
    return descriptor == null
        ? isElementHittable(element)
        : isElementHittableThroughSubtree(element);
  }

  /// The first result of [search] over the children of [parent], never
  /// [parent] itself, so a key repeated on adjacent levels names the inner one.
  Element? _firstBelow(
    Element? parent,
    Element? Function(Element child) search,
  ) {
    Element? found;
    parent?.visitChildren((child) {
      found ??= search(child);
    });
    return found;
  }
}
