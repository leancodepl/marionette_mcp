import 'package:jaspr/jaspr.dart';
import 'package:marionette_website/components/code_block.dart';
import 'package:marionette_website/components/tabs.dart';
import 'package:marionette_website/site.dart';

const _mcpServers = '''
{
  "mcpServers": {
    "marionette": { "command": "marionette_mcp", "args": [] }
  }
}''';

const _copilot = '''
{
  "servers": {
    "marionette": { "command": "marionette_mcp", "args": [] }
  }
}''';

const _promptWithUri = '''
Connect to ws://127.0.0.1:9101/V3N5aBc=/ws. Open the login screen, sign in
with test@example.com, and check the logs that the sign-in request fired.''';

const _promptAgentRuns = '''
Run the app with flutter run and connect to it. Open the login screen, sign
in with test@example.com, and check the logs that the sign-in request fired.''';

/// The first prompt, for both ways to get the VM service URI to the agent.
Component firstPromptTabs({required String name}) => Tabs(
  name: name,
  groupLabel: 'Who starts the app',
  tabs: const [
    TabItem('uri', 'You run the app', [
      CodeBlock(source: _promptWithUri, language: .console, title: 'prompt'),
    ]),
    TabItem('agent', 'The agent runs it', [
      CodeBlock(source: _promptAgentRuns, language: .console, title: 'prompt'),
    ]),
  ],
);

/// An agent the MCP server can be registered with: by running [command], or
/// by adding [config] to its [configFile].
class McpClient {
  const McpClient(
    this.id,
    this.label, {
    this.command,
    this.configFile,
    this.config,
    this.inQuickStart = true,
  });

  final String id;
  final String label;
  final String? command;
  final String? configFile;
  final String? config;

  /// Whether the landing page's quick start offers it; the docs list all.
  final bool inQuickStart;
}

const mcpClients = [
  McpClient('claude', 'Claude Code', command: claudeMcpAddCommand),
  McpClient(
    'codex',
    'Codex',
    command: 'codex mcp add marionette -- marionette_mcp',
  ),
  McpClient(
    'cursor',
    'Cursor',
    configFile: '.cursor/mcp.json',
    config: _mcpServers,
  ),
  McpClient(
    'gemini',
    'Gemini CLI',
    command: 'gemini mcp add marionette marionette_mcp',
  ),
  McpClient(
    'copilot-cli',
    'Copilot CLI',
    command: 'copilot mcp add marionette -- marionette_mcp',
  ),
  McpClient(
    'vscode',
    'Copilot in VS Code',
    configFile: 'mcp.json',
    config: _copilot,
    inQuickStart: false,
  ),
  McpClient(
    'antigravity',
    'Antigravity',
    configFile: 'mcp_config.json',
    config: _mcpServers,
  ),
];

/// How to register the MCP server with each client, one tab per client.
Component clientTabs({required String name}) => Tabs(
  name: name,
  groupLabel: 'AI tool',
  tabs: [
    for (final client in mcpClients)
      TabItem(client.id, client.label, [
        if (client.command case final command?)
          CodeBlock(source: command, language: .shell, title: 'terminal')
        else
          CodeBlock(
            source: client.config!,
            language: .json,
            title: client.configFile,
          ),
      ]),
  ],
);
