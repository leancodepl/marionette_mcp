import 'dart:convert';

import 'package:flutter/widgets.dart';

/// Controls how Marionette traverses below an adapted widget.
enum MarionetteTraversalPolicy {
  /// Continue visiting the widget's descendants.
  continueTraversal,

  /// Treat the widget as the logical owner of its complete subtree.
  ///
  /// This is useful for composite design-system controls whose implementation
  /// contains gesture detectors or other widgets that should not be exposed as
  /// separate interactive elements.
  ownSubtree,
}

/// A stable, JSON-serializable description of an application widget.
class MarionetteWidgetDescriptor {
  const MarionetteWidgetDescriptor({
    required this.type,
    this.role,
    this.key,
    this.text,
    this.value,
    this.hint,
    this.state = const <String, Object?>{},
    this.actions = const <String>[],
    this.properties = const <String, Object?>{},
    this.traversalPolicy = MarionetteTraversalPolicy.continueTraversal,
  });

  final String type;
  final String? role;
  final String? key;
  final String? text;
  final String? value;
  final String? hint;
  final Map<String, Object?> state;
  final List<String> actions;
  final Map<String, Object?> properties;
  final MarionetteTraversalPolicy traversalPolicy;

  Map<String, Object?> toJson() {
    final result = <String, Object?>{
      'type': type,
      if (role != null) 'role': role,
      if (key != null) 'key': key,
      if (text != null) 'text': text,
      if (value != null) 'value': value,
      if (hint != null) 'hint': hint,
      if (state.isNotEmpty) 'state': state,
      if (actions.isNotEmpty) 'actions': actions,
      if (properties.isNotEmpty) 'properties': properties,
    };
    assert(_debugAssertJsonEncodable(result));
    return result;
  }
}

bool _debugAssertJsonEncodable(Map<String, Object?> value) {
  try {
    jsonEncode(value);
  } catch (error) {
    throw ArgumentError(
      'MarionetteWidgetDescriptor fields must contain only JSON-encodable '
      'values: $error',
    );
  }
  return true;
}

/// Application or design-system bridge for Marionette introspection.
abstract interface class MarionetteWidgetAdapter {
  const MarionetteWidgetAdapter();

  /// Returns a descriptor when this adapter owns [element], or null otherwise.
  MarionetteWidgetDescriptor? describe(Element element);
}
