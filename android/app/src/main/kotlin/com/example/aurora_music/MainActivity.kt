package com.example.aurora_music

import android.content.ContentUris
import android.content.Intent
import android.media.RingtoneManager
import android.net.Uri
import android.provider.MediaStore
import android.provider.Settings
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// AudioServiceActivity (instead of FlutterActivity) so just_audio_background /
// audio_service can run a media-style foreground service for background playback.
// Also hosts a tiny MethodChannel to set a local song as ringtone/alarm
// (uses the existing MediaStore entry — no file copy, no ffmpeg).
class MainActivity : AudioServiceActivity() {
    private val channel = "aurora/ringtone"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canWrite" -> result.success(Settings.System.canWrite(this))
                    "openWriteSettings" -> {
                        startActivity(
                            Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS).apply {
                                data = Uri.parse("package:$packageName")
                            }
                        )
                        result.success(null)
                    }
                    "setRingtone" -> {
                        if (!Settings.System.canWrite(this)) {
                            result.success(false) // caller will prompt for permission
                            return@setMethodCallHandler
                        }
                        try {
                            val id = (call.argument<Any>("mediaId").toString()).toLong()
                            val type = call.argument<Int>("type")
                                ?: RingtoneManager.TYPE_RINGTONE
                            val uri = ContentUris.withAppendedId(
                                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, id
                            )
                            RingtoneManager.setActualDefaultRingtoneUri(
                                this, type, uri
                            )
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("RINGTONE_ERR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
