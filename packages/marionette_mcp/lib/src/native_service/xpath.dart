/// Quotes [value] as an XPath 1.0 string literal.
///
/// XPath 1.0 has no escape sequences, so a value containing both quote
/// characters is built with `concat()`. Typographic quotes (’, “) are
/// ordinary characters and need no special handling.
String xpathLiteral(String value) {
  if (!value.contains("'")) return "'$value'";
  if (!value.contains('"')) return '"$value"';

  final parts = value.split("'");
  return 'concat(${parts.map((part) => "'$part'").join(', "\'", ')})';
}
