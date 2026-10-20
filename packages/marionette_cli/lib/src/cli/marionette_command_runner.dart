import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:marionette_cli/src/cli/commands/doctor_command.dart';
import 'package:marionette_cli/src/cli/commands/double_tap_command.dart';
import 'package:marionette_cli/src/cli/commands/enter_text_command.dart';
import 'package:marionette_cli/src/cli/commands/get_interactive_elements_command.dart';
import 'package:marionette_cli/src/cli/commands/get_logs_command.dart';
import 'package:marionette_cli/src/cli/commands/help_ai_command.dart';
import 'package:marionette_cli/src/cli/commands/hot_reload_command.dart';
import 'package:marionette_cli/src/cli/commands/hot_restart_command.dart';
import 'package:marionette_cli/src/cli/commands/long_press_command.dart';
import 'package:marionette_cli/src/cli/commands/list_command.dart';
import 'package:marionette_cli/src/cli/commands/mcp_command.dart';
import 'package:marionette_cli/src/cli/commands/native_bridge_commands.dart';
import 'package:marionette_cli/src/cli/commands/native_device_commands.dart';
import 'package:marionette_cli/src/cli/commands/native_gesture_commands.dart';
import 'package:marionette_cli/src/cli/commands/native_inspection_commands.dart';
import 'package:marionette_cli/src/cli/commands/native_session_commands.dart';
import 'package:marionette_cli/src/cli/commands/native_text_commands.dart';
import 'package:marionette_cli/src/cli/commands/pinch_zoom_command.dart';
import 'package:marionette_cli/src/cli/commands/record_video_command.dart';
import 'package:marionette_cli/src/cli/commands/press_back_button_command.dart';
import 'package:marionette_cli/src/cli/commands/press_key_command.dart';
import 'package:marionette_cli/src/cli/commands/register_command.dart';
import 'package:marionette_cli/src/cli/commands/scroll_to_command.dart';
import 'package:marionette_cli/src/cli/commands/secondary_tap_command.dart';
import 'package:marionette_cli/src/cli/commands/swipe_command.dart';
import 'package:marionette_cli/src/cli/commands/take_screenshots_command.dart';
import 'package:marionette_cli/src/cli/commands/tap_command.dart';
import 'package:marionette_cli/src/cli/commands/unregister_command.dart';
import 'package:marionette_cli/src/cli/native_doctor.dart';
import 'package:marionette_cli/src/instance_registry.dart';
import 'package:marionette_cli/src/native_session_registry.dart';

class MarionetteCommandRunner extends CommandRunner<int> {
  MarionetteCommandRunner({
    InstanceRegistry? registry,
    NativeSessionRegistry? nativeRegistry,
    NativeDoctor? nativeDoctor,
  })  : _registry = registry ?? InstanceRegistry(),
        _nativeRegistry = nativeRegistry ?? NativeSessionRegistry(),
        super(
          'marionette',
          'CLI for multi-instance Flutter app interaction via Marionette.',
        ) {
    argParser
      ..addOption(
        'instance',
        abbr: 'i',
        help: 'Name of the Flutter app instance to target.',
      )
      ..addOption(
        'uri',
        help: 'VM service WebSocket URI (e.g., ws://127.0.0.1:8181/ws). '
            'Bypasses the instance registry. Mutually exclusive with --instance.',
      )
      ..addOption(
        'timeout',
        help: 'Connection timeout in seconds.',
        defaultsTo: '5',
      )
      ..addOption(
        'native-session',
        help: 'Name of the native session for native-* commands.',
        defaultsTo: 'default',
      );

    addCommand(RegisterCommand(_registry));
    addCommand(UnregisterCommand(_registry));
    addCommand(ListCommand(_registry));
    addCommand(ElementsCommand(_registry));
    addCommand(TapCommand(_registry));
    addCommand(SecondaryTapCommand(_registry));
    addCommand(DoubleTapCommand(_registry));
    addCommand(LongPressCommand(_registry));
    addCommand(PinchZoomCommand(_registry));
    addCommand(SwipeCommand(_registry));
    addCommand(EnterTextCommand(_registry));
    addCommand(PressKeyCommand(_registry));
    addCommand(PressBackButtonCommand(_registry));
    addCommand(ScrollToCommand(_registry));
    addCommand(ScreenshotCommand(_registry));
    addCommand(RecordVideoCommand(_registry));
    addCommand(LogsCommand(_registry));
    addCommand(HotReloadCommand(_registry));
    addCommand(HotRestartCommand(_registry));
    addCommand(
      DoctorCommand(
        _registry,
        nativeDoctor ?? NativeDoctor(registry: _nativeRegistry),
      ),
    );
    addCommand(NativeConnectCommand(_nativeRegistry));
    addCommand(NativeDisconnectCommand(_nativeRegistry));
    addCommand(NativeSessionsCommand(_nativeRegistry));
    addCommand(NativeGetElementsCommand(_nativeRegistry));
    addCommand(NativeWaitForCommand(_nativeRegistry));
    addCommand(NativeTakeScreenshotCommand(_nativeRegistry));
    addCommand(NativeDeviceInfoCommand(_nativeRegistry));
    addCommand(NativeTapCommand(_nativeRegistry));
    addCommand(NativeDoubleTapCommand(_nativeRegistry));
    addCommand(NativeLongPressCommand(_nativeRegistry));
    addCommand(NativePinchCommand(_nativeRegistry));
    addCommand(NativeSwipeCommand(_nativeRegistry));
    addCommand(NativeScrollCommand(_nativeRegistry));
    addCommand(NativeEnterTextCommand(_nativeRegistry));
    addCommand(NativePressKeyCommand(_nativeRegistry));
    addCommand(NativeHideKeyboardCommand(_nativeRegistry));
    addCommand(NativePermissionsCommand(_nativeRegistry));
    addCommand(NativeOpenUrlCommand(_nativeRegistry));
    addCommand(NativeAppCommand(_nativeRegistry));
    addCommand(NativeNotificationsCommand(_nativeRegistry));
    addCommand(NativeSetOrientationCommand(_nativeRegistry));
    addCommand(NativeSetLocationCommand(_nativeRegistry));
    addCommand(NativeBiometricsCommand(_nativeRegistry));
    addCommand(NativeMapFlutterRectCommand(_nativeRegistry, _registry));
    addCommand(HelpAiCommand());
    addCommand(McpCommand());
  }

  final InstanceRegistry _registry;
  final NativeSessionRegistry _nativeRegistry;

  @override
  Future<int> run(Iterable<String> args) async {
    try {
      final result = await super.run(args);
      return result ?? 0;
    } on UsageException catch (e) {
      stderr
        ..writeln(e.message)
        ..writeln()
        ..writeln(e.usage);
      return 64;
    } on FormatException catch (e) {
      stderr.writeln(e.message);
      return 64;
    }
  }

  @override
  Future<int?> runCommand(ArgResults topLevelResults) async {
    if (topLevelResults.command == null) {
      printUsage();
      return 0;
    }
    return super.runCommand(topLevelResults);
  }
}
