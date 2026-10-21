import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart' as logging;
import 'package:marionette_mcp/src/native_service/native_service_context.dart';
import 'package:marionette_mcp/src/version.g.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_context.dart';
import 'package:mcp_dart/mcp_dart.dart';

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

Screenshots: take_screenshots and native_take_screenshot always return base64 inline PNG images (default — no files written). When MARIONETTE_SCREENSHOTS_DIR is set, they also save PNG files to that directory and include absolute paths in the response alongside the inline images. When a path is returned, show the PNG to the user by embedding it as a markdown image: ![](/absolute/path.png). Do not rely on the inline image payload alone — hosts may hide it from the user.

Important: Elements are matched by their key (ValueKey<String>), Semantics identifier, or text content. Keys are the most reliable; a Semantics identifier (set via `Semantics(identifier: ...)`) is an equally stable alternative when adding a key is not practical. If you cannot locate a widget, you may need to add a ValueKey to it in the Flutter source code. For example: `ElevatedButton(key: ValueKey('submit_button'), ...)`.

Native lane (system UI outside the Flutter widget tree):
- When: prefer Flutter tools for in-app widgets. Use the native_* tools when the target is not in the Flutter tree — permission dialogs, system alerts, sheets and pickers, notifications, biometric prompts, browser sign-in, native screens, WebView content — or when get_interactive_elements warns that the app is not in front. The warning is reliable when present, but an alert or sheet shown by the app itself on iOS gives none: if a Flutter action has no effect, check native_get_elements. Capture system UI with native_take_screenshot (take_screenshots shows only Flutter).
- Session: call native_connect first; a lost device-side server or session is re-established automatically. Prefer one client (MCP server or CLI) per Android device — they share UIAutomator2's single session.
- Find and act: native_get_elements lists what is on screen (a text field's label as text, its typed content as value). native_tap, native_enter_text and the gestures (native_long_press, native_double_tap, native_pinch, native_swipe) take a selector (text, textContains, id, type, index); an ambiguous selector fails and lists the candidates — pass index or a more specific selector. A disabled element (enabled: false) is refused, not touched: on iOS the app's elements stay listed, disabled, under a system sheet or picker — act on the sheet or close it first. Native coordinates (x/y, startX/startY, bounds) are screenshot pixels on every platform; never reuse Flutter coordinates — for a platform view neither tree shows (camera preview, map, video) convert the bounds of a nearby Flutter element with native_map_flutter_rect.
- Waiting: use native_wait_for instead of fixed delays (a dialog, delayed content, the next screen). Elements outside the screen are not listed — content appearing below the bottom edge needs a scroll first. native_swipe does not wait for the content to settle (on iOS a tap right after a fling only stops it); native_scroll does.
- Scrolling: native_scroll with a target selector scrolls until it is visible and stops at the end of the list; within (the container's selector) scrolls nested lists and pickers. A target left at a screen edge or under a toolbar / tab bar may be covered — scroll a little more before tapping. Reads next to iOS system pickers take 2–3 s each.
- Keyboard: call native_hide_keyboard after typing when the keyboard covers UI you need (it refuses Gboard's floating toolbar on an emulator with a hardware keyboard, where Back would close the screen). To type into a focused Flutter field that native_get_elements does not show (Android), use native_enter_text without a selector.
- Device shortcuts instead of tapping system UI: native_permissions (grant / revoke / reset; to test the dialog itself, reset first, then native_wait_for + native_tap), native_app (activate brings the app back after a browser, share sheet or Settings), native_open_url, native_notifications, native_device_info, native_set_orientation, native_set_location, native_biometrics (answers a biometric prompt on an emulator / simulator). They act on the app under test by default. Revoking a permission, terminate and restart end the Flutter connection — reconnect afterwards. On Android, wait for the app's first screen after native_app activate / restart before native_open_url (an earlier deep link is lost), and terminate also removes the app's notifications.
- Notifications: native_notifications open, then read them with native_get_elements. On iOS a notification in the Notification Center opens with a swipe right (native_swipe), not a tap; tap a collapsed "N Notifications" first, and send the app to the background before opening the Notification Center or sending a simulated push. On Android, heads-up banners — and toasts on recent versions — are visible only on native_take_screenshot.
''';

/// Runs the Marionette MCP server with the given configuration.
///
/// Sets up logging, creates the MCP server with tools, and runs it on either
/// stdio or SSE transport depending on whether [ssePort] is provided.
Future<int> runMcpServer({
  required String logLevel,
  String? logFile,
  int? ssePort,
}) async {
  setupLogging(logLevel, logFile);

  final vmService = VmServiceContext();
  final native = NativeServiceContext(
    flutterViewMetrics: vmService.connector.getViewMetrics,
  );

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

  vmService.registerTools(server);
  native.registerTools(server);

  // Both lanes hold connections that keep the process alive: a native
  // session and the VM service WebSocket (without disconnecting it the
  // server never exits on stdin EOF while an app is connected).
  Future<void> disposeLanes() async {
    await native.dispose();
    await vmService.connector.disconnect();
  }

  if (ssePort != null) {
    return _runSseServer(server, ssePort, disposeLanes);
  } else {
    return _runStdioServer(server, disposeLanes);
  }
}

void setupLogging(String logLevelName, String? logFile) {
  final logLevel = logging.Level.LEVELS.firstWhere(
    (e) => e.name == logLevelName,
    orElse: () => logging.Level.INFO,
  );

  logging.Logger.root.level = logLevel;

  if (logFile != null) {
    final file = File(logFile)..createSync(recursive: true);
    logging.Logger.root.onRecord.listen((record) {
      file.writeAsStringSync(
        '[${record.level.name}][${record.loggerName}][${_formatTime(record.time)}] ${record.message}\n',
        mode: FileMode.append,
      );
    });
  } else {
    logging.Logger.root.onRecord.listen((record) {
      stderr.writeln(
        '[${record.level.name}][${record.loggerName}][${_formatTime(record.time)}] ${record.message}',
      );
    });
  }
}

String _formatTime(DateTime time) {
  return '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}:'
      '${time.second.toString().padLeft(2, '0')}';
}

Future<int> _runStdioServer(
  McpServer server,
  Future<void> Function() disposeLanes,
) async {
  final logger = logging.Logger('main');

  final transport = StdioServerTransport();
  final exitSignal = ExitSignal();
  final stdinClosed = Completer<void>();

  // Install the close handler before connecting. An immediate stdin EOF
  // (e.g. `</dev/null`) can close the transport during or right after
  // connect(); registering afterwards risks missing that close and hanging
  // until a signal. Fires when the transport closes — including stdin EOF,
  // i.e. the MCP host went away without sending a signal. Per the stdio
  // lifecycle the server should shut down then, not wait for SIGINT/SIGTERM.
  server.server.onclose = () {
    if (!stdinClosed.isCompleted) stdinClosed.complete();
  };

  try {
    logger.fine('Running MCP server on stdio');
    await server.connect(transport);
    logger.info('Server started');
  } catch (e, st) {
    logger.severe('Error when starting the Stdio transport', e, st);
    exitSignal.dispose();
    await disposeLanes();
    return 1;
  }

  // Stop on whichever happens first: an OS signal or the transport closing.
  // Only the first cause is logged — closing the server below re-triggers
  // `onclose`, which would otherwise log a misleading second reason.
  var stopping = false;
  void logStop(String reason) {
    if (stopping) return;
    stopping = true;
    logger.info('$reason, stopping');
  }

  await Future.any([
    exitSignal.wait.then((signal) => logStop('Received ${signal.name}')),
    stdinClosed.future.then((_) => logStop('stdin closed')),
  ]);

  // Release the signal subscriptions so the event loop can drain and the
  // process actually exits on the stdin-EOF path.
  exitSignal.dispose();
  await disposeLanes();
  await server.close();
  await transport.close();
  logger.info('Stopped');
  return 0;
}

Future<int> _runSseServer(
  McpServer server,
  int ssePort,
  Future<void> Function() disposeLanes,
) async {
  final logger = logging.Logger('main');
  final sseServerManager = SseServerManager(server);
  try {
    final httpServer = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      ssePort,
    );
    logger.fine('Running MCP server on SSE port $ssePort');
    unawaited(
      ExitSignal().wait.then((signal) {
        logger.info('Received ${signal.name}, stopping');
        unawaited(httpServer.close());
      }),
    );

    await for (final request in httpServer) {
      unawaited(sseServerManager.handleRequest(request));
    }

    logger.info('Stopping');
    await server.close();
  } catch (e, st) {
    logger.severe('Error when waiting for MCP client connection', e, st);
    return 1;
  } finally {
    await disposeLanes();
  }

  logger.info('Stopped');
  return 0;
}

/// Waits for SIGINT or SIGTERM to signal graceful shutdown.
class ExitSignal {
  ExitSignal() {
    if (!Platform.isWindows) {
      _sigtermSubscription = ProcessSignal.sigterm.watch().listen(
            _handleSignal,
          );
    }
    _sigintSubscription = ProcessSignal.sigint.watch().listen(_handleSignal);
  }

  final _completer = Completer<ProcessSignal>();
  StreamSubscription<ProcessSignal>? _sigtermSubscription;
  late final StreamSubscription<ProcessSignal> _sigintSubscription;
  bool _disposed = false;

  Future<ProcessSignal> get wait => _completer.future;

  /// Cancels the signal subscriptions so they no longer keep the event loop
  /// alive. Safe to call multiple times — in normal operation it runs once
  /// from [_handleSignal] and again from the shutdown path.
  void dispose() => _cleanup();

  void _handleSignal(ProcessSignal signal) {
    if (!_completer.isCompleted) {
      _completer.complete(signal);
      _cleanup();
    }
  }

  void _cleanup() {
    if (_disposed) return;
    _disposed = true;
    _sigtermSubscription?.cancel();
    _sigintSubscription.cancel();
  }
}
