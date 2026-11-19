import 'package:mcp_dart/mcp_dart.dart';

/// Tool result for arguments rejected before any device call is made.
CallToolResult invalidArguments(String message) => CallToolResult(
      isError: true,
      content: [TextContent(text: message)],
    );

/// Presence of a pair of arguments that must be passed together
/// (e.g. `x`/`y`).
enum ArgPairPresence { none, both, partial }

/// Reports whether both, none, or only one of [first] and [second] are
/// present in [args].
ArgPairPresence argPairPresence(
  Map<String, dynamic> args,
  String first,
  String second,
) {
  final hasFirst = args.containsKey(first);
  final hasSecond = args.containsKey(second);
  if (hasFirst && hasSecond) return ArgPairPresence.both;
  if (!hasFirst && !hasSecond) return ArgPairPresence.none;
  return ArgPairPresence.partial;
}

/// Reads a numeric argument as an int, or null when absent.
int? intArg(Map<String, dynamic> args, String key) =>
    (args[key] as num?)?.toInt();

/// Reads the enum argument [key], trimmed and case-insensitive, as one of
/// [values] matched by [wireName] (default: the enum name).
///
/// Returns [defaultValue] when the argument is absent, and null when it names
/// none of [values].
T? enumArg<T extends Enum>(
  Map<String, dynamic> args,
  String key,
  List<T> values, {
  T? defaultValue,
  String Function(T value) wireName = _enumName,
}) {
  final raw = args[key];
  if (raw == null) return defaultValue;
  if (raw is! String) return null;
  final normalized = raw.trim().toLowerCase();
  return values
      .where((value) => wireName(value).toLowerCase() == normalized)
      .firstOrNull;
}

String _enumName(Enum value) => value.name;
