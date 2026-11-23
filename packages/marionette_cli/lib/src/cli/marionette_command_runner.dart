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
import 'package:marionette_cli/src/cli/commands/native_gesture_commands.dart';
import 'package:marionette_cli/src/cli/commands/native_inspection_commands.dart';
import 'package:marionette_cli/src/cli/commands/native_notification_commands.dart';
import 'package:marionette_cli/src/cli/commands/native_session_commands.dart';
import 'package:marionette_cli/src/cli/commands/native_text_commands.dart';
import 'package:marionette_cli/src/cli/commands/pinch_zoom_command.dart';
import 'package:marionette_cli/src/cli/commands/record_video_command.dart';
import 'package:marionette_cli/src/cli/commands/press_back_button_command.dart';
import 'package:marionette_cli/src/cli/commands/press_key_command.dart';
import 'package:marionette_cli/src/cli/commands/register_command.dart';
import 'package:marionette_cli/src/cli/commands/scroll_to_command.dart';
import 'package:marionette_cli/src/cli/commands/secondary_tap_command.dart';
import 'package:marionette_cli/src/cli/commands/set_device_config_command.dart';
import 'package:marionette_cli/src/cli/commands/swipe_command.dart';
import 'package:marionette_cli/src/cli/commands/take_screenshots_command.dart';
import 'package:marionette_cli/src/cli/commands/tap_command.dart';
import 'package:marionette_cli/src/cli/commands/unregister_command.dart';
import 'package:marionette_cli/src/cli/native_command.dart';
import 'package:marionette_cli/src/instance_registry.dart';
import 'package:marionette_cli/src/native_session_registry.dart';

class MarionetteCommandRunner extends CommandRunner<int> {
  /// [operatingSystem] is the host OS in [Platform.operatingSystem] form and
  /// [environment] the process environment; both default to the real host.
  MarionetteCommandRunner({
    InstanceRegistry? registry,
    NativeSessionRegistry? nativeRegistry,
    String? operatingSystem,
    Map<String, String>? environment,
  })  : _registry = registry ?? InstanceRegistry(),
        _nativeRegistry = nativeRegistry ?? NativeSessionRegistry(),
        _operatingSystem = operatingSystem ?? Platform.operatingSystem,
        _environment = environment ?? Platform.environment,
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
        help: 'VM service URI as flutter run prints it '
            '(e.g., http://127.0.0.1:8181/AbC=/), or its ws://…/ws form. '
            'Bypasses the instance registry. Mutually exclusive with --instance.',
      )
      ..addOption(
        'timeout',
        help: 'Connection timeout in seconds.',
        defaultsTo: '5',
      )
      ..addOption(
        'native-device',
        help: 'Name of the native-lane device connection (from '
            'native-connect) for native-* commands.',
        defaultsTo: defaultNativeSession,
      )
      ..addOption(
        'session',
        help: 'Title for the session directory this command\'s step is '
            'logged into (see .marionette/sessions/). Keep it under ~60 '
            'characters — longer is truncated. Every invocation gets its '
            'own fresh session directory, titled from this if given. Falls '
            'back to an untitled directory when omitted.',
      )
      ..addOption(
        'session-dir',
        help: 'Base directory .marionette/sessions/ is created under. '
            'Overrides the MARIONETTE_SESSION_DIR environment variable and '
            'defaults to the current directory when neither is set.',
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
    addCommand(SetDeviceConfigCommand(_registry));
    addCommand(HotReloadCommand(_registry));
    addCommand(HotRestartCommand(_registry));
    addCommand(DoctorCommand(_registry));
    addCommand(NativeConnectCommand(_nativeRegistry));
    addCommand(NativeDisconnectCommand(_nativeRegistry));
    addCommand(NativeSessionsCommand(_nativeRegistry));
    addCommand(NativeGetElementsCommand(_nativeRegistry, _environment));
    addCommand(NativeWaitForCommand(_nativeRegistry, _environment));
    addCommand(NativeTakeScreenshotCommand(_nativeRegistry, _environment));
    addCommand(NativeTapCommand(_nativeRegistry, _environment));
    addCommand(NativeSwipeCommand(_nativeRegistry, _environment));
    addCommand(NativeScrollCommand(_nativeRegistry, _environment));
    addCommand(NativeEnterTextCommand(_nativeRegistry, _environment));
    addCommand(NativePressKeyCommand(_nativeRegistry, _environment));
    addCommand(NativeHideKeyboardCommand(_nativeRegistry, _environment));
    addCommand(NativeNotificationsCommand(_nativeRegistry, _environment));
    addCommand(HelpAiCommand());
    addCommand(McpCommand());
  }

  final InstanceRegistry _registry;
  final NativeSessionRegistry _nativeRegistry;
  final String _operatingSystem;
  final Map<String, String> _environment;

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
    final commandName = topLevelResults.command?.name;
    if (commandName == null) {
      printUsage();
      return 0;
    }
    if (commandName.startsWith('native-') && _operatingSystem == 'windows') {
      stderr.writeln('The native lane supports macOS and Linux hosts.');
      return 1;
    }
    return super.runCommand(topLevelResults);
  }
}
