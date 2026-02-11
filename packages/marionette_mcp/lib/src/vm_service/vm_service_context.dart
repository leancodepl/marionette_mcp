import 'dart:convert';

import 'package:logging/logging.dart' as logging;
import 'package:marionette_mcp/src/version.g.dart' as v;
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';
import 'package:mcp_dart/mcp_dart.dart';

/// Context for managing VM service connection and registering MCP tools.
final class VmServiceContext {
  VmServiceContext()
    : connector = VmServiceConnector(),
      _logger = logging.Logger('VmServiceContext');

  final VmServiceConnector connector;
  final logging.Logger _logger;

  /// Registers all VM service related tools with the MCP server.
  void registerTools(McpServer server) {
    // Connection management tools
    server
      ..registerTool(
        'connect',
        description:
            'Connects to a Flutter app via its VM service URI. This must be called before using any other tools. The VM service URI is typically in the format ws://127.0.0.1:PORT/ws and can be found in the Flutter app output when running in debug mode.',
        annotations: const ToolAnnotations(title: 'Connect to App'),
        inputSchema: ToolInputSchema(
          properties: {
            'uri': JsonSchema.string(
              description:
                  'VM service URI (e.g., ws://127.0.0.1:8181/ws). This is printed in the Flutter app console when running in debug mode.',
            ),
          },
          required: ['uri'],
        ),
        callback: (args, extra) async {
          final uri = args['uri'] as String;
          _logger.info('Connecting to app at $uri');

          try {
            await connector.connect(uri);

            // Version compatibility check
            try {
              final bindingVersion = await connector.getVersion();
              if (bindingVersion != v.version) {
                await connector.disconnect();
                return CallToolResult(
                  isError: true,
                  content: [
                    TextContent(
                      text:
                          'Version mismatch: marionette_mcp is ${v.version}, '
                          'but marionette_flutter binding is $bindingVersion. '
                          'Please ensure both packages are the same version.',
                    ),
                  ],
                );
              }
            } catch (err) {
              _logger.warning('Failed to check binding version', err);
              await connector.disconnect();
              return CallToolResult(
                isError: true,
                content: [
                  TextContent(
                    text:
                        'Failed to verify marionette_flutter binding version. '
                        'Please ensure marionette_flutter is up to date. '
                        'Error: $err',
                  ),
                ],
              );
            }

            return CallToolResult(
              content: [
                TextContent(text: 'Successfully connected to app at $uri'),
              ],
            );
          } catch (err) {
            _logger.severe('Failed to connect to app', err);
            return CallToolResult(
              isError: true,
              content: [TextContent(text: 'Failed to connect to app: $err')],
            );
          }
        },
      )
      ..registerTool(
        'disconnect',
        description:
            'Disconnects from the currently connected Flutter app. After disconnecting, you must call connect again to use any other tools.',
        annotations: const ToolAnnotations(title: 'Disconnect from App'),
        inputSchema: const ToolInputSchema(properties: {}),
        callback: (args, extra) async {
          _logger.info('Disconnecting from app');

          try {
            await connector.disconnect();
            return CallToolResult(
              content: [
                const TextContent(text: 'Successfully disconnected from app'),
              ],
            );
          } catch (err) {
            _logger.severe('Error during disconnect', err);
            return CallToolResult(
              isError: true,
              content: [TextContent(text: 'Error during disconnect: $err')],
            );
          }
        },
      )
      // Interactive elements inspection
      ..registerTool(
        'get_interactive_elements',
        description:
            'Returns a list of all interactive elements currently visible in the Flutter app UI tree. Each element includes its type, text content (if any), key (if any), and other identifying properties. This is useful for understanding what can be interacted with in the app. Requires an active connection established via connect.',
        annotations: const ToolAnnotations(
          title: 'Get Interactive Elements',
          readOnlyHint: true,
          idempotentHint: true,
        ),
        inputSchema: const ToolInputSchema(properties: {}),
        callback: (args, extra) async {
          _logger.info('Getting interactive elements');

          try {
            final response = await connector.getInteractiveElements();
            final elements = response['elements'] as List<dynamic>;

            // Format the elements nicely
            final buffer = StringBuffer()
              ..writeln('Found ${elements.length} interactive element(s):\n');

            for (final element in elements) {
              buffer.writeln(_formatElement(element as Map<String, dynamic>));
            }

            return CallToolResult(
              content: [TextContent(text: buffer.toString())],
            );
          } catch (err) {
            _logger.warning('Failed to get interactive elements', err);
            return CallToolResult(
              isError: true,
              content: [TextContent(text: err.toString())],
            );
          }
        },
      )
      // Tap interaction
      ..registerTool(
        'tap',
        description:
            'Simulates a tap gesture on an element in the Flutter app that matches the given criteria. You can match elements by their key (a ValueKey<String>), by their text content (but not accessibility!), by their widget type, or by screen coordinates. Only one matching method should be used: either key, text, type, or coordinates. Prefer using the key if available, as it is more reliable. Limit yourself to elements from get_interactive_elements only if you can. Requires an active connection established via connect.',
        annotations: const ToolAnnotations(title: 'Tap Element'),
        inputSchema: ToolInputSchema(
          properties: {
            'key': JsonSchema.string(
              description:
                  'The key of the element to tap. You can get the key of an element by calling get_interactive_elements.',
            ),
            'text': JsonSchema.string(
              description:
                  'The visible text content of the element to tap. Use this for elements that display text like buttons or labels.',
            ),
            'type': JsonSchema.string(
              description:
                  'The widget type name of the element to tap (e.g., "ElevatedButton", "IconButton"). Use this to match elements by their Flutter widget type.',
            ),
            'coordinates': JsonSchema.object(
              description:
                  'Screen coordinates to tap at. Use this to tap at a specific position on the screen.',
              properties: {
                'x': JsonSchema.number(
                  description:
                      'The x coordinate (horizontal position from left).',
                ),
                'y': JsonSchema.number(
                  description: 'The y coordinate (vertical position from top).',
                ),
              },
              required: ['x', 'y'],
            ),
          },
        ),
        callback: (args, extra) async {
          final matcher = _buildMatcher(args);
          _logger.info('Tapping with matcher: $matcher');

          try {
            final response = await connector.tap(matcher);
            final message = response['message'] as String?;

            return CallToolResult(
              content: [TextContent(text: message ?? 'Successfully tapped')],
            );
          } catch (err) {
            _logger.warning('Failed to tap', err);
            return CallToolResult(
              isError: true,
              content: [TextContent(text: err.toString())],
            );
          }
        },
      )
      // Text input
      ..registerTool(
        'enter_text',
        description:
            'Enters text into a text field in the Flutter app that matches the given criteria. This simulates typing text into the field. Requires an active connection established via connect.',
        annotations: const ToolAnnotations(title: 'Enter Text'),
        inputSchema: ToolInputSchema(
          properties: {
            'input': JsonSchema.string(
              description: 'The text to enter into the text field.',
            ),
            'key': JsonSchema.string(
              description:
                  'The key of the text field. You can get the key of an element by calling get_interactive_elements.',
            ),
          },
          required: ['input', 'key'],
        ),
        callback: (args, extra) async {
          final input = args['input'] as String;
          final matcher = _buildMatcher(args);
          _logger.info('Entering text into element with matcher: $matcher');

          try {
            final response = await connector.enterText(matcher, input);
            final message = response['message'] as String?;

            return CallToolResult(
              content: [
                TextContent(text: message ?? 'Successfully entered text'),
              ],
            );
          } catch (err) {
            _logger.warning('Failed to enter text', err);
            return CallToolResult(
              isError: true,
              content: [TextContent(text: err.toString())],
            );
          }
        },
      )
      // Scroll to element
      ..registerTool(
        'scroll_to',
        description:
            'Scrolls the view until an element matching the given criteria becomes visible. You can match elements by their key (a ValueKey<String>) or by their visible text content. This is useful when you need to interact with elements that are not currently visible on screen. Requires an active connection established via connect.',
        annotations: const ToolAnnotations(title: 'Scroll to Element'),
        inputSchema: ToolInputSchema(
          properties: {
            'key': JsonSchema.string(
              description:
                  'The key of the element to scroll to. You can get the key of an element by calling get_interactive_elements.',
            ),
            'text': JsonSchema.string(
              description:
                  'The visible text content of the element to scroll to.',
            ),
          },
        ),
        callback: (args, extra) async {
          final matcher = _buildMatcher(args);
          _logger.info('Scrolling to element with matcher: $matcher');

          try {
            final response = await connector.scrollToElement(matcher);
            final message = response['message'] as String?;

            return CallToolResult(
              content: [
                TextContent(
                  text: message ?? 'Successfully scrolled to element',
                ),
              ],
            );
          } catch (err) {
            _logger.warning('Failed to scroll to element', err);
            return CallToolResult(
              isError: true,
              content: [TextContent(text: err.toString())],
            );
          }
        },
      )
      // Get logs
      ..registerTool(
        'get_logs',
        description:
            'Retrieves all application logs collected from the Flutter app since app start or since the last hot reload. This includes debug messages, errors, and other log output from the running app. Requires an active connection established via connect.',
        annotations: const ToolAnnotations(
          title: 'Get Application Logs',
          readOnlyHint: true,
        ),
        inputSchema: const ToolInputSchema(properties: {}),
        callback: (args, extra) async {
          _logger.info('Getting application logs');

          try {
            final response = await connector.getLogs();
            final logs = response['logs'] as List;
            final count = response['count'] as int;

            if (count == 0) {
              return CallToolResult(
                content: [const TextContent(text: 'No logs collected')],
              );
            }

            // Format logs nicely
            final buffer = StringBuffer()
              ..writeln(
                'Collected $count log entr${count == 1 ? 'y' : 'ies'}:\n',
              );

            for (final log in logs) {
              buffer.writeln(log);
            }

            return CallToolResult(
              content: [TextContent(text: buffer.toString())],
            );
          } on VmServiceExtensionException catch (err) {
            _logger.warning('Failed to get logs', err);
            return CallToolResult(
              isError: true,
              content: [TextContent(text: err.error ?? err.message)],
            );
          } catch (err) {
            _logger.warning('Failed to get logs', err);
            return CallToolResult(
              isError: true,
              content: [TextContent(text: err.toString())],
            );
          }
        },
      )
      // Take screenshots
      ..registerTool(
        'take_screenshots',
        description:
            'Takes screenshots of all views in the Flutter app. Returns base64-encoded PNG images that can be decoded and saved. This captures the current visual state of the app. Requires an active connection established via connect.',
        annotations: const ToolAnnotations(
          title: 'Take Screenshots',
          readOnlyHint: true,
        ),
        inputSchema: const ToolInputSchema(properties: {}),
        callback: (args, extra) async {
          _logger.info('Taking screenshots');

          try {
            final response = await connector.takeScreenshots();
            final screenshots = (response['screenshots'] as List<dynamic>)
                .cast<String>();

            if (screenshots.isEmpty) {
              return CallToolResult(
                content: [const TextContent(text: 'No screenshots captured')],
              );
            } else {
              return CallToolResult(
                content: screenshots
                    .map(
                      (screenshot) =>
                          ImageContent(data: screenshot, mimeType: 'image/png'),
                    )
                    .toList(),
              );
            }
          } catch (err) {
            _logger.warning('Failed to take screenshots', err);
            return CallToolResult(
              isError: true,
              content: [TextContent(text: err.toString())],
            );
          }
        },
      )
      // List custom extensions
      ..registerTool(
        'list_custom_extensions',
        description:
            'Lists all custom VM service extensions registered by the Flutter '
            'app (outside of the built-in Marionette extensions). Each '
            'extension includes its name and an optional description. Use this '
            'to discover what app-specific extensions are available before '
            'calling them with call_custom_extension. '
            'Requires an active connection established via connect.',
        annotations: const ToolAnnotations(
          title: 'List Custom Extensions',
          readOnlyHint: true,
          idempotentHint: true,
        ),
        inputSchema: const ToolInputSchema(properties: {}),
        callback: (args, extra) async {
          _logger.info('Listing custom extensions');

          try {
            final response = await connector.listExtensions();
            final extensions =
                (response['extensions'] as List<dynamic>).cast<Map<String, dynamic>>();

            if (extensions.isEmpty) {
              return CallToolResult(
                content: [
                  const TextContent(
                    text: 'No custom extensions registered.',
                  ),
                ],
              );
            }

            final buffer = StringBuffer()
              ..writeln(
                'Found ${extensions.length} custom extension(s):\n',
              );

            for (final ext in extensions) {
              final name = ext['name'] as String;
              final description = ext['description'] as String?;
              buffer.write('- $name');
              if (description != null) {
                buffer.write(': $description');
              }
              buffer.writeln();
            }

            return CallToolResult(
              content: [TextContent(text: buffer.toString())],
            );
          } catch (err) {
            _logger.warning('Failed to list custom extensions', err);
            return CallToolResult(
              isError: true,
              content: [TextContent(text: err.toString())],
            );
          }
        },
      )
      // Call app-specific custom service extension (escape hatch).
      // Intentionally no readOnlyHint or idempotentHint since the behavior
      // depends entirely on the target extension.
      ..registerTool(
        'call_custom_extension',
        description:
            'Calls a custom VM service extension registered by the Flutter app. '
            'This is an escape hatch for interacting with app-specific '
            'extensions that are not part of marionette\'s built-in tools. '
            'For marionette features, use the dedicated tools instead. '
            'The extension name should not include the "ext.flutter." prefix as '
            'it is added automatically. For example, use '
            '"deckNavigation.goToSlide" instead of '
            '"ext.flutter.deckNavigation.goToSlide". '
            'Arguments are passed as string key-value pairs. '
            'The available extensions depend on what the connected Flutter app '
            'has registered. Check the app\'s source code for available extensions. '
            'Requires an active connection established via connect.',
        annotations: const ToolAnnotations(title: 'Call Custom Extension'),
        inputSchema: ToolInputSchema(
          properties: {
            'extension': JsonSchema.string(
              description:
                  'The extension name without the "ext.flutter." prefix '
                  '(e.g., "deckNavigation.goToSlide").',
            ),
            'args': JsonSchema.object(
              description:
                  'Optional key-value pairs to pass as arguments. '
                  'Values are passed as-is to the VM service extension.',
              properties: {},
            ),
          },
          required: ['extension'],
        ),
        callback: (args, extra) async {
          final extensionName = args['extension'] as String;
          final extensionArgs =
              (args['args'] as Map<String, dynamic>?) ?? <String, dynamic>{};
          _logger.info(
            'Calling custom extension: $extensionName with args: $extensionArgs',
          );

          try {
            final response = await connector.callCustomExtension(
              extensionName,
              extensionArgs,
            );
            return CallToolResult(
              content: [TextContent(text: jsonEncode(response))],
            );
          } catch (err) {
            _logger.warning('Failed to call custom extension', err);
            return CallToolResult(
              isError: true,
              content: [TextContent(text: err.toString())],
            );
          }
        },
      )
      // Hot reload
      ..registerTool(
        'hot_reload',
        description:
            'Performs a hot reload of the Flutter app. This reloads the Dart code without restarting the app, preserving the current state. Useful after making code changes to see them reflected in the running app. Requires an active connection established via connect.',
        annotations: const ToolAnnotations(title: 'Hot Reload'),
        inputSchema: const ToolInputSchema(properties: {}),
        callback: (args, extra) async {
          _logger.info('Performing hot reload');

          try {
            final reloaded = await connector.hotReload();

            if (reloaded) {
              return CallToolResult(
                content: [
                  const TextContent(text: 'Hot reload completed successfully'),
                ],
              );
            } else {
              return CallToolResult(
                isError: true,
                content: [
                  TextContent(
                    text: 'Hot reload failed. The app may need a full restart.',
                  ),
                ],
              );
            }
          } catch (err) {
            _logger.warning('Failed to perform hot reload', err);
            return CallToolResult(
              isError: true,
              content: [TextContent(text: 'Hot reload failed: $err')],
            );
          }
        },
      );
  }

  /// Builds a widget matcher map from tool arguments.
  Map<String, dynamic> _buildMatcher(Map<String, dynamic> args) {
    final matcher = <String, dynamic>{};
    // Flatten coordinates for VM service (which only supports string->string)
    if (args['coordinates'] case final Map<String, dynamic> coordinates) {
      matcher['x'] = coordinates['x'];
      matcher['y'] = coordinates['y'];
    }
    if (args.containsKey('key')) {
      matcher['key'] = args['key'];
    }
    if (args.containsKey('text')) {
      matcher['text'] = args['text'];
    }
    if (args.containsKey('type')) {
      matcher['type'] = args['type'];
    }
    return matcher;
  }

  /// Formats an element for display.
  String _formatElement(Map<String, dynamic> element) {
    final buffer = StringBuffer();

    // Element type
    if (element['type'] != null) {
      buffer.write('Type: ${element['type']}');
    }

    // Key
    if (element['key'] != null) {
      buffer.write(', Key: "${element['key']}"');
    }

    // Text content
    if (element['text'] != null && element['text'] != '') {
      buffer.write(', Text: "${element['text']}"');
    }

    // Additional properties
    final additionalProps = <String>[];
    element.forEach((key, value) {
      if (key != 'type' && key != 'key' && key != 'text' && value != null) {
        additionalProps.add('$key: ${_formatValue(value)}');
      }
    });

    if (additionalProps.isNotEmpty) {
      buffer.write(', ${additionalProps.join(', ')}');
    }

    return buffer.toString();
  }

  /// Formats a value for display.
  String _formatValue(dynamic value) {
    if (value is String) {
      return '"$value"';
    }
    if (value is Map || value is List) {
      return jsonEncode(value);
    }
    return value.toString();
  }
}
