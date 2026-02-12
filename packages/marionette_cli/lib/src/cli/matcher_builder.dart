/// Builds a widget matcher map from CLI arguments.
///
/// Accepts named args like --key, --text, --type, --x, --y and
/// constructs the matcher map expected by [VmServiceConnector].
Map<String, dynamic> buildMatcherFromArgs({
  String? key,
  String? text,
  String? type,
  num? x,
  num? y,
}) {
  final matcher = <String, dynamic>{};
  if (key != null) matcher['key'] = key;
  if (text != null) matcher['text'] = text;
  if (type != null) matcher['type'] = type;
  if (x != null) matcher['x'] = x;
  if (y != null) matcher['y'] = y;
  return matcher;
}
