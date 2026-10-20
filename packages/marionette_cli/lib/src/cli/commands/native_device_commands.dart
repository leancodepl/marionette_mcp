import 'package:marionette_cli/src/cli/native_command.dart';
import 'package:marionette_cli/src/native_session_registry.dart';
import 'package:marionette_mcp/src/native_service/native_device.dart';
import 'package:marionette_mcp/src/native_service/native_service_context.dart';
import 'package:marionette_mcp/src/native_service/tools/device_tools.dart';
import 'package:mcp_dart/mcp_dart.dart';

const _appIdHelp = 'Android package / iOS bundle id (default: the app under '
    'test of the session).';

class NativePermissionsCommand extends NativeCommand {
  NativePermissionsCommand(this.nativeRegistry) {
    argParser
      ..addOption(
        'action',
        help: 'reset makes the app ask again.',
        allowed: [for (final a in NativePermissionAction.values) a.name],
        mandatory: true,
      )
      ..addOption(
        'permission',
        allowed: [for (final p in NativePermission.values) p.name],
        mandatory: true,
      )
      ..addOption('app-id', help: _appIdHelp);
  }

  @override
  final NativeSessionRegistry nativeRegistry;

  @override
  String get name => 'native-permissions';

  @override
  String get description =>
      'Grant, revoke or reset a permission without the system dialog. '
      'Revoking may terminate the app (the output says so).';

  @override
  Map<String, dynamic> toolArguments() => NativeCommand.compact({
        'action': string('action'),
        'permission': string('permission'),
        'appId': string('app-id'),
      });

  @override
  Future<CallToolResult> execute(
    NativeServiceContext context,
    Map<String, dynamic> args,
  ) =>
      handleNativePermissions(context, args);
}

class NativeOpenUrlCommand extends NativeCommand {
  NativeOpenUrlCommand(this.nativeRegistry) {
    argParser.addOption(
      'url',
      help: 'A web page or a deep link / custom scheme.',
      mandatory: true,
    );
  }

  @override
  final NativeSessionRegistry nativeRegistry;

  @override
  String get name => 'native-open-url';

  @override
  String get description => 'Open a URL with the system handler.';

  @override
  Map<String, dynamic> toolArguments() => {'url': string('url')};

  @override
  Future<CallToolResult> execute(
    NativeServiceContext context,
    Map<String, dynamic> args,
  ) =>
      handleNativeOpenUrl(context, args);
}

class NativeAppCommand extends NativeCommand {
  NativeAppCommand(this.nativeRegistry) {
    argParser
      ..addOption(
        'action',
        help: 'activate starts the app or brings it back with its state.',
        allowed: [for (final a in NativeAppAction.values) a.name],
        mandatory: true,
      )
      ..addOption('app-id', help: _appIdHelp);
  }

  @override
  final NativeSessionRegistry nativeRegistry;

  @override
  String get name => 'native-app';

  @override
  String get description =>
      'Activate, background, terminate or restart an app. On Android, '
      'terminate and restart also remove its notifications.';

  @override
  Map<String, dynamic> toolArguments() => NativeCommand.compact({
        'action': string('action'),
        'appId': string('app-id'),
      });

  @override
  Future<CallToolResult> execute(
    NativeServiceContext context,
    Map<String, dynamic> args,
  ) =>
      handleNativeApp(context, args);
}

class NativeNotificationsCommand extends NativeCommand {
  NativeNotificationsCommand(this.nativeRegistry) {
    argParser
      ..addOption(
        'action',
        help: 'open / close the shade or Notification Center; push a '
            'simulated push (iOS Simulator).',
        allowed: [for (final a in NativeNotificationsAction.values) a.name],
        mandatory: true,
      )
      ..addOption('title', help: 'push: alert title.')
      ..addOption('body', help: 'push: alert body.')
      ..addOption(
        'payload',
        help: 'push: full APNs payload as JSON (with an "aps" key), instead '
            'of --title / --body.',
      )
      ..addOption('app-id', help: _appIdHelp);
  }

  @override
  final NativeSessionRegistry nativeRegistry;

  @override
  String get name => 'native-notifications';

  @override
  String get description =>
      'Open or close the notifications, or send a simulated push (iOS).';

  @override
  Map<String, dynamic> toolArguments() => NativeCommand.compact({
        'action': string('action'),
        'title': string('title'),
        'body': string('body'),
        'payload': jsonObject('payload'),
        'appId': string('app-id'),
      });

  @override
  Future<CallToolResult> execute(
    NativeServiceContext context,
    Map<String, dynamic> args,
  ) =>
      handleNativeNotifications(context, args);
}

class NativeSetOrientationCommand extends NativeCommand {
  NativeSetOrientationCommand(this.nativeRegistry) {
    argParser.addOption(
      'orientation',
      allowed: ['portrait', 'landscape'],
      mandatory: true,
    );
  }

  @override
  final NativeSessionRegistry nativeRegistry;

  @override
  String get name => 'native-set-orientation';

  @override
  String get description => 'Rotate the device to portrait or landscape.';

  @override
  Map<String, dynamic> toolArguments() =>
      {'orientation': string('orientation')};

  @override
  Future<CallToolResult> execute(
    NativeServiceContext context,
    Map<String, dynamic> args,
  ) =>
      handleNativeSetOrientation(context, args);
}

class NativeSetLocationCommand extends NativeCommand {
  NativeSetLocationCommand(this.nativeRegistry) {
    argParser
      ..addOption('latitude', mandatory: true)
      ..addOption('longitude', mandatory: true);
  }

  @override
  final NativeSessionRegistry nativeRegistry;

  @override
  String get name => 'native-set-location';

  @override
  String get description =>
      'Set the simulated GPS position (Android emulator, iOS Simulator).';

  @override
  Map<String, dynamic> toolArguments() => NativeCommand.compact({
        'latitude': number('latitude'),
        'longitude': number('longitude'),
      });

  @override
  Future<CallToolResult> execute(
    NativeServiceContext context,
    Map<String, dynamic> args,
  ) =>
      handleNativeSetLocation(context, args);
}

class NativeBiometricsCommand extends NativeCommand {
  NativeBiometricsCommand(this.nativeRegistry) {
    argParser.addOption(
      'action',
      help: 'match / nonMatch answer a biometric prompt on screen; enroll / '
          'unenroll: iOS Simulator only.',
      allowed: [for (final a in NativeBiometricAction.values) a.name],
      mandatory: true,
    );
  }

  @override
  final NativeSessionRegistry nativeRegistry;

  @override
  String get name => 'native-biometrics';

  @override
  String get description =>
      'Simulate Face ID / Touch ID / fingerprint on an emulator or simulator.';

  @override
  Map<String, dynamic> toolArguments() => {'action': string('action')};

  @override
  Future<CallToolResult> execute(
    NativeServiceContext context,
    Map<String, dynamic> args,
  ) =>
      handleNativeBiometrics(context, args);
}
