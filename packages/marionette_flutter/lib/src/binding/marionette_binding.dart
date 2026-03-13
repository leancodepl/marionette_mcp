import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:marionette_flutter/src/binding/marionette_configuration.dart';
import 'package:marionette_flutter/src/binding/marionette_extension_result.dart';
import 'package:marionette_flutter/src/binding/register_extension.dart';
import 'package:marionette_flutter/src/binding/register_extension_internal.dart';
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
    registerInternalMarionetteExtension(
      name: 'marionette.getVersion',
      callback: (params) async {
        return MarionetteExtensionResult.success({'version': v.version});
      },
    );

    // Extension: Get interactive elements tree
    registerInternalMarionetteExtension(
      name: 'marionette.interactiveElements',
      callback: (params) async {
        final elements = _elementTreeFinder.findInteractiveElements();
        return MarionetteExtensionResult.success({'elements': elements});
      },
    );

    // Extension: Tap element by matcher
    registerInternalMarionetteExtension(
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
    registerInternalMarionetteExtension(
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

    // Extension: Swipe on element
    registerInternalMarionetteExtension(
      name: 'marionette.swipe',
      callback: (params) async {
        if (params.containsKey('startX')) {
          // Coordinate-based swipe — validate all 4 coordinates
          final startXStr = params['startX'];
          final startYStr = params['startY'];
          final endXStr = params['endX'];
          final endYStr = params['endY'];

          if (startXStr == null ||
              startYStr == null ||
              endXStr == null ||
              endYStr == null) {
            return MarionetteExtensionResult.invalidParams(
              'Coordinate-based swipe requires all of: '
              'startX, startY, endX, endY',
            );
          }

          final startX = double.tryParse(startXStr);
          final startY = double.tryParse(startYStr);
          final endX = double.tryParse(endXStr);
          final endY = double.tryParse(endYStr);

          if (startX == null ||
              startY == null ||
              endX == null ||
              endY == null) {
            return MarionetteExtensionResult.invalidParams(
              'Invalid coordinate values. '
              'startX, startY, endX, endY must be valid numbers.',
            );
          }

          await _gestureDispatcher.drag(
            Offset(startX, startY),
            Offset(endX, endY),
          );

          return MarionetteExtensionResult.success({
            'message': 'Swiped from ($startX, $startY) to ($endX, $endY)',
          });
        }

        // Element + direction swipe
        final matcher = WidgetMatcher.fromJson(params);
        final direction = params['direction'];
        if (direction == null) {
          return MarionetteExtensionResult.invalidParams(
            'Missing required parameter: direction '
            '(must be one of: left, right, up, down)',
          );
        }

        final distanceStr = params['distance'];
        final double distance;
        if (distanceStr != null) {
          final parsed = double.tryParse(distanceStr);
          if (parsed == null) {
            return MarionetteExtensionResult.invalidParams(
              'Invalid distance value: "$distanceStr". '
              'Must be a valid number.',
            );
          }
          distance = parsed;
        } else {
          distance = 200.0;
        }

        await _gestureDispatcher.swipe(
          matcher,
          _widgetFinder,
          configuration,
          direction: direction,
          distance: distance,
        );

        return MarionetteExtensionResult.success({
          'message':
              'Swiped $direction on element matching: ${matcher.toJson()}',
        });
      },
    );

    // Extension: Scroll until widget is visible
    registerInternalMarionetteExtension(
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
    registerInternalMarionetteExtension(
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
    registerInternalMarionetteExtension(
      name: 'marionette.takeScreenshots',
      callback: (params) async {
        final screenshots = await _screenshotService.takeScreenshots();

        return MarionetteExtensionResult.success({
          'screenshots': screenshots,
        });
      },
    );

    // Extension: List custom extensions
    registerInternalMarionetteExtension(
      name: 'marionette.listExtensions',
      callback: (params) async {
        return MarionetteExtensionResult.success({
          'extensions': [
            for (final ext in customExtensionRegistry)
              {
                'name': ext.name,
                if (ext.description != null) 'description': ext.description,
              },
          ],
        });
      },
    );
  }

  @override
  Future<void> reassembleApplication() {
    _logStore?.clear();
    return super.reassembleApplication();
  }
}
