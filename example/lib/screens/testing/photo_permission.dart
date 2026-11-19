import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// The permission for the photo library. Android 12 (API 32) and older have
/// no photos permission — permission_handler reports it denied without a
/// dialog there — so storage stands in for it, as permission_handler's docs
/// advise.
Future<Permission> photoLibraryPermission() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return Permission.photos;
  }
  final android = await DeviceInfoPlugin().androidInfo;
  return android.version.sdkInt <= 32 ? Permission.storage : Permission.photos;
}
