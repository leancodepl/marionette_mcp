import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';

/// Output contract for tools that return a short action confirmation.
final messageOutputSchema = ToolOutputSchema(
  properties: {'message': JsonSchema.string()},
  required: ['message'],
);

/// App extensions may return arbitrary fields inside the response envelope.
final extensionResponseOutputSchema = ToolOutputSchema(
  properties: {
    'response': JsonSchema.object(properties: {}, additionalProperties: true),
  },
  required: ['response'],
);

/// Keeps the existing confirmation text alongside its structured message.
CallToolResult messageResult(
  String message, {
  Map<String, dynamic> fields = const {},
}) =>
    CallToolResult(
      content: [TextContent(text: message)],
      structuredContent: {'message': message, ...fields},
    );

/// Keeps an extension's JSON text alongside the original response object.
CallToolResult extensionResponseResult(Map<String, dynamic> response) =>
    CallToolResult(
      content: [TextContent(text: jsonEncode(response))],
      structuredContent: {'response': response},
    );
