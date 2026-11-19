import 'package:args/args.dart';
import 'package:marionette_cli/src/cli/native_command.dart';
import 'package:marionette_mcp/src/native_service/native_key.dart';
import 'package:marionette_mcp/src/native_service/native_service_context.dart';
import 'package:marionette_mcp/src/native_service/tools/keyboard_tools.dart';
import 'package:marionette_mcp/src/native_service/tools/text_tools.dart';
import 'package:mcp_dart/mcp_dart.dart';

class NativeEnterTextCommand extends NativeCommand {
  NativeEnterTextCommand(super.nativeRegistry, super.environment) {
    argParser.addOption(
      'text',
      help: 'The text to type.',
      mandatory: true,
    );
    addSelectorOptions(textOption: 'label');
    argParser.addFlag(
      'clear',
      help: 'Replace the field content instead of appending to it.',
      negatable: false,
    );
  }

  @override
  String get name => 'native-enter-text';

  @override
  String get description =>
      'Type into a native field chosen by a selector, or — without one — '
      'into the field that has keyboard focus. The text is appended to the '
      'field content; --clear replaces the content.';

  @override
  Map<String, dynamic> toolArguments(ArgResults results) =>
      NativeCommand.compact({
        'text': string(results, 'text', allowEmpty: true),
        ...selectorArgs(results, textOption: 'label', textKey: 'label'),
        'clear': flag(results, 'clear'),
      });

  @override
  Future<CallToolResult> execute(
    NativeServiceContext context,
    Map<String, dynamic> args,
  ) =>
      handleNativeEnterText(context, args);
}

class NativePressKeyCommand extends NativeCommand {
  NativePressKeyCommand(super.nativeRegistry, super.environment) {
    argParser.addOption(
      'key',
      help: 'Key to press (back, recents and tab: Android only).',
      allowed: [for (final key in NativeKey.values) key.wireName],
      mandatory: true,
    );
  }

  @override
  String get name => 'native-press-key';

  @override
  String get description => 'Press a system or hardware key on the device.';

  @override
  Map<String, dynamic> toolArguments(ArgResults results) =>
      {'key': string(results, 'key')};

  @override
  Future<CallToolResult> execute(
    NativeServiceContext context,
    Map<String, dynamic> args,
  ) =>
      handleNativePressKey(context, args);
}

class NativeHideKeyboardCommand extends NativeCommand {
  NativeHideKeyboardCommand(super.nativeRegistry, super.environment);

  @override
  String get name => 'native-hide-keyboard';

  @override
  String get description =>
      'Hide the software keyboard if it is shown and report whether it was.';

  @override
  Map<String, dynamic> toolArguments(ArgResults results) => const {};

  @override
  Future<CallToolResult> execute(
    NativeServiceContext context,
    Map<String, dynamic> args,
  ) =>
      handleNativeHideKeyboard(context);
}
