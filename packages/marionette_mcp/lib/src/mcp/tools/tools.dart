/// Static MCP tools for inspecting and interacting with a Flutter app.
library;

import '../../session/screenshot_service.dart';
import '../server_context.dart';
import 'base_tool.dart';
import 'connection_tools.dart';
import 'device_tools.dart';
import 'extension_tools.dart';
import 'gesture_tools.dart';
import 'inspection_tools.dart';
import 'keyboard_tools.dart';
import 'system_tools.dart';
import 'text_tools.dart';

export 'base_tool.dart';
export 'connection_tools.dart';
export 'device_tools.dart';
export 'extension_tools.dart';
export 'gesture_tools.dart';
export 'inspection_tools.dart';
export 'keyboard_tools.dart';
export 'system_tools.dart';
export 'text_tools.dart';

/// Creates the complete built-in catalog with shared connection/session state.
List<BaseTool> createAllTools({required VmServiceContext context}) => [
      ConnectTool(context),
      DisconnectTool(context),
      ...createInspectionTools(
        connector: context.connector,
        logger: context.logger,
        screenshotService: ScreenshotService(context.connector),
        currentSession: () => context.connection.session,
      ),
      ...createGestureTools(
          connector: context.connector, logger: context.logger),
      ...createTextTools(connector: context.connector, logger: context.logger),
      ...createKeyboardTools(
          connector: context.connector, logger: context.logger),
      ...createDeviceTools(
          connector: context.connector, logger: context.logger),
      ...createExtensionTools(
          connector: context.connector, logger: context.logger),
      ...createSystemTools(
          connector: context.connector, logger: context.logger),
    ];
