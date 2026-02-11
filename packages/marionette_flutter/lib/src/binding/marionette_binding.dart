import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:marionette_flutter/src/binding/marionette_configuration.dart';
import 'package:marionette_flutter/src/binding/marionette_extension_result.dart';
import 'package:marionette_flutter/src/services/element_tree_finder.dart';
import 'package:marionette_flutter/src/services/gesture_dispatcher.dart';
import 'package:marionette_flutter/src/services/log_store.dart';
import 'package:marionette_flutter/src/services/screenshot_service.dart';
import 'package:marionette_flutter/src/services/scroll_simulator.dart';
import 'package:marionette_flutter/src/services/text_input_simulator.dart';
import 'package:marionette_flutter/src/services/widget_finder.dart';
import 'package:marionette_flutter/src/services/widget_matcher.dart';
import 'package:marionette_flutter/src/version.g.dart' as v;

/// A custom binding that extends Flutter's default binding to provide
/// integration points for the Marionette MCP.
class MarionetteBinding extends WidgetsFlutterBinding {
  /// Creates and initializes the binding with the given configuration.
  ///
  /// Returns the singleton instance of [MarionetteBinding].
  static MarionetteBinding ensureInitialized([
    MarionetteConfiguration configuration = const MarionetteConfiguration(),
  ]) {
    if (_instance == null) {
      MarionetteBinding._(configuration);
    }
    return instance;
  }

  /// The singleton instance of [MarionetteBinding].
  static MarionetteBinding get instance => BindingBase.checkInstance(_instance);
  static MarionetteBinding? _instance;

  MarionetteBinding._(this.configuration);

  /// Configuration for the Marionette extensions.
  final MarionetteConfiguration configuration;

  // Service instances
  late final ElementTreeFinder _elementTreeFinder;
  late final GestureDispatcher _gestureDispatcher;
  LogStore? _logStore;
  late final ScreenshotService _screenshotService;
  late final ScrollSimulator _scrollSimulator;
  late final TextInputSimulator _textInputSimulator;
  late final WidgetFinder _widgetFinder;

  @override
  void initInstances() {
    super.initInstances();
    _instance = this;

    // Initialize services
    _widgetFinder = WidgetFinder();
    _elementTreeFinder = ElementTreeFinder(configuration);
    _gestureDispatcher = GestureDispatcher();
    _screenshotService = ScreenshotService(
      maxScreenshotSize: configuration.maxScreenshotSize,
    );
    _scrollSimulator = ScrollSimulator(_gestureDispatcher, _widgetFinder);
    _textInputSimulator = TextInputSimulator(_widgetFinder);

    // Initialize log collection if a collector is provided
    if (configuration.logCollector != null) {
      _logStore = LogStore();
      configuration.logCollector!.start(_logStore!.add);
    }
  }

  @override
  void initServiceExtensions() {
    super.initServiceExtensions();

    // Extension: Get binding version
    _registerMarionetteExtension(
      name: 'marionette.getVersion',
      callback: (params) async {
        return MarionetteExtensionResult.success({'version': v.version});
      },
    );

    // Extension: Get interactive elements tree
    _registerMarionetteExtension(
      name: 'marionette.interactiveElements',
      callback: (params) async {
        final elements = _elementTreeFinder.findInteractiveElements();
        return MarionetteExtensionResult.success({'elements': elements});
      },
    );

    // Extension: Tap element by matcher
    _registerMarionetteExtension(
      name: 'marionette.tap',
      callback: (params) async {
        final matcher = WidgetMatcher.fromJson(params);
        await _gestureDispatcher.tap(matcher, _widgetFinder, configuration);

        return MarionetteExtensionResult.success({
          'message': 'Tapped element matching: ${matcher.toJson()}',
        });
      },
    );

    // Extension: Enter text into a text field
    _registerMarionetteExtension(
      name: 'marionette.enterText',
      callback: (params) async {
        final matcher = WidgetMatcher.fromJson(params);
        final input = params['input'];

        if (input == null) {
          return MarionetteExtensionResult.invalidParams(
            'Missing required parameter: input',
          );
        }

        await _textInputSimulator.enterText(matcher, input, configuration);

        return MarionetteExtensionResult.success({
          'message': 'Entered text into element matching: ${matcher.toJson()}',
        });
      },
    );

    // Extension: Scroll until widget is visible
    _registerMarionetteExtension(
      name: 'marionette.scrollTo',
      callback: (params) async {
        final matcher = WidgetMatcher.fromJson(params);

        await _scrollSimulator.scrollUntilVisible(matcher, configuration);

        return MarionetteExtensionResult.success({
          'message': 'Scrolled to element matching: ${matcher.toJson()}',
        });
      },
    );

    // Extension: Get logs
    _registerMarionetteExtension(
      name: 'marionette.getLogs',
      callback: (params) async {
        if (_logStore == null) {
          return MarionetteExtensionResult.error(
            0,
            '''Log collection is not configured.

To enable log collection, provide a LogCollector via MarionetteConfiguration:

Option 1: Using the "logging" package (pub.dev/packages/logging)
  - Add dependency: flutter pub add marionette_logging
  - Initialize: MarionetteBinding.ensureInitialized(
      MarionetteConfiguration(logCollector: LoggingLogCollector()),
    );

Option 2: Using the "logger" package (pub.dev/packages/logger)
  - Add dependency: flutter pub add marionette_logger
  - Initialize: final collector = LoggerLogCollector();
    MarionetteBinding.ensureInitialized(
      MarionetteConfiguration(logCollector: collector),
    );
    final logger = Logger(output: MultiOutput([ConsoleOutput(), collector]));

Option 3: Using PrintLogCollector for custom logging
  - Initialize: final collector = PrintLogCollector();
    MarionetteBinding.ensureInitialized(
      MarionetteConfiguration(logCollector: collector),
    );
  - Call collector.addLog(message) from your logging listener.

See https://pub.dev/packages/marionette_flutter for more details.''',
          );
        }

        final logs = _logStore!.getLogs();

        return MarionetteExtensionResult.success({
          'logs': logs,
          'count': logs.length,
        });
      },
    );

    // Extension: Take screenshots
    _registerMarionetteExtension(
      name: 'marionette.takeScreenshots',
      callback: (params) async {
        final screenshots = await _screenshotService.takeScreenshots();

        return MarionetteExtensionResult.success({
          'screenshots': screenshots,
        });
      },
    );
  }

  /// Registers a Marionette service extension with standardized result
  /// handling.
  ///
  /// Uses [developer.registerExtension] directly, bypassing Flutter's
  /// [registerServiceExtension]. The [callback] returns a
  /// [MarionetteExtensionResult] which is pattern-matched to produce
  /// the appropriate [developer.ServiceExtensionResponse].
  void _registerMarionetteExtension({
    required String name,
    required Future<MarionetteExtensionResult> Function(
      Map<String, String> params,
    ) callback,
  }) {
    final methodName = 'ext.flutter.$name';

    developer.registerExtension(
      methodName,
      (method, parameters) async {
        // Wait for the outer event loop, same as Flutter's
        // registerServiceExtension, to avoid handling extensions in the middle
        // of a frame.
        await Future<void>.delayed(Duration.zero);

        late final MarionetteExtensionResult result;
        try {
          result = await callback(parameters);
        } on ArgumentError catch (e) {
          return developer.ServiceExtensionResponse.error(
            developer.ServiceExtensionResponse.invalidParams,
            e.message?.toString() ?? e.toString(),
          );
        } catch (exception, stack) {
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: exception,
              stack: stack,
              context: ErrorDescription(
                'during a service extension callback for "$method"',
              ),
            ),
          );

          return developer.ServiceExtensionResponse.error(
            developer.ServiceExtensionResponse.extensionError,
            json.encode(<String, String>{
              'exception': exception.toString(),
              'stack': stack.toString(),
              'method': method,
            }),
          );
        }

        switch (result) {
          case MarionetteExtensionSuccess(:final data):
            data['type'] = '_extensionType';
            data['method'] = method;
            data['status'] = 'Success';
            return developer.ServiceExtensionResponse.result(
              json.encode(data),
            );
          case MarionetteExtensionError(:final code, :final detail):
            return developer.ServiceExtensionResponse.error(
              developer.ServiceExtensionResponse.extensionErrorMin + code,
              detail,
            );
          case MarionetteExtensionInvalidParams(:final detail):
            return developer.ServiceExtensionResponse.error(
              developer.ServiceExtensionResponse.invalidParams,
              detail,
            );
        }
      },
    );
  }

  @override
  Future<void> reassembleApplication() {
    _logStore?.clear();
    return super.reassembleApplication();
  }
}
