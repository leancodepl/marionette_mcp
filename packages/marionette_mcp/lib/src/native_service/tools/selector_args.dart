import 'package:marionette_mcp/src/native_service/native_selector.dart';
import 'package:mcp_dart/mcp_dart.dart';

/// JSON schema properties of a [NativeSelector] for a tool's input.
///
/// [textKey] names the exact-text criterion (`native_enter_text` uses
/// `label`, because its `text` is the string to type). [withIndex] adds
/// `index`; tools that only test presence omit it.
Map<String, JsonSchema> nativeSelectorProperties({
  String textKey = 'text',
  bool withIndex = true,
}) =>
    {
      textKey: JsonSchema.string(
        description: 'Exact visible text (Android text/content-desc, iOS '
            'label/value; for a text field its label or placeholder, not '
            'its content) as returned in "text" by native_get_elements.',
      ),
      'textContains': JsonSchema.string(
        description: 'Case-insensitive part of the visible text.',
      ),
      'id': JsonSchema.string(
        description: 'Exact Android resource-id or iOS accessibility id, as '
            'returned in the "id" field of native_get_elements.',
      ),
      'type': JsonSchema.string(
        description: 'Element class, full (android.widget.Button, '
            'XCUIElementTypeButton) or short (Button).',
      ),
      if (withIndex)
        'index': JsonSchema.integer(
          description: 'Pick the n-th match (0-based, UI-tree order) when '
              'several elements match. Required when the selector is '
              'ambiguous.',
        ),
    };

/// Builds a [NativeSelector] from tool [args]; see
/// [nativeSelectorProperties] for [textKey].
NativeSelector nativeSelectorFromArgs(
  Map<String, dynamic> args, {
  String textKey = 'text',
}) =>
    NativeSelector(
      text: args[textKey] as String?,
      textContains: args['textContains'] as String?,
      id: args['id'] as String?,
      type: args['type'] as String?,
      index: (args['index'] as num?)?.toInt(),
    );

/// Sentence for tool descriptions explaining how selectors resolve.
const nativeSelectorRules =
    'All given selector fields must match. If several elements match, '
    'clickable ones are preferred; if that still leaves more than one, the '
    'call fails and lists the candidates — pass index or a more specific '
    'selector instead of guessing.';
