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
