import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Creative engagement notifications: a daily "your mix is ready" nudge plus
/// ad-hoc moments (sleep-timer ended, milestones). Separate from the media
/// playback notification (that one is handled by just_audio_background).
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _engagementChannel = AndroidNotificationChannel(
    'com.aurora.music.channel.engagement',
    'Aurora updates',
    description: 'Daily mixes, reminders and listening moments',
    importance: Importance.defaultImportance,
  );

  Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(settings);

    final android13 = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await android13?.createNotificationChannel(_engagementChannel);
    await android13?.requestNotificationsPermission();
    _ready = true;
  }

  NotificationDetails get _details => const NotificationDetails(
        android: AndroidNotificationDetails(
          'com.aurora.music.channel.engagement',
          'Aurora updates',
          channelDescription: 'Daily mixes, reminders and listening moments',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          styleInformation: BigTextStyleInformation(''),
        ),
      );

  Future<void> showNow(int id, String title, String body) async {
    if (!_ready) return;
    await _plugin.show(id, title, body, _details);
  }

  /// Daily notification at [hour]:[minute] local time.
  Future<void> _scheduleDaily(
      int id, int hour, int minute, String title, String body) async {
    if (!_ready) return;
    final now = tz.TZDateTime.now(tz.local);
    var when =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (when.isBefore(now)) when = when.add(const Duration(days: 1));
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      when,
      _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time, // repeat daily
    );
  }

  /// Two playful daily nudges.
  Future<void> scheduleDailyNudges() async {
    await _scheduleDaily(1001, 12, 30, '🎧 Your daily mix is ready',
        'Fresh tracks picked for your afternoon. Tap to dive in.');
    await _scheduleDaily(1002, 20, 0, '🌙 Wind-down time',
        'Set a sleep timer and drift off to something soft tonight.');
  }
}
