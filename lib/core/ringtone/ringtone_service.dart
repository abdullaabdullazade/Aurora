import 'package:flutter/services.dart';

enum RingtoneType { ringtone, alarm, notification }

/// Sets a local song as the system ringtone/alarm/notification — no trimming,
/// no ffmpeg. Reuses the track's existing MediaStore entry via a thin Kotlin
/// MethodChannel (RingtoneManager.setActualDefaultRingtoneUri).
class RingtoneService {
  RingtoneService._();
  static final RingtoneService instance = RingtoneService._();

  static const _ch = MethodChannel('aurora/ringtone');

  // RingtoneManager TYPE_* constants.
  int _code(RingtoneType t) => switch (t) {
        RingtoneType.ringtone => 1, // TYPE_RINGTONE
        RingtoneType.notification => 2, // TYPE_NOTIFICATION
        RingtoneType.alarm => 4, // TYPE_ALARM
      };

  Future<bool> canWrite() async =>
      (await _ch.invokeMethod<bool>('canWrite')) ?? false;

  Future<void> openWriteSettings() => _ch.invokeMethod('openWriteSettings');

  /// [mediaId] is the MediaStore id (Track.id for on-device tracks).
  /// Returns false if WRITE_SETTINGS permission is missing (caller should
  /// prompt + open settings, then retry).
  Future<bool> set(String mediaId, RingtoneType type) async {
    final ok = await _ch.invokeMethod<bool>('setRingtone', {
      'mediaId': mediaId,
      'type': _code(type),
    });
    return ok ?? false;
  }
}
