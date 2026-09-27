import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';

/// Local (and optionally FCM-bridged) notifications for order events.
///
/// Backend should send SMS / FCM for true push; this layer shows alerts when
/// the app detects a status change or receives a foreground notification payload.
class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService instance = PushNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _ready = false;
  int _id = 1000;

  Future<void> init() async {
    if (_ready) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
    _ready = true;
  }

  Future<void> showOrderUpdate({
    required String title,
    required String body,
    String? orderNumber,
  }) async {
    if (!_ready) {
      try {
        await init();
      } catch (e) {
        debugPrint('Notifications unavailable: $e');
        return;
      }
    }
    final id = _id++;
    await _plugin.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'order_updates',
          'Order updates',
          channelDescription:
              'Alerts when an order is placed, approved, shipped, or delivered',
          importance: Importance.high,
          priority: Priority.high,
          styleInformation: BigTextStyleInformation(body),
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: orderNumber,
    );
  }
}
