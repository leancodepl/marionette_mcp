import 'package:flutter/widgets.dart';
import 'package:marionette_flutter/src/binding/marionette_configuration.dart';

/// Abstract base class for matching widgets in the Flutter widget tree.
sealed class WidgetMatcher {
  const WidgetMatcher();

  /// Checks if the given [widget] matches this matcher's criteria.
  bool matches(Widget widget, MarionetteConfiguration configuration);

  /// Creates a matcher from a JSON map.
  /// If both 'key' and 'text' fields are present, 'key' takes precedence.
  static WidgetMatcher fromJson(Map<String, dynamic> json) {
    // Key has precedence over text
    if (json.containsKey('key')) {
      return KeyMatcher.fromJson(json);
    } else if (json.containsKey('text')) {
      return TextMatcher.fromJson(json);
    } else {
      throw ArgumentError(
        'Matcher JSON must contain either "key" or "text" field',
      );
    }
  }

  /// Converts this matcher to a JSON-serializable map.
  Map<String, dynamic> toJson();
}

/// Matches widgets by their ValueKey<String> key.
class KeyMatcher extends WidgetMatcher {
  const KeyMatcher(this.keyValue);

  factory KeyMatcher.fromJson(Map<String, dynamic> json) {
    return KeyMatcher(json['key'] as String);
  }

  final String keyValue;

  @override
  bool matches(Widget widget, MarionetteConfiguration configuration) {
    final key = widget.key;
    if (key is ValueKey<String>) {
      return key.value == keyValue;
    }
    return false;
  }

  @override
  Map<String, dynamic> toJson() {
    return <String, dynamic>{'key': keyValue};
  }
}

/// Matches widgets by their text content.
class TextMatcher extends WidgetMatcher {
  const TextMatcher(this.text);

  factory TextMatcher.fromJson(Map<String, dynamic> json) {
    return TextMatcher(json['text'] as String);
  }

  final String text;

  @override
  bool matches(Widget widget, MarionetteConfiguration configuration) {
    final extractedText = configuration.extractTextFromWidget(widget);
    return extractedText == text;
  }

  @override
  Map<String, dynamic> toJson() {
    return <String, dynamic>{'text': text};
  }
}

/// Matches widgets by their runtime type.
class TypeMatcher extends WidgetMatcher {
  const TypeMatcher(this.type);

  final Type type;

  @override
  bool matches(Widget widget, MarionetteConfiguration configuration) {
    return widget.runtimeType == type;
  }

  @override
  Map<String, dynamic> toJson() {
    throw UnsupportedError('TypeMatcher does not support JSON serialization');
  }
}
