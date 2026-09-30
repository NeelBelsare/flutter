import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('Firebase already initialized or pending config: $e');
  }
  await NotificationService.instance.showActionableNotification(message);
}

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final String _backendBaseUrl = 'https://your-devops-backend.run.app';

  static const String actionCategoryPR = 'PR_ACTION_CATEGORY';
  static const String actionIdApprove = 'ACTION_APPROVE';
  static const String actionIdDeny = 'ACTION_DENY';

  Future<void> initialize() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings();

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: handleNotificationAction,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    await _setupActionCategories();

    try {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        showActionableNotification(message);
      });
    } catch (e) {
      debugPrint('Firebase messaging listener setup note: $e');
    }
  }

  Future<void> _setupActionCategories() async {
    final AndroidFlutterLocalNotificationsPlugin? androidPlugin =
        _localNotifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    const AndroidNotificationChannel actionChannel = AndroidNotificationChannel(
      'devops_action_channel',
      'DevOps Actions & PR Alerts',
      description: 'Actionable PR merges, denials, and pipeline failures',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );
    await androidPlugin?.createNotificationChannel(actionChannel);
  }

  Future<void> showActionableNotification(RemoteMessage message) async {
    final Map<String, dynamic> data = message.data;
    final String type = data['type'] ?? '';

    List<AndroidNotificationAction> androidActions = [];
    if (type == 'github_pr_action') {
      androidActions = [
        const AndroidNotificationAction(
          actionIdApprove,
          'Approve & Merge',
          showsUserInterface: true,
          cancelNotification: true,
        ),
        const AndroidNotificationAction(
          actionIdDeny,
          'Deny / Close',
          showsUserInterface: false,
          cancelNotification: true,
        ),
      ];
    }

    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'devops_action_channel',
      'DevOps Actions & PR Alerts',
      channelDescription: 'Actionable PR merges, denials, and pipeline failures',
      importance: Importance.max,
      priority: Priority.high,
      actions: androidActions,
    );

    final NotificationDetails notificationDetails =
        NotificationDetails(android: androidDetails);

    await _localNotifications.show(
      id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title: message.notification?.title ?? 'DevOps Alert',
      body: message.notification?.body ?? '',
      notificationDetails: notificationDetails,
      payload: jsonEncode(data),
    );
  }

  Future<void> triggerPrDecision(
      String repo, String prNumber, String decision) async {
    final uri = Uri.parse('$_backendBaseUrl/api/github/pr-action');
    try {
      await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'repo': repo,
          'pr_number': prNumber,
          'decision': decision,
        }),
      );
    } catch (e) {
      debugPrint('Failed to trigger PR decision: $e');
    }
  }
}

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) async {
  if (response.payload == null) return;
  try {
    final Map<String, dynamic> data = jsonDecode(response.payload!);
    final String actionId = response.actionId ?? '';
    final String repo = data['repo'] ?? '';
    final String prNumber = data['pr_number'] ?? '';

    if (actionId == NotificationService.actionIdApprove) {
      await NotificationService.instance
          .triggerPrDecision(repo, prNumber, 'approve_merge');
    } else if (actionId == NotificationService.actionIdDeny) {
      await NotificationService.instance
          .triggerPrDecision(repo, prNumber, 'deny_close');
    }
  } catch (e) {
    debugPrint('Error processing background notification tap: $e');
  }
}

void handleNotificationAction(NotificationResponse response) async {
  notificationTapBackground(response);
}
