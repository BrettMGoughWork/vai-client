import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../content/content_data.dart';

/// Schedules OS-level reminders based on [ReminderContentData].
///
/// Responsibility sits here (the actions layer) rather than in the content or
/// UX layers: content parsing is the content layer's job; rendering is the UX
/// layer's job; triggering OS side-effects belongs in actions.
abstract interface class ReminderService {
  Future<void> initialize();
  Future<void> scheduleReminder(ReminderContentData data);
}

/// Android implementation backed by [FlutterLocalNotificationsPlugin].
class AndroidReminderService implements ReminderService {
  AndroidReminderService({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  final Completer<void> _ready = Completer<void>();

  static const String _channelId = 'vai_reminders';
  static const String _channelName = 'Reminders';
  static const String _channelDescription = 'Scheduled reminders set by Vai';

  @override
  Future<void> initialize() async {
    try {
      tz.initializeTimeZones();

      const AndroidInitializationSettings androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      await _plugin.initialize(
        settings: const InitializationSettings(android: androidSettings),
      );

      // Request permissions — prompts the user on Android 13+ and for exact
      // alarms on Android 12+.
      final AndroidFlutterLocalNotificationsPlugin? androidPlugin = _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();
      await androidPlugin?.requestExactAlarmsPermission();

      _ready.complete();
      debugPrint('[ReminderService] Initialized successfully');
    } catch (e, st) {
      _ready.completeError(e, st);
      debugPrint('[ReminderService] Initialization failed: $e\n$st');
    }
  }

  @override
  Future<void> scheduleReminder(ReminderContentData data) async {
    try {
      // Wait for initialize() to finish regardless of call ordering.
      await _ready.future;

      final DateTime scheduledAt = _resolveScheduledTime(data.when);
      final int id = DateTime.now().millisecondsSinceEpoch & 0x7FFFFFFF;
      final String title = data.title ?? 'Reminder';

      debugPrint(
        '[ReminderService] Scheduling "$title" for $scheduledAt'
        ' (when="${data.when}")',
      );

      const NotificationDetails details = NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.high,
          priority: Priority.high,
        ),
      );

      try {
        await _plugin.zonedSchedule(
          id: id,
          title: title,
          body: data.text,
          scheduledDate: tz.TZDateTime.from(scheduledAt.toUtc(), tz.UTC),
          notificationDetails: details,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        );
        debugPrint('[ReminderService] Scheduled (exact) id=$id at $scheduledAt');
      } on PlatformException catch (e) {
        // SCHEDULE_EXACT_ALARM not yet granted — fall back to inexact delivery.
        debugPrint(
          '[ReminderService] Exact alarm unavailable ($e)'
          ' — retrying with inexact',
        );
        await _plugin.zonedSchedule(
          id: id,
          title: title,
          body: data.text,
          scheduledDate: tz.TZDateTime.from(scheduledAt.toUtc(), tz.UTC),
          notificationDetails: details,
          androidScheduleMode: AndroidScheduleMode.inexact,
        );
        debugPrint(
          '[ReminderService] Scheduled (inexact) id=$id at $scheduledAt',
        );
      }
    } catch (e, st) {
      debugPrint('[ReminderService] Failed to schedule reminder: $e\n$st');
    }
  }

  /// Tries to parse [when] as ISO 8601. Falls back to 30 s from now so the
  /// notification fires quickly and is visible during development/testing.
  DateTime _resolveScheduledTime(String? when) {
    if (when != null) {
      final DateTime? parsed = DateTime.tryParse(when);
      if (parsed != null && parsed.isAfter(DateTime.now())) {
        return parsed;
      }
      debugPrint(
        '[ReminderService] "when" field ("$when") is missing, unparseable,'
        ' or in the past — scheduling 30 s from now',
      );
    }
    return DateTime.now().add(const Duration(seconds: 30));
  }
}

/// No-op stub for non-Android platforms and unit tests.
class NoopReminderService implements ReminderService {
  const NoopReminderService();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> scheduleReminder(ReminderContentData data) async {}
}
