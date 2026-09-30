import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

// Top-level or global plugin instance
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

const String notificationChannelId = 'task_reminder_exact_channel';
const String notificationChannelName = 'Task Reminders';
const String notificationChannelDesc =
    'High priority channel for precise task reminders';

/// Background/terminated notification action handler
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse notificationResponse) {
  // Handle notification tap when the app is in background or terminated
  debugPrint('Notification tapped in background: ${notificationResponse.payload}');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize timezone database and detect local timezone
  await _configureLocalTimeZone();

  // Initialize flutter_local_notifications
  await _initializeNotifications();

  runApp(const TaskReminderApp());
}

/// Initializes timezone database and maps device local offset to timezone location
Future<void> _configureLocalTimeZone() async {
  tz.initializeTimeZones();

  // Attempt to match local time zone by name or current time offset
  final String timeZoneName = DateTime.now().timeZoneName;
  if (tz.timeZoneDatabase.locations.containsKey(timeZoneName)) {
    tz.setLocalLocation(tz.getLocation(timeZoneName));
    return;
  }

  // Fallback: match by current UTC offset duration
  final Duration localOffset = DateTime.now().timeZoneOffset;
  for (final location in tz.timeZoneDatabase.locations.values) {
    if (location.currentTimeZone.offset == localOffset) {
      tz.setLocalLocation(location);
      return;
    }
  }

  // Ultimate fallback to UTC if no matching offset found
  tz.setLocalLocation(tz.UTC);
}

/// Initializes local notification settings and registers Android notification channel
Future<void> _initializeNotifications() async {
  const AndroidInitializationSettings androidInitializationSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const DarwinInitializationSettings darwinInitializationSettings =
      DarwinInitializationSettings(
    requestAlertPermission: false,
    requestBadgePermission: false,
    requestSoundPermission: false,
  );

  const InitializationSettings initializationSettings = InitializationSettings(
    android: androidInitializationSettings,
    iOS: darwinInitializationSettings,
  );

  await flutterLocalNotificationsPlugin.initialize(
    settings: initializationSettings,
    onDidReceiveNotificationResponse: (NotificationResponse response) {
      debugPrint('Notification received foreground/action: ${response.payload}');
    },
    onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
  );

  // Create High-Importance Android Notification Channel for Heads-up popups, sound & vibration
  final AndroidNotificationChannel androidNotificationChannel =
      AndroidNotificationChannel(
    notificationChannelId,
    notificationChannelName,
    description: notificationChannelDesc,
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
    showBadge: true,
    vibrationPattern: Int64List.fromList([0, 1000, 500, 1000]),
  );

  final AndroidFlutterLocalNotificationsPlugin? androidPlugin =
      flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  await androidPlugin?.createNotificationChannel(androidNotificationChannel);
}

class TaskReminderApp extends StatelessWidget {
  const TaskReminderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Task Reminder',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const ReminderHomeScreen(),
    );
  }
}

class ReminderHomeScreen extends StatefulWidget {
  const ReminderHomeScreen({super.key});

  @override
  State<ReminderHomeScreen> createState() => _ReminderHomeScreenState();
}

class _ReminderHomeScreenState extends State<ReminderHomeScreen> {
  final TextEditingController _taskController = TextEditingController();
  TimeOfDay? _selectedTime;
  bool _isScheduling = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    // Default to current time + 1 minute for quick testing convenience
    final now = DateTime.now().add(const Duration(minutes: 1));
    _selectedTime = TimeOfDay(hour: now.hour, minute: now.minute);

    // Request permissions on screen load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestPermissions();
    });
  }

  @override
  void dispose() {
    _taskController.dispose();
    super.dispose();
  }

  /// Request runtime permissions for Android 13+ (POST_NOTIFICATIONS) and Exact Alarms
  Future<bool> _requestPermissions() async {
    // 1. Request POST_NOTIFICATIONS for Android 13+ (API 33+)
    PermissionStatus notificationStatus = await Permission.notification.status;
    if (!notificationStatus.isGranted) {
      notificationStatus = await Permission.notification.request();
    }

    // 2. Request Exact Alarm permission (Android 12+ / 13+)
    PermissionStatus exactAlarmStatus = await Permission.scheduleExactAlarm.status;
    if (!exactAlarmStatus.isGranted) {
      exactAlarmStatus = await Permission.scheduleExactAlarm.request();
    }

    // Also notify flutter_local_notifications plugin on Android
    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    await androidImplementation?.requestNotificationsPermission();
    await androidImplementation?.requestExactAlarmsPermission();

    final bool isNotificationAllowed = notificationStatus.isGranted;
    final bool isExactAlarmAllowed =
        exactAlarmStatus.isGranted || exactAlarmStatus.isLimited;

    if (!isNotificationAllowed || !isExactAlarmAllowed) {
      if (mounted) {
        setState(() {
          _statusMessage =
              'Warning: Notification or Exact Alarm permissions are not granted. '
              'Reminders may not trigger on time.';
        });
      }
      return false;
    }

    return true;
  }

  /// Opens the Flutter Material Time Picker
  Future<void> _pickTime() async {
    final TimeOfDay initialTime = _selectedTime ?? TimeOfDay.now();
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      helpText: 'SELECT REMINDER TIME',
      confirmText: 'CONFIRM',
      cancelText: 'CANCEL',
    );

    if (picked != null) {
      setState(() {
        _selectedTime = picked;
        _statusMessage = null;
      });
    }
  }

  /// Schedules an exact local notification with high priority, popup alert, vibration and sound
  Future<void> _scheduleNotification() async {
    final String taskText = _taskController.text.trim();

    if (taskText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a task description.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (_selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a reminder time.'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }

    // Capture time format before async calls
    final String formattedPickedTime = _selectedTime!.format(context);

    setState(() {
      _isScheduling = true;
    });

    // Ensure permissions are acquired before scheduling
    final bool permissionsGranted = await _requestPermissions();
    if (!permissionsGranted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Permissions required: Please grant Notification and Exact Alarm permissions.',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
    }

    // Calculate scheduled TZDateTime
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      _selectedTime!.hour,
      _selectedTime!.minute,
    );

    // If the picked time today has already passed, schedule it for tomorrow
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    // High-priority Android notification details for heads-up popup, vibration & sound
    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      notificationChannelId,
      notificationChannelName,
      channelDescription: notificationChannelDesc,
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'Task Reminder',
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 1000, 500, 1000]),
      fullScreenIntent: true,
      visibility: NotificationVisibility.public,
      category: AndroidNotificationCategory.reminder,
      audioAttributesUsage: AudioAttributesUsage.notification,
    );

    const DarwinNotificationDetails darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
    );

    final NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
    );

    // Unique notification ID based on timestamp
    final int notificationId = DateTime.now().millisecondsSinceEpoch.remainder(100000);

    try {
      await flutterLocalNotificationsPlugin.zonedSchedule(
        id: notificationId,
        title: '⏰ Task Reminder',
        body: taskText,
        scheduledDate: scheduledDate,
        notificationDetails: notificationDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: 'task_payload_$notificationId',
      );

      final String formattedTime =
          '$formattedPickedTime (${scheduledDate.day}/${scheduledDate.month}/${scheduledDate.year})';

      if (mounted) {
        setState(() {
          _isScheduling = false;
          _statusMessage = 'Reminder scheduled for $formattedTime';
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Reminder set for $formattedTime'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isScheduling = false;
          _statusMessage = 'Failed to schedule: $e';
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to schedule reminder: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Task Reminder',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 2,
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Card
              Card(
                elevation: 0,
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: theme.colorScheme.primary.withValues(alpha: 0.2),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Icon(
                        Icons.alarm_on_rounded,
                        size: 38,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Exact Background Alarms',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Triggers with sound, vibration, and popup even when terminated or locked.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 28),

              // 1. Task Description TextField
              Text(
                'Task Description',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _taskController,
                maxLines: 3,
                minLines: 1,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  hintText: 'e.g., Take medication, Attend client meeting...',
                  prefixIcon: const Icon(Icons.edit_note_rounded),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerLowest,
                ),
              ),

              const SizedBox(height: 24),

              // 2. Time Picker Field
              Text(
                'Reminder Time',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: _pickTime,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 16.0,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.colorScheme.outline),
                    borderRadius: BorderRadius.circular(12),
                    color: theme.colorScheme.surfaceContainerLowest,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.access_time_filled_rounded,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _selectedTime != null
                              ? _selectedTime!.format(context)
                              : 'Select time',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      OutlinedButton(
                        onPressed: _pickTime,
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('Change Time'),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // 3. Set Reminder Button
              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  onPressed: _isScheduling ? null : _scheduleNotification,
                  icon: _isScheduling
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.notification_add_rounded),
                  label: Text(
                    _isScheduling ? 'Scheduling...' : 'Set Reminder',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Status / Confirmation Display
              if (_statusMessage != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _statusMessage!.startsWith('Reminder scheduled')
                        ? Colors.green.withValues(alpha: 0.1)
                        : Colors.amber.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _statusMessage!.startsWith('Reminder scheduled')
                          ? Colors.green.withValues(alpha: 0.5)
                          : Colors.amber.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _statusMessage!.startsWith('Reminder scheduled')
                            ? Icons.check_circle_rounded
                            : Icons.info_outline_rounded,
                        color: _statusMessage!.startsWith('Reminder scheduled')
                            ? Colors.green
                            : Colors.orange,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _statusMessage!,
                          style: TextStyle(
                            fontSize: 13,
                            color: _statusMessage!.startsWith('Reminder scheduled')
                                ? Colors.green.shade800
                                : Colors.amber.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
