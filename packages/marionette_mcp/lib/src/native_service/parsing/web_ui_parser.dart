import 'package:marionette_mcp/src/native_service/native_models.dart';

const _htmlInteractiveTags = {
  'a',
  'button',
  'input',
  'textarea',
  'select',
  'summary',
};

const _htmlInteractiveRoles = {
  'button',
  'link',
  'textbox',
  'checkbox',
  'radio',
  'switch',
  'menuitem',
  'tab',
  'option',
  'searchbox',
};

const _htmlVoidTags = {
  'area',
  'base',
  'br',
  'col',
  'embed',
  'hr',
  'img',
  'input',
  'link',
  'meta',
  'param',
  'source',
  'track',
  'wbr',
};

final _htmlTagPattern = RegExp(
  r'''<([a-zA-Z][\w:-]*)((?:\s+[^>]*?)?)(/?)>''',
  multiLine: true,
);

final _htmlAttrPattern = RegExp(
  r'''([^\s=/>]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?''',
);

/// Parses an HTML document (ChromeDriver page source) into [NativeElement]s.
///
/// Keeps nodes that are typically interactive or carry a non-empty `id` /
/// visible label. Bounds are left at zero — the web connector resolves
/// geometry via WebDriver when needed; agents primarily match by `id` / text.
List<NativeElement> parseHtmlDom(String html) {
  final cleaned = html
      .replaceAll(
        RegExp(r'<script\b[^>]*>[\s\S]*?</script>', caseSensitive: false),
        '',
      )
      .replaceAll(
        RegExp(r'<style\b[^>]*>[\s\S]*?</style>', caseSensitive: false),
        '',
      );

  final elements = <NativeElement>[];
  for (final match in _htmlTagPattern.allMatches(cleaned)) {
    final tag = match.group(1)!.toLowerCase();
    if (tag.startsWith('!') ||
        tag == 'html' ||
        tag == 'head' ||
        tag == 'body') {
      continue;
    }

    final attrString = match.group(2) ?? '';
    final selfClosing = match.group(3) == '/' || _htmlVoidTags.contains(tag);
    final attributes = _parseHtmlAttributes(attrString);

    final role = (attributes['role'] ?? '').toLowerCase();
    final id = attributes['id'] ?? '';
    final text = _htmlLabelFor(tag, attributes, cleaned, match, selfClosing);
    final clickable = _htmlInteractiveTags.contains(tag) ||
        _htmlInteractiveRoles.contains(role) ||
        attributes.containsKey('onclick');

    if (!clickable && id.isEmpty && (text == null || text.isEmpty)) {
      continue;
    }

    if (tag == 'input' &&
        (attributes['type'] ?? '').toLowerCase() == 'hidden') {
      continue;
    }

    elements.add(
      NativeElement(
        className: tag,
        text: text,
        resourceId: id.isNotEmpty ? id : null,
        clickable: clickable,
        bounds: const NativeBounds(x: 0, y: 0, width: 0, height: 0),
      ),
    );
  }

  return elements;
}

Map<String, String> _parseHtmlAttributes(String attrString) {
  final attributes = <String, String>{};
  for (final match in _htmlAttrPattern.allMatches(attrString)) {
    final name = match.group(1)!.toLowerCase();
    if (name == '/' || name.startsWith('<')) continue;
    final value = match.group(2) ?? match.group(3) ?? match.group(4) ?? '';
    attributes[name] = _decodeHtmlEntities(value);
  }
  return attributes;
}

String? _htmlLabelFor(
  String tag,
  Map<String, String> attributes,
  String html,
  RegExpMatch openMatch,
  bool selfClosing,
) {
  for (final key in ['aria-label', 'placeholder', 'value', 'alt', 'title']) {
    final value = attributes[key] ?? '';
    if (value.trim().isNotEmpty) return value.trim();
  }

  if (selfClosing) return null;

  final closeTag = '</$tag>';
  final start = openMatch.end;
  final end = html.toLowerCase().indexOf(closeTag.toLowerCase(), start);
  if (end == -1 || end - start > 500) return null;

  final inner = html.substring(start, end);
  final text = inner
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (text.isEmpty) return null;
  return _decodeHtmlEntities(text);
}

String _decodeHtmlEntities(String value) {
  if (!value.contains('&')) return value;
  return value
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');
}
