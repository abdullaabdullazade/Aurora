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
    private val mediaChannel = "aurora/media"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Native MediaStore scan — replaces on_audio_query.querySongs, which
        // crashes ("Reply already submitted"). Runs off the UI thread.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, mediaChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "querySongs" -> Thread {
                        try {
                            val songs = queryAudio()
                            runOnUiThread { result.success(songs) }
                        } catch (e: Exception) {
                            runOnUiThread {
                                result.error("QUERY_ERR", e.message, null)
                            }
                        }
                    }.start()
                    // System output picker — lets the user route to phone
                    // speaker / Bluetooth / headphones even while BT is on.
                    "openOutputPicker" -> {
                        val intents = listOf(
                            Intent("android.settings.panel.action.MEDIA_OUTPUT")
                                .putExtra(
                                    "com.android.settings.panel.extra.PACKAGE_NAME",
                                    packageName),
                            Intent("com.android.settings.action.MEDIA_OUTPUT"),
                            Intent(Settings.ACTION_SOUND_SETTINGS),
                            Intent(Settings.ACTION_BLUETOOTH_SETTINGS),
                            Intent(Settings.ACTION_SETTINGS),
                        )
                        var opened = false
                        for (i in intents) {
                            try {
                                i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                startActivity(i)
                                opened = true
                                break
                            } catch (_: Exception) { /* try next */ }
                        }
                        result.success(opened)
                    }
                    else -> result.notImplemented()
                }
            }

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

    private fun queryAudio(): List<HashMap<String, Any?>> {
        val out = ArrayList<HashMap<String, Any?>>()
        val proj = arrayOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.DURATION,
            MediaStore.Audio.Media.DATA,
        )
        val sel = "${MediaStore.Audio.Media.IS_MUSIC} != 0"
        contentResolver.query(
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
            proj, sel, null,
            "${MediaStore.Audio.Media.DATE_ADDED} DESC",
        )?.use { c ->
            val idI = c.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
            val titleI = c.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
            val artistI = c.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
            val durI = c.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
            val dataI = c.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA)
            while (c.moveToNext()) {
                val dur = c.getLong(durI)
                if (dur <= 0) continue
                out.add(hashMapOf(
                    "id" to c.getLong(idI).toString(),
                    "title" to (c.getString(titleI) ?: "Unknown"),
                    "artist" to (c.getString(artistI) ?: "Unknown artist"),
                    "duration" to dur,
                    "data" to (c.getString(dataI) ?: ""),
                ))
            }
        }
        return out
    }
}
