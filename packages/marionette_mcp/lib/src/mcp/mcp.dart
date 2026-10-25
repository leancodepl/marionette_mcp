/// Marionette MCP server composition.
library;

import 'package:marionette_mcp/src/version.g.dart';
import 'package:mcp_dart/mcp_dart.dart';

import 'server_context.dart';
import 'step_logging.dart';
import 'tools/dynamic_extension_tools.dart';
import 'tools/tools.dart';

export 'server_context.dart';
export 'tools/tools.dart';

const _instructions = '''
Marionette MCP enables AI agents to interact with Flutter apps running in debug mode. It provides tools to inspect UI elements, tap buttons, enter text, scroll, take screenshots, retrieve logs, and perform hot reloads and hot restarts.

Usage:
1. Start the Flutter app in debug mode and note the VM service URI (e.g., ws://127.0.0.1:8181/ws).
2. Use the "connect" tool with the VM service URI to establish a connection.
3. Use "get_interactive_elements" to discover available UI elements.
4. Interact with elements using "tap", "enter_text", or "scroll_to" tools.
5. Use "take_screenshots" to see the current app state and "get_logs" to debug issues.
6. Use "hot_reload" after making code changes to reload the app without losing state.
7. Use "hot_restart" to fully restart the app from main() and reset all state — needed for changes a hot reload cannot pick up (e.g. main()/bootstrap edits, global singletons, or state shape). Requires the app to be running via `flutter run`.

Important: Elements are matched by their key (ValueKey<String>), Semantics identifier, or text content. Keys are the most reliable; a Semantics identifier (set via `Semantics(identifier: ...)`) is an equally stable alternative when adding a key is not practical. If you cannot locate a widget, you may need to add a ValueKey to it in the Flutter source code. For example: `ElevatedButton(key: ValueKey('submit_button'), ...)`.

When the same key exists in several identical subtrees (grid cells, repeated cards, embedded app instances), a plain match always hits the first one. Pass "ancestor_keys" alongside the selector to scope the search to one subtree, e.g. `{"key": "cell.joinButton", "ancestor_keys": ["grid.cell_2"]}`. The keys nest, outermost first — each is looked up inside the previous one's subtree — so `["session_2", "grid.cell_3"]` reaches a cell whose own key also repeats in the other sessions. Only descendants of the last key match, never that element itself. If a key has no element the call fails naming it, instead of searching the whole tree; scroll_to keeps scrolling first, because the scope may not be built yet. ancestor_keys is ignored when targeting by coordinates or focused_element. "get_interactive_elements" accepts "ancestor_keys" as well, to list only that subtree — use it to find the right scope keys and to keep the listing small on busy screens.
''';

/// Creates the protocol server using an explicitly owned app context.
///
/// The caller must dispose [context] when its transport closes.
McpServer createMcpServer({required VmServiceContext context}) {
  final server = McpServer(
    const Implementation(name: 'marionette-mcp', version: version),
    options: const McpServerOptions(
      // listChanged: true advertises that the tool set can change at
      // runtime — required for clients to refetch tools/list when an app
      // connects with custom extensions registered via
      // registerMarionetteExtension.
      capabilities: ServerCapabilities(
        tools: ServerCapabilitiesTools(listChanged: true),
      ),
      instructions: _instructions,
    ),
  );

  registerMcpTools(server, context: context);

  return server;
}

/// Registers the complete catalog on a server owned by the caller.
///
/// A context belongs to one server and must be disposed when its transport ends.
void registerMcpTools(McpServer server, {required VmServiceContext context}) {
  context.attachDynamicTools(DynamicExtensionTools(
    server: server,
    connector: context.connector,
    logger: context.logger,
    stepLogger: context.stepLogger,
  ));
  for (final tool in createAllTools(context: context)) {
    server.registerBaseTool(
      tool,
      callback: tool is ConnectionTool
          ? tool.execute
          : withStepLogging(context.stepLogger, tool.name, tool.execute),
    );
  }
}
