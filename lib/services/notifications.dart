import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Shows local notifications for task and meeting updates.
class Notifications {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static int _id = 0;

  static Future<void> init() async {
    if (kIsWeb) return;
    try {
      await _plugin.initialize(
        InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
        ),
      );
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      _ready = true;
    } catch (e) {
      debugPrint('Notifications unavailable: $e');
    }
  }

  static Future<bool> show(String title, String body, {bool meeting = false}) async {
    if (!_ready) return false;
    try {
      await _plugin.show(
        _id++,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            meeting ? 'meetings' : 'tasks',
            meeting ? 'Meeting updates' : 'Task updates',
            channelDescription: meeting ? 'Newly scheduled meetings' : 'New and reassigned tasks',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
      return true;
    } catch (error) {
      debugPrint('Could not show notification: $error');
      return false;
    }
  }
}
