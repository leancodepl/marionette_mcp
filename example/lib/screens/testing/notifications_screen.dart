import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'native_demo_channel.dart';

/// Payload of the notification the app was last opened from; outlives the
/// screen so a tap that relaunches the app is still reported.
final ValueNotifier<String?> _openedFrom = ValueNotifier(null);

final FlutterLocalNotificationsPlugin _notifications =
    FlutterLocalNotificationsPlugin();
Future<void>? _initialized;

Future<void> _initialize() => _initialized ??= () async {
      await _notifications.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (response) =>
            _openedFrom.value = response.payload,
      );
      final launch = await _notifications.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        _openedFrom.value = launch!.notificationResponse?.payload;
      }
    }();

/// Notifications and toasts: a local notification posted after a delay
/// (so the app can be sent to the background first), opening the app from
/// it, and an Android Toast.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  String _status = 'idle';

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _notifyLater() async {
    await _initialize();
    final allowed = Platform.isAndroid
        ? await _notifications
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission()
        : await _notifications
            .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(alert: true, badge: true, sound: true);
    if (allowed == false) {
      if (mounted) setState(() => _status = 'notifications not allowed');
      return;
    }
    if (mounted) setState(() => _status = 'notification in 3 s');
    const title = 'Marionette';
    const body = 'Local notification — tap to open the app';
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'marionette_demo',
        'Marionette demo',
        importance: Importance.max,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(presentAlert: true, presentBanner: true),
    );
    if (Platform.isIOS) {
      // iOS suspends the app in the background, so a Dart timer would only
      // fire after it comes back; the system delivers a scheduled one.
      tz_data.initializeTimeZones();
      try {
        await _notifications.zonedSchedule(
          1,
          title,
          body,
          tz.TZDateTime.now(tz.UTC).add(const Duration(seconds: 3)),
          details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: 'demo-payload',
        );
        if (mounted) setState(() => _status = 'notification scheduled');
      } catch (error) {
        if (mounted) setState(() => _status = 'schedule failed: $error');
      }
      return;
    }
    // Android keeps the process running in the background; a timer avoids
    // the exact-alarm permission a scheduled notification would need.
    await Future<void>.delayed(const Duration(seconds: 3));
    await _notifications.show(1, title, body, details, payload: 'demo-payload');
    if (mounted) setState(() => _status = 'notification posted');
  }

  Future<void> _toast() async {
    try {
      await NativeDemoChannel.showToast('Native toast from Marionette');
      if (mounted) setState(() => _status = 'toast shown');
    } catch (error) {
      if (mounted) setState(() => _status = 'toast: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Post a notification in 3 s (send the app to the background '
            'with native_press_key key=home to see a banner), read it '
            'with native_notifications action=open and tap it to come back.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _notifyLater,
            child: const Text('Notify in 3 s'),
          ),
          if (Platform.isAndroid)
            OutlinedButton(
              onPressed: _toast,
              child: const Text('Show Android toast'),
            ),
          Text('Status: $_status'),
          ValueListenableBuilder(
            valueListenable: _openedFrom,
            builder: (context, payload, _) =>
                Text('Opened from notification: ${payload ?? 'no'}'),
          ),
        ],
      ),
    );
  }
}
