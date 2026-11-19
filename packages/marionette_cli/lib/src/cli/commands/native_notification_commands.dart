import 'package:args/args.dart';
import 'package:marionette_cli/src/cli/native_command.dart';
import 'package:marionette_mcp/src/native_service/native_service_context.dart';
import 'package:marionette_mcp/src/native_service/tools/notification_tools.dart';
import 'package:mcp_dart/mcp_dart.dart';

class NativeNotificationsCommand extends NativeCommand {
  NativeNotificationsCommand(super.nativeRegistry, super.environment) {
    argParser.addOption(
      'action',
      help: 'open / close the shade or Notification Center.',
      allowed: [for (final a in NativeNotificationsAction.values) a.name],
      mandatory: true,
    );
  }

  @override
  String get name => 'native-notifications';

  @override
  String get description => 'Open or close the notifications.';

  @override
  Map<String, dynamic> toolArguments(ArgResults results) =>
      {'action': string(results, 'action')};

  @override
  Future<CallToolResult> execute(
    NativeServiceContext context,
    Map<String, dynamic> args,
  ) =>
      handleNativeNotifications(context, args);
}
