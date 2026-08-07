import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// View type registered in Android [MainActivity] and iOS [AppDelegate].
const kNativeControlsPlatformViewType = 'marionette-demo-native-controls';

/// Embedded native label, text field, and button (§1a plain platform view).
class NativeControlsPlatformView extends StatelessWidget {
  const NativeControlsPlatformView({super.key});

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return const Center(
        child: Text('Platform views are not exercised on web in this demo.'),
      );
    }

    if (Platform.isAndroid) {
      return AndroidView(
        viewType: kNativeControlsPlatformViewType,
        layoutDirection: TextDirection.ltr,
        creationParamsCodec: const StandardMessageCodec(),
      );
    }

    if (Platform.isIOS) {
      return UiKitView(
        viewType: kNativeControlsPlatformViewType,
        layoutDirection: TextDirection.ltr,
        creationParamsCodec: const StandardMessageCodec(),
      );
    }

    return const Center(
      child: Text('Platform views are only supported on Android and iOS.'),
    );
  }
}
