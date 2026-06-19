import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:marionette_flutter/src/binding/extensions/gesture_extensions.dart';
import 'package:marionette_flutter/src/binding/extensions/info_extensions.dart';
import 'package:marionette_flutter/src/binding/extensions/keyboard_extensions.dart';
import 'package:marionette_flutter/src/binding/extensions/media_extensions.dart';
import 'package:marionette_flutter/src/binding/extensions/text_extensions.dart';
import 'package:marionette_flutter/src/binding/marionette_configuration.dart';
import 'package:marionette_flutter/src/binding/marionette_extension_result.dart';
import 'package:marionette_flutter/src/binding/register_extension_internal.dart';
import 'package:marionette_flutter/src/services/create_screencast_server.dart';
import 'package:marionette_flutter/src/services/element_tree_finder.dart';
import 'package:marionette_flutter/src/services/gesture_dispatcher.dart';
import 'package:marionette_flutter/src/services/keyboard_simulator.dart';
import 'package:marionette_flutter/src/services/log_store.dart';
import 'package:marionette_flutter/src/services/screencast_server.dart';
import 'package:marionette_flutter/src/services/screencast_service.dart';
import 'package:marionette_flutter/src/services/screenshot_service.dart';
import 'package:marionette_flutter/src/services/scroll_simulator.dart';
import 'package:marionette_flutter/src/services/text_input_simulator.dart';
import 'package:marionette_flutter/src/services/widget_finder.dart';

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
  late final KeyboardSimulator _keyboardSimulator;
  LogStore? _logStore;
  late final ScreenshotService _screenshotService;
  late final ScrollSimulator _scrollSimulator;
  late final TextInputSimulator _textInputSimulator;
  late final ScreencastServer _screencastServer;
  late final WidgetFinder _widgetFinder;

  @override
  void initInstances() {
    super.initInstances();
    _instance = this;

    _widgetFinder = WidgetFinder();
    _elementTreeFinder = ElementTreeFinder(configuration);
    _gestureDispatcher = GestureDispatcher();
    _screenshotService = ScreenshotService(
      maxScreenshotSize: configuration.maxScreenshotSize,
    );
    _screencastServer = createScreencastServer(
      screencastServiceFactory: ({Size? maxSize}) =>
          ScreencastService(maxSize: maxSize),
      viewportSizeProvider: () {
        final renderView = renderViews.firstOrNull;
        return renderView?.flutterView.physicalSize ?? Size.zero;
      },
    );
    _scrollSimulator = ScrollSimulator(_gestureDispatcher, _widgetFinder);
    _textInputSimulator = TextInputSimulator(_widgetFinder);
    _keyboardSimulator = KeyboardSimulator();

    if (configuration.logCollector != null) {
      _logStore = LogStore();
      configuration.logCollector!.start(_logStore!.add);
    }
  }

  @override
  void initServiceExtensions() {
    super.initServiceExtensions();

    registerInfoExtensions(
      elementTreeFinder: _elementTreeFinder,
      logStoreProvider: () => _logStore,
    );
    registerGestureExtensions(
      gestureDispatcher: _gestureDispatcher,
      widgetFinder: _widgetFinder,
      scrollSimulator: _scrollSimulator,
      configuration: configuration,
    );
    registerTextExtensions(
      textInputSimulator: _textInputSimulator,
      configuration: configuration,
    );
    registerKeyboardExtensions(
      keyboardSimulator: _keyboardSimulator,
    );
    registerMediaExtensions(
      screenshotService: _screenshotService,
      screencastServer: _screencastServer,
    );

    // pressBackButton stays inline because it calls handlePopRoute(), which
    // is an instance method on the binding itself.
    registerInternalMarionetteExtension(
      name: 'marionette.pressBackButton',
      callback: (params) async {
        // This acts like a normal, non-predictive back.
        // For details, see https://github.com/flutter/flutter/blob/main/packages/flutter/lib/src/widgets/binding.dart#L1196
        final didPop = await handlePopRoute();
        return MarionetteExtensionResult.success({
          'didPop': didPop,
          'message': didPop
              ? 'Back button pressed, route was popped'
              : 'Back button pressed, no route to pop (app may exit)',
        });
      },
    );
  }

  @override
  Future<void> reassembleApplication() async {
    _logStore?.clear();
    await _screencastServer.stopScreencast();
    return super.reassembleApplication();
  }
}
