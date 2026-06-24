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

  /// Set by DownloadController — fired by download notification actions.
  void Function(String trackId)? onDownloadCancel;
  void Function(String trackId)? onDownloadPause;
  void Function(String trackId)? onDownloadResume;

  static const _engagementChannel = AndroidNotificationChannel(
    'com.aurora.music.channel.engagement',
    'Aurora updates',
    description: 'Daily mixes, reminders and listening moments',
    importance: Importance.defaultImportance,
  );

  static const _downloadChannel = AndroidNotificationChannel(
    'com.aurora.music.channel.downloads',
    'Downloads',
    description: 'Download progress',
    importance: Importance.low,
  );

  Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(settings,
        onDidReceiveNotificationResponse: _onResponse);

    final android13 = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await android13?.createNotificationChannel(_engagementChannel);
    await android13?.createNotificationChannel(_downloadChannel);
    await android13?.requestNotificationsPermission();
    _ready = true;
  }

  void _onResponse(NotificationResponse r) {
    final a = r.actionId;
    if (a == null) return;
    if (a.startsWith('cancel_')) onDownloadCancel?.call(a.substring(7));
    if (a.startsWith('pause_')) onDownloadPause?.call(a.substring(6));
    if (a.startsWith('resume_')) onDownloadResume?.call(a.substring(7));
  }

  // --- Download notifications -------------------------------------------
  int _dlId(String trackId) => 50000 + (trackId.hashCode & 0xffff);

  Future<void> showDownloadProgress(
      String trackId, String title, int percent) async {
    if (!_ready) return;
    final details = AndroidNotificationDetails(
      _downloadChannel.id,
      _downloadChannel.name,
      channelDescription: _downloadChannel.description,
      importance: Importance.low,
      priority: Priority.low,
      onlyAlertOnce: true,
      ongoing: true,
      autoCancel: false,
      showProgress: true,
      maxProgress: 100,
      progress: percent.clamp(0, 100),
      indeterminate: percent <= 0,
      actions: [
        AndroidNotificationAction('pause_$trackId', 'Pause',
            cancelNotification: false),
        AndroidNotificationAction('cancel_$trackId', 'Cancel',
            cancelNotification: false),
      ],
    );
    await _plugin.show(_dlId(trackId), 'Downloading · $percent%', title,
        NotificationDetails(android: details));
  }

  Future<void> showDownloadPaused(
      String trackId, String title, int percent) async {
    if (!_ready) return;
    final details = AndroidNotificationDetails(
      _downloadChannel.id,
      _downloadChannel.name,
      channelDescription: _downloadChannel.description,
      importance: Importance.low,
      priority: Priority.low,
      onlyAlertOnce: true,
      ongoing: true,
      autoCancel: false,
      showProgress: true,
      maxProgress: 100,
      progress: percent.clamp(0, 100),
      actions: [
        AndroidNotificationAction('resume_$trackId', 'Resume',
            cancelNotification: false),
        AndroidNotificationAction('cancel_$trackId', 'Cancel',
            cancelNotification: false),
      ],
    );
    await _plugin.show(_dlId(trackId), 'Paused · $percent%', title,
        NotificationDetails(android: details));
  }

  Future<void> showDownloadDone(String trackId, String title) async {
    if (!_ready) return;
    await _plugin.cancel(_dlId(trackId));
    await _plugin.show(
      _dlId(trackId),
      '✓ Downloaded',
      title,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'com.aurora.music.channel.downloads', 'Downloads',
          importance: Importance.low, priority: Priority.low),
      ),
    );
  }

  Future<void> showDownloadError(String trackId, String title) async {
    if (!_ready) return;
    await _plugin.cancel(_dlId(trackId));
    await _plugin.show(
      _dlId(trackId),
      '⚠ Download failed',
      title,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'com.aurora.music.channel.downloads', 'Downloads',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority),
      ),
    );
  }

  Future<void> cancelDownloadNotif(String trackId) async {
    if (_ready) await _plugin.cancel(_dlId(trackId));
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
