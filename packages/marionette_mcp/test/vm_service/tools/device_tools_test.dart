import 'package:logging/logging.dart' as logging;
import 'package:marionette_mcp/src/vm_service/tools/device_tools.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

/// Captures the arguments the tool forwards to the connector.
class _CapturingConnector implements VmServiceConnector {
  final List<Map<String, Object?>> calls = [];
  Map<String, dynamic> nextResponse = const {
    'message': 'Device config updated'
  };
  Object? nextError;

  @override
  Future<Map<String, dynamic>> setDeviceConfig({
    double? textScale,
    bool? boldText,
    String? platformBrightness,
    bool? disableAnimations,
    bool reset = false,
  }) async {
    calls.add({
      'textScale': textScale,
      'boldText': boldText,
      'platformBrightness': platformBrightness,
      'disableAnimations': disableAnimations,
      'reset': reset,
    });
    if (nextError case final error?) {
      throw error;
    }
    return nextResponse;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  group('set_device_config', () {
    late _CapturingConnector connector;
    late logging.Logger logger;

    setUp(() {
      connector = _CapturingConnector();
      logger = logging.Logger.detached('test');
    });

    String textOf(CallToolResult result) =>
        (result.content.single as TextContent).text;

    test('forwards every field', () async {
      await setDeviceConfig(connector, logger, {
        'text_scale': 1.5,
        'bold_text': true,
        'platform_brightness': 'dark',
        'disable_animations': true,
      });

      expect(connector.calls.single, {
        'textScale': 1.5,
        'boldText': true,
        'platformBrightness': 'dark',
        'disableAnimations': true,
        'reset': false,
      });
    });

    test('widens an integer text scale to a double', () async {
      await setDeviceConfig(connector, logger, {'text_scale': 2});

      expect(connector.calls.single['textScale'], 2.0);
    });

    test('forwards reset on its own', () async {
      await setDeviceConfig(connector, logger, {'reset': true});

      expect(connector.calls.single['reset'], isTrue);
    });

    test('relays the message from the app', () async {
      connector.nextResponse = const {'message': 'Device config reset'};

      final result = await setDeviceConfig(connector, logger, {'reset': true});

      expect(textOf(result), 'Device config reset');
      expect(result.isError, isNot(true));
    });

    test('rejects a call that sets nothing', () async {
      final result = await setDeviceConfig(connector, logger, const {});

      expect(result.isError, isTrue);
      expect(textOf(result), contains('At least one parameter'));
      expect(connector.calls, isEmpty);
    });

    test('rejects reset=false with no other parameter', () async {
      final result = await setDeviceConfig(connector, logger, {'reset': false});

      expect(result.isError, isTrue);
      expect(connector.calls, isEmpty);
    });

    test('rejects a non-positive text scale', () async {
      final result = await setDeviceConfig(connector, logger, {
        'text_scale': 0,
      });

      expect(result.isError, isTrue);
      expect(textOf(result), contains('greater than 0'));
      expect(connector.calls, isEmpty);
    });

    test('rejects an unknown brightness', () async {
      final result = await setDeviceConfig(connector, logger, {
        'platform_brightness': 'sepia',
      });

      expect(result.isError, isTrue);
      expect(textOf(result), contains('light, dark'));
      expect(connector.calls, isEmpty);
    });

    test('surfaces the setup instructions an unprepared app returns', () async {
      // The binding answers with help text when no MarionetteDeviceConfig is
      // mounted; it must reach the agent verbatim, not as a bare failure.
      connector.nextError = VmServiceExtensionException(
        'Extension marionette.setDeviceConfig failed',
        error: 'Device config overrides are not available in this app.',
      );

      final result = await setDeviceConfig(connector, logger, {
        'text_scale': 2,
      });

      expect(result.isError, isTrue);
      expect(textOf(result), contains('not available in this app'));
    });
  });
}
