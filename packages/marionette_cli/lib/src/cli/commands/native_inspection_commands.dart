import 'dart:convert';
import 'dart:io';

import 'package:marionette_cli/src/cli/native_command.dart';
import 'package:marionette_cli/src/native_session_registry.dart';
import 'package:marionette_mcp/src/native_service/native_service_context.dart';
import 'package:marionette_mcp/src/native_service/tools/inspection_tools.dart';
import 'package:marionette_mcp/src/native_service/tools/screenshot_tools.dart';
import 'package:mcp_dart/mcp_dart.dart';

class NativeGetElementsCommand extends NativeCommand {
  NativeGetElementsCommand(this.nativeRegistry) {
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
  final NativeSessionRegistry nativeRegistry;

  @override
  String get name => 'native-get-elements';

  @override
  String get description =>
      'List the native UI elements on screen (system dialogs, sheets, '
      'WebView content) as JSON.';

  @override
  Map<String, dynamic> toolArguments() => NativeCommand.compact({
        ...selectorArgs(withIndex: false),
        'clickableOnly': flag('clickable-only'),
        'includeForegroundApp': flag('include-foreground-app'),
      });

  @override
  Future<CallToolResult> execute(
    NativeServiceContext context,
    Map<String, dynamic> args,
  ) =>
      handleNativeGetElements(context, args);
}

class NativeWaitForCommand extends NativeCommand {
  NativeWaitForCommand(this.nativeRegistry) {
    addSelectorOptions(withIndex: false);
    argParser
      ..addOption(
        'state',
        help: 'Wait until the element is visible or gone.',
        allowed: [for (final state in NativeWaitState.values) state.name],
        defaultsTo: NativeWaitState.visible.name,
      )
      ..addOption('timeout-ms', help: 'Maximum wait (default 10000).')
      ..addOption('interval-ms', help: 'Delay between reads (default 500).');
  }

  @override
  final NativeSessionRegistry nativeRegistry;

  @override
  String get name => 'native-wait-for';

  @override
  String get description =>
      'Wait until a native element is visible (prints it) or gone. Exits 1 '
      'on timeout.';

  @override
  Map<String, dynamic> toolArguments() => NativeCommand.compact({
        ...selectorArgs(withIndex: false),
        'state': string('state'),
        'timeoutMs': integer('timeout-ms'),
        'intervalMs': integer('interval-ms'),
      });

  @override
  Future<CallToolResult> execute(
    NativeServiceContext context,
    Map<String, dynamic> args,
  ) =>
      handleNativeWaitFor(context, args);
}

class NativeTakeScreenshotCommand extends NativeCommand {
  NativeTakeScreenshotCommand(this.nativeRegistry) {
    argParser.addOption(
      'output',
      abbr: 'o',
      help: 'Output file path for the PNG.',
      mandatory: true,
    );
  }

  @override
  final NativeSessionRegistry nativeRegistry;

  @override
  String get name => 'native-take-screenshot';

  @override
  String get description =>
      'Save a screenshot of the whole device screen (system UI included).';

  @override
  Map<String, dynamic> toolArguments() => const {};

  @override
  Future<CallToolResult> execute(
    NativeServiceContext context,
    Map<String, dynamic> args,
  ) =>
      handleNativeTakeScreenshot(context);

  @override
  Future<void> saveImage(ImageContent image) async {
    final path = argResults!['output'] as String;
    File(path)
      ..createSync(recursive: true)
      ..writeAsBytesSync(base64Decode(image.data));
    stdout.writeln('Saved screenshot: $path');
  }
}
