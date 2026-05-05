import 'package:marionette_flutter/src/binding/marionette_extension_result.dart';
import 'package:marionette_flutter/src/binding/register_extension_internal.dart';
import 'package:marionette_flutter/src/services/screencast_server.dart';
import 'package:marionette_flutter/src/services/screenshot_service.dart';

/// Registers media-related `marionette.*` extensions: takeScreenshots,
/// startScreencast, stopScreencast.
void registerMediaExtensions({
  required ScreenshotService screenshotService,
  required ScreencastServer screencastServer,
}) {
  registerInternalMarionetteExtension(
    name: 'marionette.takeScreenshots',
    callback: (params) async {
      final screenshots = await screenshotService.takeScreenshots();
      return MarionetteExtensionResult.success({
        'screenshots': screenshots,
      });
    },
  );

  registerInternalMarionetteExtension(
    name: 'marionette.startScreencast',
    callback: (params) async {
      try {
        final maxWidth = int.tryParse(params['maxWidth'] ?? '');
        final maxHeight = int.tryParse(params['maxHeight'] ?? '');
        final wsPort = int.tryParse(params['wsPort'] ?? '');

        final result = await screencastServer.startScreencast(
          maxWidth: maxWidth,
          maxHeight: maxHeight,
          wsPort: wsPort,
        );
        return MarionetteExtensionResult.success(result);
      } on StateError catch (e) {
        return MarionetteExtensionResult.error(0, e.message);
      }
    },
  );

  registerInternalMarionetteExtension(
    name: 'marionette.stopScreencast',
    callback: (params) async {
      await screencastServer.stopScreencast();
      return MarionetteExtensionResult.success({
        'message': 'Screencast stopped',
      });
    },
  );
}
