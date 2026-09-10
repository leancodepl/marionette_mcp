import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:marionette_flutter/src/binding/marionette_configuration.dart';
import 'package:marionette_flutter/src/services/hit_test_utils.dart';

/// Finds and extracts interactive elements from the Flutter widget tree.
class ElementTreeFinder {
  const ElementTreeFinder(this.configuration);

  final MarionetteConfiguration configuration;

  /// Returns a list of interactive elements from the current widget tree.
  ///
  /// [compaction] reduces the per-element payload further (see
  /// [CompactionMode]). It overrides
  /// [MarionetteConfiguration.compaction] in both directions; pass null to use
  /// the app's configured default.
  List<Map<String, dynamic>> findInteractiveElements({
    CompactionMode? compaction,
  }) {
    final elements = <Map<String, dynamic>>[];
    final rootElement = WidgetsBinding.instance.rootElement;

    if (rootElement != null) {
      _visitElement(
        rootElement,
        elements,
        compaction: compaction ?? configuration.compaction,
      );
    }

    return elements;
  }

  void _visitElement(
    Element element,
    List<Map<String, dynamic>> result, {
    required CompactionMode compaction,
  }) {
    final widget = element.widget;
    final elementData =
        _extractElementData(element, widget, compaction: compaction);

    if (elementData != null) {
      result.add(elementData);
    }

    if (configuration.shouldStopAtType(widget.runtimeType)) {
      return;
    }

    element.visitChildren((child) {
      _visitElement(child, result, compaction: compaction);
    });
  }

  Map<String, dynamic>? _extractElementData(
    Element element,
    Widget widget, {
    required CompactionMode compaction,
  }) {
    // Only process elements with render objects
    final renderObject = element.renderObject;
    if (renderObject == null) {
      return null;
    }

    // Check if this is an interactive or meaningful widget
    final isInteractive = configuration.isInteractiveWidgetType(
      widget.runtimeType,
    );
    final text = configuration.extractTextFromWidget(element);
    // Discovery-only Semantics fallback: if the standard matcher path yielded
    // no text, surface explicit accessibility annotations so agents can read
    // content rendered via inline-span trees, custom painters, or third-party
    // rich-text packages. Kept separate from extractTextFromWidget so that
    // TextMatcher (tap/scroll_to/enter_text) is not affected — otherwise a
    // Semantics(label: 'Save', child: ElevatedButton(...)) wrapper would
    // shadow the inner button.
    final discoverableText = text ?? _extractSemanticsText(widget);
    final keyValue = _extractKeyValue(widget.key);
    final identifierValue = _extractIdentifier(widget);

    if (!isInteractive &&
        discoverableText == null &&
        keyValue == null &&
        identifierValue == null) {
      return null;
    }

    // Only return widgets that can be hit
    if (!isElementHittable(element)) {
      return null;
    }

    final compact = compaction == CompactionMode.compact;
    final properties = DiagnosticPropertiesBuilder();
    widget.debugFillProperties(properties);
    // Keep only primitive-valued properties, dropping the object blobs
    // (ButtonStyle, TextStyle, InputDecoration, Color, controllers, FocusNode)
    // and callbacks that dominate the payload. Filtering by value type —
    // rather than by DiagnosticsNode subtype — is necessary because widgets are
    // inconsistent: e.g. TextField declares `enabled`/`obscureText` as generic
    // DiagnosticsProperty<bool> while ElevatedButton uses FlagProperty. Exact
    // retained fields therefore vary per widget.
    final data = Map<String, Object>.fromEntries(
      properties.properties
          .where((p) =>
              p.name != null &&
              p.value != null &&
              _isPrimitive(p.value) &&
              !(compact && _isCompactNoise(p.name!)))
          .map(
            (p) => MapEntry(p.name!, p.value.toString()),
          ),
    );

    data['type'] = widget.runtimeType.toString();

    if (keyValue != null) {
      data['key'] = keyValue;
    }

    if (identifierValue != null) {
      data['identifier'] = identifierValue;
    }

    if (discoverableText != null) {
      data['text'] = discoverableText;
      // `Text` also declares its string as `data`, so an element would carry
      // the same words twice.
      if (compact && data['data'] == discoverableText) {
        data.remove('data');
      }
    }

    // The InputDecoration blob never survives the primitive filter, but it
    // carries a keyless text field's only human-readable handle (`text` holds
    // the entered value, empty for a blank field). Surface the label/hint so
    // such fields stay identifiable. TextFormField has no public `decoration`,
    // so this only applies to TextField.
    if (widget is TextField) {
      final label = widget.decoration?.labelText ?? widget.decoration?.hintText;
      if (label != null && label.isNotEmpty) {
        data['label'] = label;
      }
    }

    // Get position and size if available
    if (renderObject is RenderBox && renderObject.hasSize) {
      try {
        final offset = renderObject.localToGlobal(Offset.zero);
        final size = renderObject.size;
        // Logical pixels, and the agent uses them to reason about position and
        // to tap by coordinate — neither needs the sixteen significant digits a
        // double prints (`411.42857142857144`).
        data['bounds'] = compact
            ? {
                'x': offset.dx.round(),
                'y': offset.dy.round(),
                'width': size.width.round(),
                'height': size.height.round(),
              }
            : {
                'x': offset.dx,
                'y': offset.dy,
                'width': size.width,
                'height': size.height,
              };
      } catch (_) {
        // Ignore if we can't get bounds
      }
    }

    // Check visibility. Every element in the list is on screen in the ordinary
    // case, so in compact mode this is reported only when it is not — absence
    // means visible, and the exception stays impossible to miss.
    final visible = _isElementVisible(element);
    if (!compact || !visible) {
      data['visible'] = visible;
    }

    return data;
  }

  /// Whether [value] is a primitive worth keeping in the property dump.
  static bool _isPrimitive(Object? value) =>
      value is bool || value is num || value is String || value is Enum;

  /// Properties that survive the primitive filter but say nothing an agent can
  /// act on: they describe how text or gestures are laid out and rendered, and
  /// no interaction tool reads them (`tap`/`enter_text`/`scroll_to`/`swipe`
  /// match on key, identifier, text, type or coordinates). They are also the
  /// ones that dominate what is left once the object blobs are gone — every
  /// `Text` in a list carries several of them.
  static const _renderingDetails = {
    'startBehavior',
    'textAlign',
    'textDirection',
    'softWrap',
    'overflow',
    'textWidthBasis',
  };

  /// Text-style primitives that leak into a `Text` element unprefixed, because
  /// `Text` forwards its `style` to the same [DiagnosticPropertiesBuilder]. The
  /// rest of `TextStyle` is object-valued and never survives the primitive
  /// filter, so only these need naming.
  static const _textStylePrimitives = {
    'inherit',
    'family',
    'size',
    'letterSpacing',
    'height',
    'baseline',
    'leadingDistribution',
  };

  static bool _isCompactNoise(String name) =>
      _renderingDetails.contains(name) || _textStylePrimitives.contains(name);

  String? _extractKeyValue(Key? key) {
    if (key is ValueKey<String>) {
      return key.value;
    }
    return null;
  }

  /// Extracts the accessibility `identifier` from a `Semantics` widget.
  ///
  /// Unlike `label`/`value` (see [_extractSemanticsText]), the `identifier` is
  /// a unique, machine-readable handle that lives only on the `Semantics`
  /// widget, so it is both surfaced for discovery here and consulted by the
  /// matcher path (see `IdentifierMatcher`). Returns null when the widget is
  /// not a `Semantics` or carries no identifier, keeping the output quiet by
  /// default.
  static String? _extractIdentifier(Widget widget) {
    if (widget is! Semantics) return null;
    final identifier = widget.properties.identifier;
    if (identifier == null || identifier.isEmpty) return null;
    return identifier;
  }

  /// Discovery-only fallback: extracts the accessibility annotation from a
  /// `Semantics` widget.
  ///
  /// Combines `label` and `value` the way screen readers announce them
  /// (`'label: value'`) so widgets that set both — e.g.
  /// `Semantics(label: 'Volume', value: '70%')` — keep their dynamic state
  /// in the discovery output instead of dropping `value` when `label` is
  /// also present. Falls back to whichever field is non-empty when only one
  /// is set, and returns null when neither carries content.
  ///
  /// This is intentionally kept out of [MarionetteConfiguration.extractTextFromWidget]
  /// so that [TextMatcher] is not affected by Semantics wrappers — see the
  /// class-level dartdoc on `MarionetteConfiguration` for the rationale.
  static String? _extractSemanticsText(Widget widget) {
    if (widget is! Semantics) return null;
    final label = widget.properties.label;
    final value = widget.properties.value;
    final hasLabel = label != null && label.isNotEmpty;
    final hasValue = value != null && value.isNotEmpty;
    if (hasLabel && hasValue) return '$label: $value';
    if (hasLabel) return label;
    if (hasValue) return value;
    return null;
  }

  /// Checks if the element is currently visible in the view it is mounted in.
  ///
  /// Measures against that view rather than the first one the platform knows
  /// about: an app driven by the desktop windowing API renders into a view
  /// other than the implicit one, and [RenderObject.localToGlobal] is relative
  /// to the owning view anyway.
  bool _isElementVisible(Element element) {
    final renderObject = element.renderObject;
    if (renderObject == null || !renderObject.attached) {
      return false;
    }

    if (renderObject is RenderBox) {
      if (!renderObject.hasSize) {
        return false;
      }

      final size = renderObject.size;
      if (size.width <= 0 || size.height <= 0) {
        return false;
      }

      try {
        final offset = renderObject.localToGlobal(Offset.zero);
        final view = viewOf(element);
        if (view == null) {
          return true;
        }
        final screenSize = view.physicalSize / view.devicePixelRatio;

        final isOnScreen = offset.dx + size.width >= 0 &&
            offset.dy + size.height >= 0 &&
            offset.dx < screenSize.width &&
            offset.dy < screenSize.height;

        return isOnScreen;
      } catch (_) {
        return true;
      }
    }

    return true;
  }
}
