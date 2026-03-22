import 'package:marionette_flutter/src/services/native_screencast_server.dart';
import 'package:marionette_flutter/src/services/screencast_server.dart';

ScreencastServer createScreencastServer({
  required ScreencastServiceFactory screencastServiceFactory,
  required ViewportSizeProvider viewportSizeProvider,
}) {
  return NativeScreencastServer(
    screencastServiceFactory: screencastServiceFactory,
    viewportSizeProvider: viewportSizeProvider,
  );
}
