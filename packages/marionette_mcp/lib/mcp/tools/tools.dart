/// Static MCP tools for inspecting and interacting with a Flutter app.
library;

import 'package:logging/logging.dart' as logging;
import 'package:marionette_mcp/src/session/step_logger.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';

import 'base_tool.dart';
import 'device_tools.dart';
import 'extension_tools.dart';
import 'gesture_tools.dart';
import 'inspection_tools.dart';
import 'keyboard_tools.dart';
import 'system_tools.dart';
import 'text_tools.dart';

export 'base_tool.dart';
export 'device_tools.dart';
export 'extension_tools.dart';
export 'gesture_tools.dart';
export 'inspection_tools.dart';
export 'keyboard_tools.dart';
export 'system_tools.dart';
export 'text_tools.dart';

/// Creates all static tools with their shared dependencies.
List<BaseTool> createAllTools({
  required VmServiceConnector connector,
  required logging.Logger logger,
  required StepLogger stepLogger,
}) =>
    [
      ...createInspectionTools(
        connector: connector,
        logger: logger,
        stepLogger: stepLogger,
      ),
      ...createGestureTools(connector: connector, logger: logger),
      ...createTextTools(connector: connector, logger: logger),
      ...createKeyboardTools(connector: connector, logger: logger),
      ...createDeviceTools(connector: connector, logger: logger),
      ...createExtensionTools(connector: connector, logger: logger),
      ...createSystemTools(connector: connector, logger: logger),
    ];
