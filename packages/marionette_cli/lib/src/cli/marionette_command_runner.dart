import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import '../instance_registry.dart';
import 'commands/doctor_command.dart';
import 'commands/elements_command.dart';
import 'commands/enter_text_command.dart';
import 'commands/hot_reload_command.dart';
import 'commands/list_command.dart';
import 'commands/logs_command.dart';
import 'commands/mcp_command.dart';
import 'commands/register_command.dart';
import 'commands/screenshot_command.dart';
import 'commands/scroll_to_command.dart';
import 'commands/tap_command.dart';
import 'commands/unregister_command.dart';

class MarionetteCommandRunner extends CommandRunner<int> {
  MarionetteCommandRunner()
      : _registry = InstanceRegistry(),
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
        'timeout',
        help: 'Connection timeout in seconds.',
        defaultsTo: '5',
      );

    addCommand(RegisterCommand(_registry));
    addCommand(UnregisterCommand(_registry));
    addCommand(ListCommand(_registry));
    addCommand(ElementsCommand(_registry));
    addCommand(TapCommand(_registry));
    addCommand(EnterTextCommand(_registry));
    addCommand(ScrollToCommand(_registry));
    addCommand(ScreenshotCommand(_registry));
    addCommand(LogsCommand(_registry));
    addCommand(HotReloadCommand(_registry));
    addCommand(DoctorCommand(_registry));
    addCommand(McpCommand());
  }

  final InstanceRegistry _registry;

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
