import 'package:marionette_cli/src/cli/native_command.dart';
import 'package:marionette_cli/src/instance_registry.dart';
import 'package:marionette_cli/src/native_session_registry.dart';
import 'package:marionette_mcp/src/native_service/native_service_context.dart';
import 'package:marionette_mcp/src/native_service/tools/bridge_tools.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';
import 'package:mcp_dart/mcp_dart.dart';

class NativeMapFlutterRectCommand extends NativeCommand {
  NativeMapFlutterRectCommand(this.nativeRegistry, this._instances) {
    argParser
      ..addOption(
        'x',
        help: 'Left of the Flutter bounds (logical pixels).',
        mandatory: true,
      )
      ..addOption(
        'y',
        help: 'Top of the Flutter bounds (logical pixels).',
        mandatory: true,
      )
      ..addOption('width', help: 'Width of the Flutter bounds.')
      ..addOption('height', help: 'Height of the Flutter bounds.');
  }

  @override
  final NativeSessionRegistry nativeRegistry;
  final InstanceRegistry _instances;
  VmServiceConnector? _flutter;

  @override
  String get name => 'native-map-flutter-rect';

  @override
  String get description =>
      'Convert bounds from get-interactive-elements (Flutter logical pixels) '
      'to native screenshot pixels, for native gestures on platform views. '
      'Needs --instance or --uri for the Flutter app too.';

  @override
  Map<String, dynamic> toolArguments() {
    if (_flutterUri() == null) {
      usageException(
        'native-map-flutter-rect also needs the Flutter app: pass '
        '-i <instance> or --uri <ws-uri> before the command.',
      );
    }
    return NativeCommand.compact({
      'x': number('x'),
      'y': number('y'),
      'width': number('width'),
      'height': number('height'),
    });
  }

  @override
  Future<Map<String, dynamic>> Function()? get flutterViewMetrics {
    final uri = _flutterUri();
    if (uri == null) return null;
    return () async {
      final connector = _flutter = VmServiceConnector();
      await connector.connect(uri);
      return connector.getViewMetrics();
    };
  }

  /// The Flutter app from the global `--uri` or `--instance`, if given.
  String? _flutterUri() {
    final uri = globalResults?['uri'] as String?;
    if (uri != null && uri.isNotEmpty) return uri;
    final instance = globalResults?['instance'] as String?;
    if (instance == null || instance.isEmpty) return null;
    final info = _instances.get(instance);
    if (info == null) {
      usageException(
        'Instance "$instance" not found. '
        'Use "marionette list" to see registered instances.',
      );
    }
    return info.uri;
  }

  @override
  Future<CallToolResult> execute(
    NativeServiceContext context,
    Map<String, dynamic> args,
  ) =>
      handleNativeMapFlutterRect(context, args);

  @override
  Future<void> cleanup() async {
    await _flutter?.disconnect();
    _flutter = null;
  }
}
