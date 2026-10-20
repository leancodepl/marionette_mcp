import 'dart:convert';

import 'package:marionette_mcp/src/native_service/native_connector.dart';
import 'package:marionette_mcp/src/native_service/native_service_context.dart';
import 'package:marionette_mcp/src/native_service/tools/arg_validation.dart';
import 'package:marionette_mcp/src/tool_runner.dart';
import 'package:mcp_dart/mcp_dart.dart';

/// Lifecycle actions of `native_app`.
enum NativeAppAction {
  activate,
  terminate,
  background,
  restart;

  static NativeAppAction? tryParse(Object? raw) {
    for (final value in values) {
      if (value.name == raw) return value;
    }
    return null;
  }
}

/// Actions of `native_notifications`.
enum NativeNotificationsAction {
  open,
  close,
  push;

  static NativeNotificationsAction? tryParse(Object? raw) {
    for (final value in values) {
      if (value.name == raw) return value;
    }
    return null;
  }
}

/// How long to wait before checking whether a permission change killed
/// the app; both platforms stop it asynchronously.
const _appExitCheckDelay = Duration(milliseconds: 800);

const _appIdDescription =
    'Android package name / iOS bundle id. Default: the app under test — '
    'the first non-system app seen in the foreground in this session.';

const _flutterLaneWarning =
    'The Flutter lane connection to this app is lost; after starting it '
    'again (native_app action=activate), reconnect with the Flutter connect '
    'tool.';

/// Registers device shortcut tools: permissions, URLs, app lifecycle,
/// notifications, orientation, location and device facts
/// (docs/native-lane-decisions.md#d9, #d12).
void registerNativeDeviceTools(
  McpServer server,
  NativeServiceContext context,
) {
  server
    ..registerTool(
      'native_permissions',
      description:
          'Grants, revokes or resets an app permission without the system '
          'dialog — prepare a state before a test, or skip a dialog. '
          'permission: ${NativePermission.commaSeparatedNames}. reset makes '
          'the app ask again on next use. Revoking on Android and most '
          'changes on iOS terminate the app if it is running (the result '
          'says so). The iOS Simulator cannot change notifications, nor '
          'grant / revoke photos (reset works) — answer those dialogs with '
          'native_tap. Android before 13 has no notification permission. '
          'Requires native_connect.',
      annotations: const ToolAnnotations(title: 'Native Permissions'),
      inputSchema: ToolInputSchema(
        properties: {
          'action': JsonSchema.string(
            description: '"grant", "revoke" or "reset".',
          ),
          'permission': JsonSchema.string(
            description: NativePermission.commaSeparatedNames,
          ),
          'appId': JsonSchema.string(description: _appIdDescription),
        },
        required: ['action', 'permission'],
      ),
      callback: (args, extra) => handleNativePermissions(context, args),
    )
    ..registerTool(
      'native_open_url',
      description:
          'Opens a URL with the system handler: a web page in the browser, '
          'or a deep link / custom scheme in the app that handles it (e.g. '
          'to return from an OAuth flow). On Android a link sent while the '
          'app is still starting is lost — after native_app activate / '
          'restart, wait for its first screen (native_wait_for) first. '
          'Requires native_connect.',
      annotations: const ToolAnnotations(title: 'Native Open URL'),
      inputSchema: ToolInputSchema(
        properties: {
          'url': JsonSchema.string(
            description: 'Absolute URL with a scheme, e.g. '
                'https://example.com or myapp://path.',
          ),
        },
        required: ['url'],
      ),
      callback: (args, extra) => handleNativeOpenUrl(context, args),
    )
    ..registerTool(
      'native_app',
      description: 'Controls an app: activate (start it, or bring the running '
          'instance back to the front with its state — e.g. after a share '
          'sheet, browser or Settings), background (go to the home screen), '
          'terminate, restart (terminate + activate, a fresh start). '
          'terminate and restart end the Flutter lane connection; on '
          'Android they also remove the app\'s notifications (force-stop). '
          'Requires native_connect.',
      annotations: const ToolAnnotations(title: 'Native App'),
      inputSchema: ToolInputSchema(
        properties: {
          'action': JsonSchema.string(
            description: '"activate", "background", "terminate" or '
                '"restart".',
          ),
          'appId': JsonSchema.string(description: _appIdDescription),
        },
        required: ['action'],
      ),
      callback: (args, extra) => handleNativeApp(context, args),
    )
    ..registerTool(
      'native_notifications',
      description:
          'open / close the notification shade (Android) or Notification '
          'Center (iOS, by swipe); push sends a simulated push notification '
          'to the app (iOS Simulator only; the app must be allowed to show '
          'notifications). Read the notifications with native_get_elements '
          'while the shade is open. To open a notification, native_tap it '
          '(Android, iOS banner); in the iOS Notification Center a tap does '
          'nothing — swipe it right with native_swipe. Requires '
          'native_connect.',
      annotations: const ToolAnnotations(title: 'Native Notifications'),
      inputSchema: ToolInputSchema(
        properties: {
          'action': JsonSchema.string(
            description: '"open", "close" or "push".',
          ),
          'title': JsonSchema.string(description: 'push: alert title.'),
          'body': JsonSchema.string(description: 'push: alert body.'),
          'payload': JsonSchema.object(
            description: 'push: full APNs payload with an "aps" key, instead '
                'of title/body.',
          ),
          'appId': JsonSchema.string(
            description: 'push: target app. $_appIdDescription',
          ),
        },
        required: ['action'],
      ),
      callback: (args, extra) => handleNativeNotifications(context, args),
    )
    ..registerTool(
      'native_device_info',
      description:
          'Returns device facts as JSON: platform, osVersion, apiLevel '
          '(Android), model, isEmulator, id (serial / UDID), screen (width, '
          'height in screenshot pixels, scale), orientation, foregroundApp, '
          'and appId — the app native_permissions / native_app act on by '
          'default. Requires native_connect.',
      annotations: const ToolAnnotations(
        title: 'Native Device Info',
        readOnlyHint: true,
      ),
      inputSchema: const ToolInputSchema(properties: {}),
      callback: (args, extra) => handleNativeDeviceInfo(context),
    )
    ..registerTool(
      'native_set_orientation',
      description:
          'Rotates the screen to "portrait" or "landscape". Screen size and '
          'element bounds follow the new orientation — read them again. '
          'Requires native_connect.',
      annotations: const ToolAnnotations(title: 'Native Set Orientation'),
      inputSchema: ToolInputSchema(
        properties: {
          'orientation': JsonSchema.string(
            description: '"portrait" or "landscape".',
          ),
        },
        required: ['orientation'],
      ),
      callback: (args, extra) => handleNativeSetOrientation(context, args),
    )
    ..registerTool(
      'native_biometrics',
      description: 'Simulates biometrics on an emulator / simulator: match (a '
          'recognised face or finger) or nonMatch answers a biometric prompt '
          'that is on screen (check it with native_get_elements first); '
          'enroll / unenroll register a face or finger (iOS Simulator only — '
          'on Android the result explains the Settings steps). Physical '
          'devices: not possible. Requires native_connect.',
      annotations: const ToolAnnotations(title: 'Native Biometrics'),
      inputSchema: ToolInputSchema(
        properties: {
          'action': JsonSchema.string(
            description: '"match", "nonMatch", "enroll" or "unenroll".',
          ),
        },
        required: ['action'],
      ),
      callback: (args, extra) => handleNativeBiometrics(context, args),
    )
    ..registerTool(
      'native_set_location',
      description: 'Sets the simulated GPS position (Android emulator, iOS '
          'Simulator). Requires native_connect.',
      annotations: const ToolAnnotations(title: 'Native Set Location'),
      inputSchema: ToolInputSchema(
        properties: {
          'latitude': JsonSchema.number(description: '-90 to 90.'),
          'longitude': JsonSchema.number(description: '-180 to 180.'),
        },
        required: ['latitude', 'longitude'],
      ),
      callback: (args, extra) => handleNativeSetLocation(context, args),
    );
}

CallToolResult _text(String text) =>
    CallToolResult(content: [TextContent(text: text)]);

/// Handles `native_permissions` (docs/native-lane-decisions.md#d17).
Future<CallToolResult> handleNativePermissions(
  NativeServiceContext context,
  Map<String, dynamic> args,
) async {
  final action = NativePermissionAction.tryParse(args['action']);
  final permission = NativePermission.tryParse(args['permission']);
  if (action == null) {
    return invalidArguments(
      'native_permissions action must be "grant", "revoke" or "reset".',
    );
  }
  if (permission == null) {
    return invalidArguments(
      'native_permissions permission must be one of: '
      '${NativePermission.commaSeparatedNames}.',
    );
  }

  final logger = context.logger;
  logger.info('Native permissions ${action.name} ${permission.name}');
  return runTool(logger, 'native permissions', () async {
    final device = context.requireConnector().device;
    final appId = await context.resolveAppId(args['appId'] as String?);
    final wasRunning = await device.isAppRunning(appId);

    final change = await device.setPermission(action, permission, appId);

    final lines = [
      '${_pastTense(action)} ${permission.name} '
          '(${change.nativeNames.join(', ')}) for $appId.',
      ...change.notes,
    ];
    if (wasRunning == true) {
      await Future<void>.delayed(_appExitCheckDelay);
      if (await device.isAppRunning(appId) == false) {
        lines.add('The change terminated $appId. $_flutterLaneWarning');
      }
    }
    return _text(lines.join('\n'));
  });
}

String _pastTense(NativePermissionAction action) => switch (action) {
      NativePermissionAction.grant => 'Granted',
      NativePermissionAction.revoke => 'Revoked',
      NativePermissionAction.reset => 'Reset',
    };

/// Handles `native_open_url`.
Future<CallToolResult> handleNativeOpenUrl(
  NativeServiceContext context,
  Map<String, dynamic> args,
) async {
  final url = args['url'] as String?;
  final uri = url == null ? null : Uri.tryParse(url);
  if (uri == null || uri.scheme.isEmpty) {
    return invalidArguments(
      'native_open_url requires an absolute url with a scheme, e.g. '
      'https://example.com or myapp://path.',
    );
  }

  final logger = context.logger;
  logger.info('Native open URL $url');
  return runTool(logger, 'native open url', () async {
    await context.requireConnector().device.openUrl(url!);
    final isWeb = uri.scheme == 'http' || uri.scheme == 'https';
    return _text([
      'Opened $url. Check the result with native_get_elements '
          '(foregroundApp shows which app handled it).',
      if (context.platform == NativePlatform.ios && !isWeb)
        'iOS may first ask to open the app ("Open in …?"): confirm with '
            'native_tap text="Open".',
    ].join(' '));
  });
}

/// Handles `native_app`.
Future<CallToolResult> handleNativeApp(
  NativeServiceContext context,
  Map<String, dynamic> args,
) async {
  final action = NativeAppAction.tryParse(args['action']);
  if (action == null) {
    return invalidArguments(
      'native_app action must be "activate", "background", "terminate" or '
      '"restart".',
    );
  }

  final logger = context.logger;
  logger.info('Native app ${action.name}');
  return runTool(logger, 'native app', () async {
    final connector = context.requireConnector();
    final device = connector.device;
    Future<String> appId() => context.resolveAppId(args['appId'] as String?);
    switch (action) {
      case NativeAppAction.background:
        await connector.pressKey(NativeKey.home);
        return _text('Went to the home screen; the app keeps running in the '
            'background (native_app action=activate brings it back).');
      case NativeAppAction.activate:
        final id = await appId();
        await device.activateApp(id);
        return _text('Activated $id.');
      case NativeAppAction.terminate:
        final id = await appId();
        final wasRunning = await device.terminateApp(id);
        // Android's force-stop also cancels the app's notifications and
        // alarms (docs/native-lane-decisions.md#d11).
        final notifications = context.platform == NativePlatform.android
            ? ' Its notifications were removed too (Android force-stop); to '
                'test opening the app from a notification, use '
                'action=background instead.'
            : '';
        return _text(wasRunning
            ? 'Terminated $id.$notifications $_flutterLaneWarning'
            : '$id was not running.$notifications');
      case NativeAppAction.restart:
        final id = await appId();
        await device.terminateApp(id);
        await device.activateApp(id);
        // On Android a deep link sent during the cold start is lost (the
        // Flutter app has no link handler yet); iOS queues it.
        final startingNote = context.platform == NativePlatform.android
            ? ' Wait for its first screen (native_wait_for) before '
                'native_open_url — a link sent while it starts is lost.'
            : '';
        return _text('Restarted $id (fresh start). Reconnect the Flutter '
            'lane with the Flutter connect tool.$startingNote');
    }
  });
}

/// Handles `native_notifications`.
Future<CallToolResult> handleNativeNotifications(
  NativeServiceContext context,
  Map<String, dynamic> args,
) async {
  final action = NativeNotificationsAction.tryParse(args['action']);
  if (action == null) {
    return invalidArguments(
      'native_notifications action must be "open", "close" or "push".',
    );
  }
  final title = args['title'] as String?;
  final body = args['body'] as String?;
  final rawPayload = args['payload'];
  if (action == NativeNotificationsAction.push) {
    if (rawPayload != null &&
        (rawPayload is! Map<String, dynamic> || rawPayload['aps'] == null)) {
      return invalidArguments(
        'native_notifications payload must be an object with an "aps" key.',
      );
    }
    if (rawPayload == null && title == null && body == null) {
      return invalidArguments(
        'native_notifications push requires title and/or body, or payload.',
      );
    }
  }

  final logger = context.logger;
  logger.info('Native notifications ${action.name}');
  return runTool(logger, 'native notifications', () async {
    final connector = context.requireConnector();
    final ios = context.platform == NativePlatform.ios;
    switch (action) {
      case NativeNotificationsAction.open:
        if (ios) {
          await _swipeNotificationCenter(connector, open: true);
        } else {
          await connector.device.openNotifications();
        }
        // The iOS Notification Center ignores taps on a notification (it
        // only hints a side swipe; iOS 18.6 and 26.4); a swipe right opens it
        // (docs/native-lane-decisions.md#d21).
        return _text('Opened the notifications. Read them with '
            'native_get_elements; close with action=close.'
            '${ios ? ' To open one, swipe it right with native_swipe — a tap '
                'does nothing here. If only "N Notifications" is listed, tap '
                'it first to expand the list. Opened over the app, the '
                'Notification Center is not in the tree: send the app to the '
                'background (native_app action=background) first.' : ''}');
      case NativeNotificationsAction.close:
        if (ios) {
          await _swipeNotificationCenter(connector, open: false);
        } else {
          await connector.device.closeNotifications();
        }
        return _text('Closed the notifications.');
      case NativeNotificationsAction.push:
        final appId = await context.resolveAppId(args['appId'] as String?);
        final payload = rawPayload as Map<String, dynamic>? ??
            {
              'aps': {
                'alert': {
                  if (title != null) 'title': title,
                  if (body != null) 'body': body,
                },
              },
            };
        await connector.device.pushNotification(appId, payload);
        // While the app is active (in front, or for ~1 s after going to the
        // background) the app itself decides whether a banner is shown.
        return _text('Sent a push notification to $appId. It shows as a '
            'banner when the app is in the background — send it there a few '
            'seconds before pushing (native_app action=background); while '
            'the app is active, the app decides whether to show it.');
    }
  });
}

/// iOS has no command for the Notification Center: swipe down from the
/// top edge (left of center — the top right opens Control Center), or up
/// from the lower part of the screen to close it.
Future<void> _swipeNotificationCenter(
  NativeConnector connector, {
  required bool open,
}) async {
  final screen = await connector.getScreen();
  final x = screen.width ~/ 3;
  if (open) {
    await connector.swipe(
      startX: x,
      startY: 1,
      endX: x,
      endY: (screen.height * 0.6).round(),
    );
  } else {
    await connector.swipe(
      startX: screen.width ~/ 2,
      startY: screen.height - 1,
      endX: screen.width ~/ 2,
      endY: screen.height ~/ 2,
    );
  }
}

/// Handles `native_device_info`.
Future<CallToolResult> handleNativeDeviceInfo(NativeServiceContext context) {
  final logger = context.logger;
  logger.info('Native device info');
  return runTool(logger, 'native device info', () async {
    final connector = context.requireConnector();
    final info = await connector.device.info();
    final screen = await connector.getScreen();
    final orientation = await connector.getOrientation();
    final foregroundApp = await connector.foregroundApp
        .then<String?>((value) => value, onError: (Object _) => null);
    context.observeForegroundApp(foregroundApp);
    return _text(jsonEncode({
      'platform': context.platform?.name,
      ...info.toJson(),
      'screen': screen.toJson(),
      'orientation': orientation.name,
      'foregroundApp': foregroundApp,
      'appId': context.defaultAppId,
    }));
  });
}

/// Handles `native_set_orientation`.
Future<CallToolResult> handleNativeSetOrientation(
  NativeServiceContext context,
  Map<String, dynamic> args,
) async {
  final orientation = NativeOrientation.tryParse(args['orientation']);
  if (orientation == null) {
    return invalidArguments(
      'native_set_orientation orientation must be "portrait" or '
      '"landscape".',
    );
  }

  final logger = context.logger;
  logger.info('Native set orientation ${orientation.name}');
  return runTool(logger, 'native set orientation', () async {
    final connector = context.requireConnector();
    await connector.setOrientation(orientation);
    final screen = await connector.getScreen();
    return _text('Orientation is now ${orientation.name}; screen '
        '${screen.width}x${screen.height} screenshot pixels. Read elements '
        'again — their bounds changed.');
  });
}

/// Handles `native_biometrics` (docs/native-lane-decisions.md#d20).
Future<CallToolResult> handleNativeBiometrics(
  NativeServiceContext context,
  Map<String, dynamic> args,
) async {
  final action = NativeBiometricAction.tryParse(args['action']);
  if (action == null) {
    return invalidArguments(
      'native_biometrics action must be "match", "nonMatch", "enroll" or '
      '"unenroll".',
    );
  }

  final logger = context.logger;
  logger.info('Native biometrics ${action.name}');
  return runTool(logger, 'native biometrics', () async {
    await context.requireConnector().device.biometrics(action);
    return _text(switch (action) {
      NativeBiometricAction.match ||
      NativeBiometricAction.nonMatch =>
        'Simulated a ${action == NativeBiometricAction.match ? '' : 'non-'}'
            'matching face / finger. Check the result with '
            'native_get_elements (the prompt closes on a match; a non-match '
            'shows a retry dialog).',
      NativeBiometricAction.enroll =>
        'Enrolled a face / finger; apps now see biometrics as available.',
      NativeBiometricAction.unenroll => 'Removed the enrolled face / finger.',
    });
  });
}

/// Handles `native_set_location`.
Future<CallToolResult> handleNativeSetLocation(
  NativeServiceContext context,
  Map<String, dynamic> args,
) async {
  final latitude = (args['latitude'] as num?)?.toDouble();
  final longitude = (args['longitude'] as num?)?.toDouble();
  if (latitude == null ||
      longitude == null ||
      latitude.abs() > 90 ||
      longitude.abs() > 180) {
    return invalidArguments(
      'native_set_location requires latitude (-90..90) and longitude '
      '(-180..180).',
    );
  }

  final logger = context.logger;
  logger.info('Native set location $latitude,$longitude');
  return runTool(logger, 'native set location', () async {
    await context.requireConnector().device.setLocation(latitude, longitude);
    return _text('Simulated location set to $latitude, $longitude.');
  });
}
