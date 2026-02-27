import 'package:flutter/material.dart';
import 'package:marionette_flutter/src/binding/marionette_configuration.dart';
import 'package:marionette_flutter/src/services/widget_finder.dart';
import 'package:marionette_flutter/src/services/widget_matcher.dart';

/// Simulates text input into text fields.
class TextInputSimulator {
  const TextInputSimulator(this._widgetFinder);

  final WidgetFinder _widgetFinder;

  /// Enters text into a text field identified by the given matcher.
  Future<void> enterText(
    WidgetMatcher matcher,
    String text,
    MarionetteConfiguration configuration,
  ) async {
    final element = _widgetFinder.findElement(matcher, configuration);

    if (element == null) {
      throw Exception('Element matching ${matcher.toJson()} not found');
    }

    // Try to find the EditableText widget within the matched element's subtree
    final editableTextElement = _widgetFinder.findElementFrom(
      const TypeMatcher(EditableText),
      element,
      configuration,
    );

    if (editableTextElement != null) {
      final editableTextState =
          (editableTextElement as StatefulElement).state as EditableTextState;

      editableTextState.requestKeyboard();

      // Route changes through EditableTextState so TextField/TextFormField
      // callbacks (for example onChanged) run like real keyboard input.
      editableTextState.updateEditingValue(
        TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        ),
      );

      // Schedule a frame to ensure the UI updates
      WidgetsBinding.instance.scheduleFrame();
      return;
    }

    throw Exception(
      'Could not find an EditableText widget within the subtree of matcher ${matcher.toJson()}',
    );
  }
}
