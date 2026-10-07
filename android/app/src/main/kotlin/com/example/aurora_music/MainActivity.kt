package com.example.aurora_music

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.provider.Settings
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

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
                    // System Bluetooth settings (scan / pair) — OS owns media routing.
                    "openOutputPicker" -> {
                        result.success(openOutputPicker())
                    }
                    "listAudioOutputs" -> {
                        try {
                            result.success(listAudioOutputs())
                        } catch (e: Exception) {
                            result.error("AUDIO_OUT", e.message, null)
                        }
                    }
                    "setPreferredOutput" -> {
                        val rawId = call.argument<Any>("id")?.toString()
                        if (rawId.isNullOrBlank()) {
                            result.success(false)
                        } else {
                            Thread {
                                val ok = try {
                                    setPreferredOutput(rawId)
                                } catch (_: Exception) {
                                    false
                                }
                                runOnUiThread { result.success(ok) }
                            }.start()
                        }
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

    private fun audioManager(): AudioManager =
        getSystemService(Context.AUDIO_SERVICE) as AudioManager

    private fun bluetoothAdapter(): BluetoothAdapter? {
        return try {
            getSystemService(BluetoothManager::class.java)?.adapter
        } catch (_: Exception) {
            null
        }
    }

    /** System Bluetooth settings — scan / pair. Media routing stays with the OS. */
    private fun openOutputPicker(): Boolean {
        val bt = Intent(Settings.ACTION_BLUETOOTH_SETTINGS)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (tryStartActivity(bt)) return true
        val settings = Intent(Settings.ACTION_SETTINGS)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return tryStartActivity(settings)
    }

    private fun tryStartActivity(intent: Intent): Boolean {
        return try {
            if (packageManager.resolveActivity(intent, 0) == null) return false
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun listAudioOutputs(): List<HashMap<String, Any?>> {
        val devices = audioManager().getDevices(AudioManager.GET_DEVICES_OUTPUTS)
        val out = ArrayList<HashMap<String, Any?>>()
        var hasSpeaker = false
        val seenLabels = HashSet<String>()

        for (d in devices) {
            val kind = outputKind(d) ?: continue
            if (kind == "speaker") {
                if (hasSpeaker) continue
                hasSpeaker = true
            }
            val name = deviceLabel(d, kind)
            // One headset shows up as both A2DP and SCO outputs; list it once.
            if (!seenLabels.add(name.lowercase())) continue
            out.add(
                hashMapOf(
                    "id" to d.id.toString(),
                    "name" to name,
                    "type" to kind,
                    "isActive" to false,
                )
            )
        }
        if (!hasSpeaker) {
            out.add(
                0,
                hashMapOf(
                    "id" to "speaker",
                    "name" to "This phone",
                    "type" to "speaker",
                    "isActive" to false,
                )
            )
        }

        // Bonded Bluetooth not yet present as an AudioDeviceInfo output.
        for (bonded in bondedBluetoothEntries()) {
            val label = bonded.first
            if (seenLabels.contains(label.lowercase())) continue
            seenLabels.add(label.lowercase())
            out.add(
                hashMapOf(
                    "id" to bonded.second,
                    "name" to label,
                    "type" to "bluetooth",
                    "isActive" to false,
                )
            )
        }

        markActiveFromSystem(out)
        return out
    }

    /** Active = what the OS actually exposes as a connected media output. */
    private fun markActiveFromSystem(out: ArrayList<HashMap<String, Any?>>) {
        for (row in out) row["isActive"] = false

        // Prefer a live A2DP/BLE/headphones AudioDeviceInfo (not bonded-only bt:MAC).
        val liveBt = out.firstOrNull {
            it["type"] == "bluetooth" && !it["id"].toString().startsWith("bt:")
        }
        if (liveBt != null) {
            liveBt["isActive"] = true
            return
        }
        val headphones = out.firstOrNull { it["type"] == "headphones" }
        if (headphones != null) {
            headphones["isActive"] = true
            return
        }
        out.firstOrNull { it["type"] == "speaker" }?.let { it["isActive"] = true }
    }

    private fun bondedBluetoothEntries(): List<Pair<String, String>> {
        return try {
            val adapter = bluetoothAdapter() ?: return emptyList()
            if (!adapter.isEnabled) return emptyList()
            val bonded = adapter.bondedDevices ?: return emptyList()
            bonded.mapNotNull { d ->
                val name = try {
                    d.name?.trim().orEmpty()
                } catch (_: SecurityException) {
                    ""
                }
                if (name.isEmpty()) return@mapNotNull null
                name to "bt:${d.address}"
            }
        } catch (_: SecurityException) {
            emptyList()
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun outputKind(d: AudioDeviceInfo): String? = when (d.type) {
        AudioDeviceInfo.TYPE_BUILTIN_SPEAKER,
        AudioDeviceInfo.TYPE_BUILTIN_SPEAKER_SAFE -> "speaker"
        AudioDeviceInfo.TYPE_WIRED_HEADSET,
        AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
        AudioDeviceInfo.TYPE_USB_HEADSET,
        AudioDeviceInfo.TYPE_USB_DEVICE,
        AudioDeviceInfo.TYPE_USB_ACCESSORY -> "headphones"
        AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
        AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
        AudioDeviceInfo.TYPE_BLE_HEADSET,
        AudioDeviceInfo.TYPE_BLE_SPEAKER,
        AudioDeviceInfo.TYPE_HEARING_AID -> "bluetooth"
        else -> null
    }

    private fun deviceLabel(d: AudioDeviceInfo, kind: String): String {
        val product = try {
            d.productName?.toString()?.trim().orEmpty()
        } catch (_: SecurityException) {
            ""
        } catch (_: Exception) {
            ""
        }
        if (product.isNotEmpty() && !product.equals("null", ignoreCase = true)) {
            return product
        }
        return when (kind) {
            "speaker" -> "This phone"
            "headphones" -> "Headphones"
            else -> "Bluetooth"
        }
    }

    /**
     * System-owned routing: connect/disconnect A2DP; OS picks the media path.
     * No MediaRouter2 / setCommunicationDevice for music.
     */
    private fun setPreferredOutput(rawId: String): Boolean {
        return try {
            when {
                rawId == "speaker" || isSpeakerDeviceId(rawId) -> routeToSpeaker()
                rawId.startsWith("bt:") -> {
                    val address = rawId.removePrefix("bt:")
                    val ok = a2dpConnect(address)
                    if (ok) waitForBluetoothOutput(bondedNameForAddress(address))
                    ok
                }
                else -> {
                    val id = rawId.toIntOrNull() ?: return false
                    val device = audioManager().getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                        .firstOrNull { it.id == id }
                        ?: return false
                    when (outputKind(device)) {
                        "speaker" -> routeToSpeaker()
                        "bluetooth" -> {
                            val name = deviceLabel(device, "bluetooth")
                            val address = addressForProductName(name)
                            if (address != null) {
                                val ok = a2dpConnect(address)
                                if (ok) waitForBluetoothOutput(name)
                                ok
                            } else {
                                // Already a live A2DP sink — OS is already routing there.
                                true
                            }
                        }
                        "headphones" -> true // wired: already system-active when listed
                        else -> false
                    }
                }
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun isSpeakerDeviceId(rawId: String): Boolean {
        val id = rawId.toIntOrNull() ?: return false
        val device = audioManager().getDevices(AudioManager.GET_DEVICES_OUTPUTS)
            .firstOrNull { it.id == id } ?: return false
        return outputKind(device) == "speaker"
    }

    private fun routeToSpeaker(): Boolean {
        // Clear any leftover communication routing, then disconnect A2DP so
        // the OS falls back to the built-in speaker for media.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            try {
                audioManager().clearCommunicationDevice()
            } catch (_: Exception) {
            }
        }
        val disconnected = a2dpDisconnectAll()
        if (!disconnected) {
            // Cannot force disconnect on this OEM — open BT settings.
            openOutputPicker()
            return false
        }
        Thread.sleep(500)
        return !hasLiveBluetoothOutput()
    }

    private fun hasLiveBluetoothOutput(): Boolean {
        return audioManager().getDevices(AudioManager.GET_DEVICES_OUTPUTS)
            .any { outputKind(it) == "bluetooth" }
    }

    private fun waitForBluetoothOutput(preferredName: String?): Boolean {
        repeat(8) {
            Thread.sleep(250)
            val devices = audioManager().getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                .filter { outputKind(it) == "bluetooth" }
            if (devices.isEmpty()) return@repeat
            if (preferredName.isNullOrBlank()) return true
            val want = preferredName.lowercase()
            if (devices.any {
                    deviceLabel(it, "bluetooth").lowercase().let { n ->
                        n == want || n.contains(want) || want.contains(n)
                    }
                }
            ) {
                return true
            }
            return true // any BT output appeared after connect
        }
        return hasLiveBluetoothOutput()
    }

    private fun bondedNameForAddress(address: String): String? {
        return try {
            bluetoothAdapter()?.bondedDevices?.firstOrNull {
                it.address.equals(address, ignoreCase = true)
            }?.name?.trim()?.takeIf { it.isNotEmpty() }
        } catch (_: Exception) {
            null
        }
    }

    private fun addressForProductName(name: String): String? {
        val want = name.lowercase()
        return try {
            bluetoothAdapter()?.bondedDevices?.firstOrNull { d ->
                val n = try {
                    d.name?.trim()?.lowercase().orEmpty()
                } catch (_: Exception) {
                    ""
                }
                // An unnamed bond would otherwise match everything ("".contains).
                n.isNotEmpty() && (n == want || n.contains(want) || want.contains(n))
            }?.address
        } catch (_: Exception) {
            null
        }
    }

    private fun a2dpConnect(address: String): Boolean {
        return withA2dpProxy { proxy, adapter ->
            val device = try {
                adapter.bondedDevices?.firstOrNull {
                    it.address.equals(address, ignoreCase = true)
                }
            } catch (_: Exception) {
                null
            } ?: return@withA2dpProxy false
            tryInvokeProfileMethod(proxy, "connect", device)
        }
    }

    private fun a2dpDisconnectAll(): Boolean {
        return withA2dpProxy { proxy, _ ->
            val connected = try {
                @Suppress("UNCHECKED_CAST")
                val m = proxy.javaClass.getMethod("getConnectedDevices")
                (m.invoke(proxy) as? List<BluetoothDevice>).orEmpty()
            } catch (_: Exception) {
                emptyList()
            }
            if (connected.isEmpty()) {
                // Also try disconnecting all bonded that look connected via AudioManager.
                val names = audioManager().getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                    .filter { outputKind(it) == "bluetooth" }
                    .map { deviceLabel(it, "bluetooth") }
                var any = false
                for (n in names) {
                    val addr = addressForProductName(n) ?: continue
                    val device = try {
                        bluetoothAdapter()?.getRemoteDevice(addr)
                    } catch (_: Exception) {
                        null
                    } ?: continue
                    if (tryInvokeProfileMethod(proxy, "disconnect", device)) any = true
                }
                return@withA2dpProxy any || names.isEmpty()
            }
            var any = false
            for (d in connected) {
                if (tryInvokeProfileMethod(proxy, "disconnect", d)) any = true
            }
            any
        }
    }

    private fun withA2dpProxy(block: (BluetoothProfile, BluetoothAdapter) -> Boolean): Boolean {
        val adapter = bluetoothAdapter() ?: return false
        val latch = CountDownLatch(1)
        val outcome = AtomicBoolean(false)
        val proxyRef = AtomicReference<BluetoothProfile?>(null)
        val listener = object : BluetoothProfile.ServiceListener {
            override fun onServiceConnected(profile: Int, proxy: BluetoothProfile) {
                if (profile != BluetoothProfile.A2DP) {
                    latch.countDown()
                    return
                }
                proxyRef.set(proxy)
                try {
                    outcome.set(block(proxy, adapter))
                } catch (_: Exception) {
                    outcome.set(false)
                } finally {
                    latch.countDown()
                }
            }

            override fun onServiceDisconnected(profile: Int) {}
        }
        return try {
            if (!adapter.getProfileProxy(this, listener, BluetoothProfile.A2DP)) {
                return false
            }
            latch.await(3, TimeUnit.SECONDS)
            proxyRef.get()?.let { p ->
                try {
                    adapter.closeProfileProxy(BluetoothProfile.A2DP, p)
                } catch (_: Exception) {
                }
            }
            outcome.get()
        } catch (_: Exception) {
            false
        }
    }

    private fun tryInvokeProfileMethod(
        proxy: BluetoothProfile,
        method: String,
        device: BluetoothDevice,
    ): Boolean {
        return try {
            val m = proxy.javaClass.getMethod(method, BluetoothDevice::class.java)
            val r = m.invoke(proxy, device)
            r == true || r == null
        } catch (_: Exception) {
            false
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
