import 'package:marionette_cli/src/cli/native_command.dart';
import 'package:marionette_cli/src/native_session_registry.dart';
import 'package:marionette_mcp/src/native_service/native_service_context.dart';
import 'package:marionette_mcp/src/native_service/tools/notification_tools.dart';
import 'package:mcp_dart/mcp_dart.dart';

class NativeNotificationsCommand extends NativeCommand {
  NativeNotificationsCommand(this.nativeRegistry) {
    argParser.addOption(
      'action',
      help: 'open / close the shade or Notification Center.',
      allowed: [for (final a in NativeNotificationsAction.values) a.name],
      mandatory: true,
    );
  }

  @override
  final NativeSessionRegistry nativeRegistry;

  @override
  String get name => 'native-notifications';

  @override
  String get description => 'Open or close the notifications.';

  @override
  Map<String, dynamic> toolArguments() => {'action': string('action')};

  @override
  Future<CallToolResult> execute(
    NativeServiceContext context,
    Map<String, dynamic> args,
  ) =>
      handleNativeNotifications(context, args);
}
