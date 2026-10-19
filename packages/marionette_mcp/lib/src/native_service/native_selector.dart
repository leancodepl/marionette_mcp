import 'package:marionette_mcp/src/native_service/native_connector.dart';
import 'package:marionette_mcp/src/native_service/native_exceptions.dart';

/// Criteria identifying native elements; all given fields must match (AND).
///
/// Shared by every `native_*` tool that targets an element, so they resolve
/// targets identically. Resolution rules (ambiguity, `index`) are described
/// in [selectElement] and docs/native-lane-decisions.md#d1.
final class NativeSelector {
  const NativeSelector({
    this.text,
    this.textContains,
    this.id,
    this.type,
    this.index,
  });

  /// Exact [NativeElement.text] (Android `text` / `content-desc`, iOS
  /// `label` / `value`; a text field's label or placeholder), compared
  /// verbatim.
  final String? text;

  /// Case-insensitive substring of the visible text.
  final String? textContains;

  /// Exact Android `resource-id` / iOS accessibility identifier.
  final String? id;

  /// Element class: either the full class (`android.widget.Button`,
  /// `XCUIElementTypeButton`) or its short name (`Button`).
  final String? type;

  /// Picks the n-th (0-based) of all matches, in UI-tree order.
  final int? index;

  /// Whether no matching criterion is set ([index] alone is not one).
  bool get isEmpty =>
      text == null && textContains == null && id == null && type == null;

  /// Whether [element] satisfies every criterion that is set.
  bool matches(NativeElement element) {
    if (text != null && element.text != text) return false;
    if (id != null && element.resourceId != id) return false;
    final needle = textContains?.toLowerCase();
    if (needle != null &&
        !(element.text?.toLowerCase().contains(needle) ?? false)) {
      return false;
    }
    final wantedType = type;
    if (wantedType != null && !_typeMatches(element.className, wantedType)) {
      return false;
    }
    return true;
  }

  /// Human-readable form for error messages, e.g. `text="OK", type="Button"`.
  String describe() => [
        if (text != null) 'text="${_escape(text!)}"',
        if (textContains != null) 'textContains="${_escape(textContains!)}"',
        if (id != null) 'id="$id"',
        if (type != null) 'type="$type"',
        if (index != null) 'index=$index',
      ].join(', ');

  static bool _typeMatches(String className, String wanted) =>
      className == wanted ||
      className.endsWith('.$wanted') ||
      className == 'XCUIElementType$wanted';

  static String _escape(String value) => value.replaceAll('\n', r'\n');
}

/// Maximum number of near misses listed when nothing matches.
const _maxSimilar = 5;

/// Resolves [selector] against [elements] (a UI tree in document order).
///
/// - All criteria are combined with AND.
/// - Only visible elements count ([NativeElement.isVisible]): Flutter on iOS
///   keeps off-screen nodes in the tree with zero size at (0, 0), and acting
///   on one would hit the top-left corner. A target that exists only off
///   screen fails with a hint to scroll (docs/native-lane-decisions.md#d16).
/// - With [NativeSelector.index], returns that match (0-based, tree order,
///   counting all matches); out of range throws
///   [NativeElementNotFoundException].
/// - Otherwise a single match is returned. With several, clickable elements
///   are preferred — a label inside a button usually matches too. If more
///   than one candidate remains, [NativeAmbiguousElementException] lists them
///   rather than guessing (docs/native-lane-decisions.md#d1).
/// - No match throws [NativeElementNotFoundException] with up to five
///   similar texts as a hint.
NativeElement selectElement(
  List<NativeElement> elements,
  NativeSelector selector,
) {
  final matches =
      elements.where((e) => e.isVisible && selector.matches(e)).toList();

  final index = selector.index;
  if (index != null) {
    if (index >= 0 && index < matches.length) return matches[index];
    throw NativeElementNotFoundException(
      '${selector.describe()} (${matches.length} '
      'match${matches.length == 1 ? '' : 'es'})',
    );
  }

  if (matches.length == 1) return matches.single;
  if (matches.isEmpty) {
    if (elements.any(selector.matches)) {
      throw NativeElementNotFoundException(
        '${selector.describe()} on screen',
        hint: 'It exists but is scrolled out of view. Bring it on screen '
            'with native_scroll (pass the same selector as the target).',
      );
    }
    throw NativeElementNotFoundException(
      selector.describe(),
      similar: _similarTexts(elements, selector),
    );
  }

  final clickable = matches.where((element) => element.clickable).toList();
  if (clickable.length == 1) return clickable.single;

  throw NativeAmbiguousElementException(selector.describe(), [
    for (final (i, element) in matches.indexed) '[$i] ${_describe(element)}',
  ]);
}

String _describe(NativeElement element) => [
      element.className,
      if (element.text != null)
        'text="${element.text!.replaceAll('\n', r'\n')}"',
      if (element.resourceId != null) 'id="${element.resourceId}"',
      'clickable=${element.clickable}',
      'bounds=(${element.bounds.x}, ${element.bounds.y}, '
          '${element.bounds.width}x${element.bounds.height})',
    ].join(' ');

/// Texts that nearly match the selector's text criteria: equal ignoring case
/// and whitespace, or containing / contained in the wanted text.
List<String> _similarTexts(
  List<NativeElement> elements,
  NativeSelector selector,
) {
  final wanted = selector.text ?? selector.textContains;
  if (wanted == null || wanted.trim().isEmpty) return const [];
  String normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  final needle = normalize(wanted);

  final similar = <String>[];
  for (final element in elements) {
    final text = element.text;
    if (text == null || similar.contains(text)) continue;
    final candidate = normalize(text);
    final isSimilar = candidate.contains(needle) ||
        (candidate.length >= 3 && needle.contains(candidate));
    if (isSimilar) {
      similar.add(text);
      if (similar.length == _maxSimilar) break;
    }
  }
  return similar;
}
