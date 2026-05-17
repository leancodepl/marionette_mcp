import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:marionette_mcp/src/permissions/permission_accepter.dart';

/// CLI command that locates and taps an "accept" button on a native OS
/// permission dialog overlaying the Flutter app.
///
/// Does not require an active `connect` session — it shells out to `adb`
/// (Android) or `osascript` (iOS Simulator) directly.
class AcceptPermissionCommand extends Command<int> {
  @override
  String get name => 'accept-permission';

  @override
  String get description =>
      'Accept a native OS permission dialog (camera, location, etc.) that '
      'is overlaying the Flutter app. Uses `adb` on Android or `osascript` '
      'on iOS Simulator. Does not require an active instance connection.';

  @override
  Future<int> run() async {
    final result = await PermissionAccepter().accept();
    if (result.success) {
      stdout.writeln(result.message);
      return 0;
    } else {
      stderr.writeln(result.message);
      return 1;
    }
  }
}
