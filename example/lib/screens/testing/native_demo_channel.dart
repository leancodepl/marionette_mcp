import 'package:flutter/services.dart';

/// Native UI implemented in the example app's platform code (MainActivity,
/// AppDelegate): dialogs, a toast and a full native screen that only the
/// native lane can drive.
abstract final class NativeDemoChannel {
  static const _channel = MethodChannel('marionette-demo/native');

  /// Shows a native alert; returns "ok", "cancel" or "dismissed".
  static Future<String> showAlert({
    required String title,
    required String message,
  }) async =>
      await _channel.invokeMethod<String>(
        'showAlert',
        {'title': title, 'message': message},
      ) ??
      'dismissed';

  /// Shows an Android toast; throws on iOS (no toasts there).
  static Future<void> showToast(String text) =>
      _channel.invokeMethod<void>('showToast', {'text': text});

  /// Opens the native form screen; returns the text typed there, or
  /// "cancelled".
  static Future<String> openNativeScreen() async =>
      await _channel.invokeMethod<String>('openNativeScreen') ?? 'cancelled';
}
