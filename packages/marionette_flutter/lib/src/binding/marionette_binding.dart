import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:marionette_flutter/src/binding/marionette_configuration.dart';
import 'package:marionette_flutter/src/services/element_tree_finder.dart';
import 'package:marionette_flutter/src/services/gesture_dispatcher.dart';
import 'package:marionette_flutter/src/services/log_collector.dart';
import 'package:marionette_flutter/src/services/screenshot_service.dart';
import 'package:marionette_flutter/src/services/scroll_simulator.dart';
import 'package:marionette_flutter/src/services/text_input_simulator.dart';
import 'package:marionette_flutter/src/services/widget_finder.dart';
import 'package:marionette_flutter/src/services/widget_matcher.dart';

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
  late final LogCollector _logCollector;
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
    _logCollector = LogCollector();
    _screenshotService = ScreenshotService();
    _scrollSimulator = ScrollSimulator(_gestureDispatcher, _widgetFinder);
    _textInputSimulator = TextInputSimulator(_widgetFinder);

    // Initialize log collection
    _logCollector.initialize();
  }

  @override
  void initServiceExtensions() {
    super.initServiceExtensions();

    // Extension: Get interactive elements tree
    registerServiceExtension(
      name: 'marionette.interactiveElements',
      callback: (params) async {
        try {
          final elements = _elementTreeFinder.findInteractiveElements();
          return <String, dynamic>{'status': 'Success', 'elements': elements};
        } catch (err, st) {
          return <String, dynamic>{
            'status': 'Error',
            'error': err.toString(),
            'stackTrace': st.toString(),
          };
        }
      },
    );

    // Extension: Tap element by matcher
    registerServiceExtension(
      name: 'marionette.tap',
      callback: (params) async {
        try {
          final matcher = WidgetMatcher.fromJson(params);
          await _gestureDispatcher.tap(matcher, _widgetFinder, configuration);

          return <String, dynamic>{
            'status': 'Success',
            'message': 'Tapped element matching: ${matcher.toJson()}',
          };
        } catch (err, st) {
          return <String, dynamic>{
            'status': 'Error',
            'error': err.toString(),
            'stackTrace': st.toString(),
          };
        }
      },
    );

    // Extension: Enter text into a text field
    registerServiceExtension(
      name: 'marionette.enterText',
      callback: (params) async {
        try {
          final matcher = WidgetMatcher.fromJson(params);
          final input = params['input'];

          if (input == null) {
            return <String, dynamic>{
              'status': 'Error',
              'error': 'Missing required parameter: input',
            };
          }

          await _textInputSimulator.enterText(matcher, input, configuration);

          return <String, dynamic>{
            'status': 'Success',
            'message':
                'Entered text into element matching: ${matcher.toJson()}',
          };
        } catch (err, st) {
          return <String, dynamic>{
            'status': 'Error',
            'error': err.toString(),
            'stackTrace': st.toString(),
          };
        }
      },
    );

    // Extension: Scroll until widget is visible
    registerServiceExtension(
      name: 'marionette.scrollTo',
      callback: (params) async {
        try {
          final matcher = WidgetMatcher.fromJson(params);

          await _scrollSimulator.scrollUntilVisible(matcher, configuration);

          return <String, dynamic>{
            'status': 'Success',
            'message': 'Scrolled to element matching: ${matcher.toJson()}',
          };
        } catch (err, st) {
          return <String, dynamic>{
            'status': 'Error',
            'error': err.toString(),
            'stackTrace': st.toString(),
          };
        }
      },
    );

    // Extension: Get logs
    registerServiceExtension(
      name: 'marionette.getLogs',
      callback: (params) async {
        try {
          final logs = _logCollector.getFormattedLogs();

          return <String, dynamic>{
            'status': 'Success',
            'logs': logs,
            'count': logs.length,
          };
        } catch (err, st) {
          return <String, dynamic>{
            'status': 'Error',
            'error': err.toString(),
            'stackTrace': st.toString(),
          };
        }
      },
    );

    // Extension: Take screenshots
    registerServiceExtension(
      name: 'marionette.takeScreenshots',
      callback: (params) async {
        try {
          final screenshots = await _screenshotService.takeScreenshots();

          return <String, dynamic>{
            'status': 'Success',
            'screenshots': screenshots,
          };
        } catch (err, st) {
          return <String, dynamic>{
            'status': 'Error',
            'error': err.toString(),
            'stackTrace': st.toString(),
          };
        }
      },
    );
  }

  @override
  Future<void> reassembleApplication() {
    _logCollector.clear();
    return super.reassembleApplication();
  }
}
