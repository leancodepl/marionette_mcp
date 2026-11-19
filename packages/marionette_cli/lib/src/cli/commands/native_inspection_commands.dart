import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:marionette_cli/src/cli/native_command.dart';
import 'package:marionette_mcp/src/native_service/native_service_context.dart';
import 'package:marionette_mcp/src/native_service/tools/inspection_tools.dart';
import 'package:marionette_mcp/src/native_service/tools/screenshot_tools.dart';
import 'package:marionette_mcp/src/session/session.dart';
import 'package:mcp_dart/mcp_dart.dart';

class NativeGetElementsCommand extends NativeCommand {
  NativeGetElementsCommand(super.nativeRegistry, super.environment) {
    addSelectorOptions(withIndex: false);
    argParser
      ..addFlag(
        'clickable-only',
        help: 'List only elements the platform reports as tappable.',
        negatable: false,
      )
      ..addFlag(
        'include-foreground-app',
        help: 'Report the foreground app (default: on).',
        defaultsTo: true,
      );
  }

  @override
  String get name => 'native-get-elements';

  @override
  String get description =>
      'List the native UI elements on screen (system dialogs, sheets, '
      'WebView content) as JSON.';

  @override
  Map<String, dynamic> toolArguments(ArgResults results) =>
      NativeCommand.compact({
        ...selectorArgs(results, withIndex: false),
        'clickableOnly': flag(results, 'clickable-only'),
        'includeForegroundApp': flag(results, 'include-foreground-app'),
      });

  @override
  Future<CallToolResult> execute(
    NativeServiceContext context,
    Map<String, dynamic> args,
  ) =>
      handleNativeGetElements(context, args);
}

class NativeWaitForCommand extends NativeCommand {
  NativeWaitForCommand(super.nativeRegistry, super.environment) {
    addSelectorOptions(withIndex: false);
    argParser
      ..addOption(
        'state',
        help: 'Wait until the element is visible or gone.',
        allowed: [for (final state in NativeWaitState.values) state.name],
        defaultsTo: NativeWaitState.visible.name,
      )
      ..addOption(
        'timeout-ms',
        help: 'Maximum wait (default $defaultWaitTimeoutMs).',
      )
      ..addOption(
        'interval-ms',
        help: 'Delay between reads (default $defaultWaitIntervalMs).',
      );
  }

  @override
  String get name => 'native-wait-for';

  @override
  String get description =>
      'Wait until a native element is visible (prints it) or gone. Exits 1 '
      'on timeout.';

  @override
  Map<String, dynamic> toolArguments(ArgResults results) =>
      NativeCommand.compact({
        ...selectorArgs(results, withIndex: false),
        'state': string(results, 'state'),
        'timeoutMs': integer(results, 'timeout-ms'),
        'intervalMs': integer(results, 'interval-ms'),
      });

  @override
  Future<CallToolResult> execute(
    NativeServiceContext context,
    Map<String, dynamic> args,
  ) =>
      handleNativeWaitFor(context, args);
}

class NativeTakeScreenshotCommand extends NativeCommand {
  NativeTakeScreenshotCommand(super.nativeRegistry, super.environment) {
    argParser.addOption(
      'output',
      abbr: 'o',
      help: 'Output file path for the PNG.',
      mandatory: true,
    );
  }

  @override
  String get name => 'native-take-screenshot';

  @override
  String get description =>
      'Save a screenshot of the whole device screen (system UI included).';

  /// Reads `--output` here, so a missing one fails before the device call.
  @override
  Map<String, dynamic> toolArguments(ArgResults results) {
    if (string(results, 'output') == null) {
      usageException('--output must not be empty.');
    }
    return const {};
  }

  @override
  Future<CallToolResult> execute(
    NativeServiceContext context,
    Map<String, dynamic> args,
  ) =>
      handleNativeTakeScreenshot(context);

  /// Keeps a copy in the report's `screenshots/` and returns the result
  /// `native_take_screenshot` gives with `inline: false`, so the report can
  /// cite it.
  @override
  CallToolResult recordInSession(CallToolResult result, Session session) {
    final image = result.content.whereType<ImageContent>().firstOrNull;
    if (image == null) return result;
    final saved = session.saveScreenshots([image.data]).single;
    stdout.writeln('Saved a copy in the session: $saved');
    final note = result.content.whereType<TextContent>().firstOrNull?.text;
    return CallToolResult(
      content: [
        TextContent(
          text:
              'Saved 1 screenshot(s):\n$saved${note == null ? '' : '\n$note'}',
        ),
      ],
    );
  }

  @override
  Future<void> saveImage(ImageContent image) async {
    final path = argResults!['output'] as String;
    File(path)
      ..createSync(recursive: true)
      ..writeAsBytesSync(base64Decode(image.data));
    stdout.writeln('Saved screenshot: $path');
  }
}
