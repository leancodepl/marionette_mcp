import 'dart:io';

import 'package:args/args.dart';
import 'package:marionette_mcp/marionette_mcp.dart';

void printUsage(ArgParser argParser) {
  stderr
    ..writeln('Marionette MCP Server - Flutter app interaction for AI agents')
    ..writeln()
    ..writeln('Usage: marionette_mcp [options]')
    ..writeln()
    ..writeln('Options:')
    ..writeln(argParser.usage);
}

Future<void> main(List<String> arguments) async {
  final argParser = ServerConfig.buildParser();
  try {
    final results = argParser.parse(arguments);

    if (results.flag('help')) {
      printUsage(argParser);
      return;
    }
    if (results.flag('version')) {
      stderr.writeln('marionette_mcp version: $version');
      return;
    }

    final config = ServerConfig.fromResults(results);

    exitCode = await runMcpServer(
      logLevel: config.logLevel,
      logFile: config.logFile,
      ssePort: config.ssePort,
    );
  } on FormatException catch (e) {
    stderr
      ..writeln(e.message)
      ..writeln();
    printUsage(argParser);
    exitCode = 1;
  } on Exception catch (e) {
    stderr.writeln(e.toString());
    exitCode = 1;
  }
}
