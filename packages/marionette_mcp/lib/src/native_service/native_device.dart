/// Device operations of the native lane that do not go through the
/// WebDriver session: permissions, URLs, app lifecycle, notifications,
/// location, device facts. Backed by `adb` (Android) and `xcrun simctl`
/// (iOS Simulator). See docs/native-lane-decisions.md#d12.
library;

/// A permission group with the same name on both platforms; each maps to
/// one or more native permissions (e.g. `location` → fine + coarse on
/// Android).
enum NativePermission {
  camera,
  microphone,
  photos,
  location,
  contacts,
  calendar,
  notifications,

  /// Every permission the app can have changed this way.
  all;

  static NativePermission? tryParse(Object? raw) {
    for (final value in values) {
      if (value.name == raw) return value;
    }
    return null;
  }

  static String get commaSeparatedNames => values.map((v) => v.name).join(', ');
}

/// What to do with a permission.
enum NativePermissionAction {
  /// Allow without a dialog.
  grant,

  /// Deny without a dialog.
  revoke,

  /// Back to "not decided": the app asks again on next use.
  reset;

  static NativePermissionAction? tryParse(Object? raw) {
    for (final value in values) {
      if (value.name == raw) return value;
    }
    return null;
  }
}

/// Outcome of [NativeDevice.setPermission].
class NativePermissionChange {
  const NativePermissionChange({
    required this.nativeNames,
    this.notes = const [],
  });

  /// Platform permissions that were changed (e.g.
  /// `android.permission.CAMERA`, iOS `camera`).
  final List<String> nativeNames;

  /// Caveats worth telling the agent (e.g. a partial reset).
  final List<String> notes;
}

/// Facts about the device that do not need the UI session.
class NativeDeviceInfo {
  const NativeDeviceInfo({
    required this.osVersion,
    required this.model,
    required this.isEmulator,
    this.apiLevel,
    this.id,
  });

  /// e.g. `Android 9`, `iOS 18.6`.
  final String osVersion;

  /// Device model or simulator name.
  final String model;

  /// Emulator / simulator rather than a physical device.
  final bool isEmulator;

  /// Android API level; null on iOS.
  final int? apiLevel;

  /// Android serial or simulator UDID, when known.
  final String? id;

  Map<String, Object?> toJson() => {
        'osVersion': osVersion,
        if (apiLevel != null) 'apiLevel': apiLevel,
        'model': model,
        'isEmulator': isEmulator,
        if (id != null) 'id': id,
      };
}

/// Device operations outside the WebDriver session (D12).
///
/// Failures are reported as `NativeLaneException`s with a hint; operations
/// a platform cannot do throw `NativeUnsupportedException`.
abstract interface class NativeDevice {
  /// OS version, model and similar facts.
  Future<NativeDeviceInfo> info();

  /// Applies [action] to [permission] for app [appId]. Changing a
  /// permission may terminate the app (Android always on revoke, iOS for
  /// most services).
  Future<NativePermissionChange> setPermission(
    NativePermissionAction action,
    NativePermission permission,
    String appId,
  );

  /// Opens [url] (a web page or a deep link) with the system handler.
  Future<void> openUrl(String url);

  /// Starts [appId], or brings its existing instance to the front with its
  /// state intact when it is already running.
  Future<void> activateApp(String appId);

  /// Stops [appId]; returns false when it was not running.
  Future<bool> terminateApp(String appId);

  /// Whether [appId] has a running process; null when unknown.
  Future<bool?> isAppRunning(String appId);

  /// Opens the notification shade. Throws `NativeUnsupportedException` when
  /// the platform needs a gesture instead (iOS).
  Future<void> openNotifications();

  /// Closes the notification shade (see [openNotifications]).
  Future<void> closeNotifications();

  /// Delivers a push notification [payload] (with an `aps` key) to [appId].
  Future<void> pushNotification(String appId, Map<String, dynamic> payload);

  /// Sets the simulated GPS position (emulators and simulators only).
  Future<void> setLocation(double latitude, double longitude);
}

/// Whether [appId] belongs to the system (launcher, permission dialogs,
/// pickers, settings) rather than to an app under test — used to pick the
/// default app (docs/native-lane-decisions.md#d7).
bool isSystemAppId(String appId) {
  if (appId == 'android' || appId.isEmpty) return true;
  return _systemAppPrefixes.any(appId.startsWith);
}

/// Package / bundle id prefixes of system apps. Google and AOSP system
/// components, common OEM shells, and every Apple app.
const _systemAppPrefixes = [
  'com.android.',
  'com.google.android.',
  'com.samsung.',
  'com.sec.android.',
  'com.miui.',
  'com.xiaomi.',
  'com.huawei.',
  'com.oppo.',
  'com.coloros.',
  'com.apple.',
];

/// Android permissions for [permission] on API level [sdk]. Empty when the
/// permission does not exist at that level (notifications before API 33).
List<String> androidPermissionNames(NativePermission permission, int sdk) => [
      for (final name in _androidPermissionSuffixes(permission, sdk))
        'android.permission.$name',
    ];

List<String> _androidPermissionSuffixes(NativePermission permission, int sdk) =>
    switch (permission) {
      NativePermission.camera => ['CAMERA'],
      NativePermission.microphone => ['RECORD_AUDIO'],
      NativePermission.location => [
          'ACCESS_FINE_LOCATION',
          'ACCESS_COARSE_LOCATION',
        ],
      NativePermission.contacts => ['READ_CONTACTS', 'WRITE_CONTACTS'],
      NativePermission.calendar => ['READ_CALENDAR', 'WRITE_CALENDAR'],
      NativePermission.photos => sdk >= 33
          ? [
              'READ_MEDIA_IMAGES',
              'READ_MEDIA_VIDEO',
              if (sdk >= 34) 'READ_MEDIA_VISUAL_USER_SELECTED',
            ]
          : ['READ_EXTERNAL_STORAGE'],
      NativePermission.notifications => sdk >= 33 ? ['POST_NOTIFICATIONS'] : [],
      NativePermission.all => [
          for (final single in NativePermission.values)
            if (single != NativePermission.all)
              ..._androidPermissionSuffixes(single, sdk),
        ],
    };

/// `simctl privacy` service for [permission], or null when the simulator
/// cannot change it (notifications).
String? iosPrivacyService(NativePermission permission) => switch (permission) {
      // `camera` is accepted by simctl although its help does not list it.
      NativePermission.camera => 'camera',
      NativePermission.microphone => 'microphone',
      NativePermission.photos => 'photos',
      NativePermission.location => 'location',
      NativePermission.contacts => 'contacts',
      NativePermission.calendar => 'calendar',
      NativePermission.notifications => null,
      NativePermission.all => 'all',
    };
