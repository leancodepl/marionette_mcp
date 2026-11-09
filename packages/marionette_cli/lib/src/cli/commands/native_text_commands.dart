import 'package:marionette_cli/src/cli/native_command.dart';
import 'package:marionette_cli/src/native_session_registry.dart';
import 'package:marionette_mcp/src/native_service/native_key.dart';
import 'package:marionette_mcp/src/native_service/native_service_context.dart';
import 'package:marionette_mcp/src/native_service/tools/keyboard_tools.dart';
import 'package:marionette_mcp/src/native_service/tools/text_tools.dart';
import 'package:mcp_dart/mcp_dart.dart';

class NativeEnterTextCommand extends NativeCommand {
  NativeEnterTextCommand(this.nativeRegistry) {
    argParser.addOption(
      'text',
      help: 'The text to type.',
      mandatory: true,
    );
    addSelectorOptions(textOption: 'label');
    argParser.addFlag(
      'clear',
      help: 'Empty the field before typing.',
      negatable: false,
    );
  }

  @override
  final NativeSessionRegistry nativeRegistry;

  @override
  String get name => 'native-enter-text';

  @override
  String get description =>
      'Type into a native field chosen by a selector, or — without one — '
      'into the field that has keyboard focus. Text is appended.';

  @override
  Map<String, dynamic> toolArguments() => NativeCommand.compact({
        'text': string('text'),
        ...selectorArgs(textOption: 'label', textKey: 'label'),
        'clear': flag('clear'),
      });

  @override
  Future<CallToolResult> execute(
    NativeServiceContext context,
    Map<String, dynamic> args,
  ) =>
      handleNativeEnterText(context, args);
}

class NativePressKeyCommand extends NativeCommand {
  NativePressKeyCommand(this.nativeRegistry) {
    argParser.addOption(
      'key',
      help: 'Key to press (back, recents and tab: Android only).',
      allowed: [for (final key in NativeKey.values) key.wireName],
      mandatory: true,
    );
  }

  @override
  final NativeSessionRegistry nativeRegistry;

  @override
  String get name => 'native-press-key';

  @override
  String get description => 'Press a system or hardware key on the device.';

  @override
  Map<String, dynamic> toolArguments() => {'key': string('key')};

  @override
  Future<CallToolResult> execute(
    NativeServiceContext context,
    Map<String, dynamic> args,
  ) =>
      handleNativePressKey(context, args);
}

class NativeHideKeyboardCommand extends NativeCommand {
  NativeHideKeyboardCommand(this.nativeRegistry);

  @override
  final NativeSessionRegistry nativeRegistry;

  @override
  String get name => 'native-hide-keyboard';

  @override
  String get description =>
      'Hide the software keyboard if it is shown and report whether it was.';

  @override
  Map<String, dynamic> toolArguments() => const {};

  @override
  Future<CallToolResult> execute(
    NativeServiceContext context,
    Map<String, dynamic> args,
  ) =>
      handleNativeHideKeyboard(context);
}
