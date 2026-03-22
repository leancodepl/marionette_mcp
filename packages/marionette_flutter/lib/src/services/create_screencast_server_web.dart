import 'dart:ui';

import 'package:marionette_flutter/src/services/frame_capturer_web.dart';
import 'package:marionette_flutter/src/services/screencast_server.dart';
import 'package:marionette_flutter/src/services/screencast_service.dart';
import 'package:marionette_flutter/src/services/screencast_web_server.dart';

ScreencastServer createScreencastServer({
  required ScreencastServiceFactory screencastServiceFactory,
  required ViewportSizeProvider viewportSizeProvider,
}) {
  // Override the factory to inject the web-compatible frame capturer.
  // The default capturer uses scene.toImage() which produces blank frames
  // on Flutter web; webFrameCapturer uses OffsetLayer.toImage() instead.
  return ScreencastWebServer(
    screencastServiceFactory: ({Size? maxSize}) =>
        ScreencastService(frameCapturer: webFrameCapturer, maxSize: maxSize),
    viewportSizeProvider: viewportSizeProvider,
  );
}
