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
List<BaseTool> createAllTools({required VmServiceContext context}) {
  final connector = context.connector;
  final logger = context.logger;
  return [
    ConnectTool(context),
    DisconnectTool(context),
    GetInteractiveElementsTool(connector, logger),
    GetLogsTool(connector, logger),
    TakeScreenshotsTool(
      ScreenshotService(connector),
      logger,
      () => context.connection.session,
    ),
    TapTool(connector, logger),
    SecondaryTapTool(connector, logger),
    DoubleTapTool(connector, logger),
    LongPressTool(connector, logger),
    SwipeTool(connector, logger),
    PinchZoomTool(connector, logger),
    PressBackButtonTool(connector, logger),
    ScrollToTool(connector, logger),
    EnterTextTool(connector, logger),
    PressKeyTool(connector, logger),
    SetDeviceConfigTool(connector, logger),
    ListCustomExtensionsTool(connector, logger),
    CallCustomExtensionTool(connector, logger),
    HotReloadTool(connector, logger),
    HotRestartTool(connector, logger),
  ];
}
