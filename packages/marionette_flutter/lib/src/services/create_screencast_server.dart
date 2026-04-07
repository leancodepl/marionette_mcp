import 'package:marionette_flutter/src/services/screencast_server.dart';

import 'create_screencast_server_native.dart'
    if (dart.library.js_interop) 'create_screencast_server_web.dart'
    as platform;

/// Creates the platform-appropriate [ScreencastServer].
///
/// On native (iOS, Android, desktop), returns [NativeScreencastServer].
/// On web, returns [ScreencastWebServer].
ScreencastServer createScreencastServer({
  required ScreencastServiceFactory screencastServiceFactory,
  required ViewportSizeProvider viewportSizeProvider,
}) {
  return platform.createScreencastServer(
    screencastServiceFactory: screencastServiceFactory,
    viewportSizeProvider: viewportSizeProvider,
  );
}
