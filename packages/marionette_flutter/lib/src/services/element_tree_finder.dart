import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsProperties;
import 'package:marionette_flutter/src/binding/marionette_configuration.dart';
import 'package:marionette_flutter/src/services/hit_test_utils.dart';

/// Finds and extracts interactive elements from the Flutter widget tree.
class ElementTreeFinder {
  const ElementTreeFinder(this.configuration);

  final MarionetteConfiguration configuration;

  /// Returns a list of interactive elements from the current widget tree.
  ///
  /// When [startElement] is given, only that element and its subtree are
  /// walked; it defaults to the app's root element. Callers scoping by
  /// `ancestor_keys` resolve the start element with
  /// `WidgetFinder.resolveScopeRoot`, which is also where a missing scope key
  /// fails loud — this class stays deliberately unaware of matchers.
  ///
  /// [compaction] reduces the per-element payload further (see
  /// [CompactionMode]). It overrides
  /// [MarionetteConfiguration.compaction] in both directions; pass null to use
  /// the app's configured default.
  List<Map<String, dynamic>> findInteractiveElements({
    Element? startElement,
    CompactionMode? compaction,
  }) {
    final elements = <Map<String, dynamic>>[];
    final rootElement = startElement ?? WidgetsBinding.instance.rootElement;

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
    final stops = configuration.shouldStopAtElement(element);
    final elementData = _extractElementData(
      element,
      widget,
      compaction: compaction,
      collapsesSubtree: stops,
    );

    if (elementData != null) {
      result.add(elementData);
    }

    if (stops) {
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
    required bool collapsesSubtree,
  }) {
    // Only process elements with render objects
    final renderObject = element.renderObject;
    if (renderObject == null) {
      return null;
    }

    // Check if this is an interactive or meaningful widget
    final isInteractive = configuration.isElementInteractive(element);
    final text = configuration.extractTextFromWidget(element);
    // Discovery-only Semantics fallback: if the standard matcher path yielded
    // no text, surface explicit accessibility annotations so agents can read
    // content rendered via inline-span trees, custom painters, or third-party
    // rich-text packages. Kept separate from extractTextFromWidget so that
    // TextMatcher (tap/scroll_to/enter_text) is not affected — otherwise a
    // Semantics(label: 'Save', child: ElevatedButton(...)) wrapper would
    // shadow the inner button.
    final discoverableText = text ??
        _extractSemanticsText(widget) ??
        (isInteractive && collapsesSubtree
            ? _extractMergedLabel(element)
            : null);
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
    final label = _semanticsLabel(widget.properties);
    final value = widget.properties.value;
    final hasValue = value != null && value.isNotEmpty;
    if (label != null && hasValue) return '$label: $value';
    if (label != null) return label;
    if (hasValue) return value;
    return null;
  }

  /// The nonempty `label` of [properties], or the text of its
  /// `attributedLabel`: `Semantics` takes one or the other, never both.
  static String? _semanticsLabel(SemanticsProperties properties) {
    final label = properties.label ?? properties.attributedLabel?.string;
    return label == null || label.isEmpty ? null : label;
  }

  /// A discovery-only label for a control traversal stops at, built from the
  /// text its children show and the explicit `Semantics` labels below it
  /// (such as an `Icon`'s `semanticLabel`), in tree order and joined line by
  /// line. It reads only what [RenderObject.visitChildrenForSemantics]
  /// reaches, which leaves out `ExcludeSemantics` (an `Icon`'s glyph),
  /// `Offstage`, the hidden children of an `IndexedStack` and the like.
  ///
  /// This is a hybrid of the visible text and the accessibility labels, not
  /// what Flutter's accessibility tree announces: a `Text` reports its
  /// visible text even when its `semanticsLabel` says something else.
  /// `tap(text:)` still matches each `Text` on its own, so a label merged from
  /// several children or taken from `Semantics` alone does not match.
  /// A control holding an [EditableText] is a field, whose `text` is its value
  /// rather than the label around it, so it gets none.
  String? _extractMergedLabel(Element element) {
    final root = element.renderObject;
    if (root == null || _containsEditableText(element)) return null;

    final announced = <RenderObject>{root};
    void collect(RenderObject child) {
      if (announced.add(child)) child.visitChildrenForSemantics(collect);
    }

    root.visitChildrenForSemantics(collect);

    final labels = <String>[];
    element.visitChildren(
      (child) => _collectLabels(child, announced, labels),
    );
    return labels.isEmpty ? null : labels.join('\n');
  }

  /// Adds the labels of [element] and its subtree to [labels] in tree order,
  /// skipping elements whose render object is not in [announced].
  void _collectLabels(
    Element element,
    Set<RenderObject> announced,
    List<String> labels,
  ) {
    if (!announced.contains(element.renderObject)) return;
    if (element.widget
        case Semantics(:final properties, :final excludeSemantics)) {
      if (_semanticsLabel(properties) case final label?) labels.add(label);
      if (excludeSemantics) return;
    }
    final text = configuration.extractTextFromWidget(element);
    if (text == null) {
      element.visitChildren(
        (child) => _collectLabels(child, announced, labels),
      );
      return;
    }
    final inlineText = _fillPlaceholders(element, text, announced);
    if (inlineText.isNotEmpty) labels.add(inlineText);
  }

  /// Replaces each placeholder a `WidgetSpan` leaves in [text] with the labels
  /// of the widget it embeds. [RichText] builds those widgets as its children,
  /// one per placeholder and in the same order.
  String _fillPlaceholders(
    Element textElement,
    String text,
    Set<RenderObject> announced,
  ) {
    if (!text.contains(_placeholder)) return text;

    final inlineLabels = <String>[];
    _findRichText(textElement)?.visitChildren((child) {
      final labels = <String>[];
      _collectLabels(child, announced, labels);
      inlineLabels.add(labels.join(' '));
    });
    final remaining = inlineLabels.iterator;
    return text.replaceAllMapped(
      _placeholder,
      (_) => remaining.moveNext() ? remaining.current : '',
    );
  }

  static final _placeholder =
      String.fromCharCode(PlaceholderSpan.placeholderCodeUnit);

  /// [element] itself when it is a [RichText], or the first [RichText] below
  /// it, such as the one a `Text` builds.
  static Element? _findRichText(Element element) {
    if (element.widget is RichText) return element;
    Element? richText;
    element.visitChildren((child) => richText ??= _findRichText(child));
    return richText;
  }

  /// Whether any descendant of [element] is an [EditableText], including one
  /// that the semantics walk skips, such as a field below
  /// `Semantics(excludeSemantics: true)`.
  static bool _containsEditableText(Element element) {
    var found = false;
    void visit(Element child) {
      if (found) return;
      if (child.widget is EditableText) {
        found = true;
      } else {
        child.visitChildren(visit);
      }
    }

    element.visitChildren(visit);
    return found;
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
