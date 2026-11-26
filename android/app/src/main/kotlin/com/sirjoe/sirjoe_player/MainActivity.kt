package com.sirjoe.sirjoe_player

import android.bluetooth.BluetoothA2dp
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothClass
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothHeadset
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private val reqEnable = 4711
    private var a2dp: BluetoothA2dp? = null
    private var headset: BluetoothHeadset? = null
    private var pendingEnable: MethodChannel.Result? = null
    private val handler = Handler(Looper.getMainLooper())

    private val adapter: BluetoothAdapter?
        get() = (getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sirjoe/bluetooth")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "isOn" -> {
                            val ad = adapter
                            if (ad == null) result.success(null) else result.success(ad.isEnabled)
                        }
                        "turnOn" -> turnOn(result)
                        "paired" -> result.success(paired())
                        "isConnected" -> result.success(isConnected(call.argument<String>("id") ?: ""))
                        "connect" -> connect(call.argument<String>("id") ?: "", result)
                        "openSettings" -> {
                            startActivity(
                                Intent(Settings.ACTION_BLUETOOTH_SETTINGS)
                                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            )
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: SecurityException) {
                    result.error("PERMISSION", e.message, null)
                } catch (e: Exception) {
                    result.error("ERROR", e.message, null)
                }
            }
    }

    private fun initProxies() {
        val ad = adapter ?: return
        if (!ad.isEnabled) return
        try {
            if (a2dp == null) {
                ad.getProfileProxy(this, object : BluetoothProfile.ServiceListener {
                    override fun onServiceConnected(profile: Int, proxy: BluetoothProfile) {
                        a2dp = proxy as BluetoothA2dp
                    }

                    override fun onServiceDisconnected(profile: Int) {
                        a2dp = null
                    }
                }, BluetoothProfile.A2DP)
            }
            if (headset == null) {
                ad.getProfileProxy(this, object : BluetoothProfile.ServiceListener {
                    override fun onServiceConnected(profile: Int, proxy: BluetoothProfile) {
                        headset = proxy as BluetoothHeadset
                    }

                    override fun onServiceDisconnected(profile: Int) {
                        headset = null
                    }
                }, BluetoothProfile.HEADSET)
            }
        } catch (e: Exception) {
        }
    }

    private fun turnOn(result: MethodChannel.Result) {
        val ad = adapter
        if (ad == null) {
            result.success(false)
            return
        }
        if (ad.isEnabled) {
            result.success(true)
            return
        }
        if (Build.VERSION.SDK_INT < 33) {
            try {
                @Suppress("DEPRECATION")
                if (ad.enable()) {
                    waitEnabled(result, 0)
                    return
                }
            } catch (e: Exception) {
            }
        }
        // Da Android 13 serve la conferma dell'utente.
        pendingEnable = result
        @Suppress("DEPRECATION")
        startActivityForResult(Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE), reqEnable)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == reqEnable) {
            val r = pendingEnable ?: return
            pendingEnable = null
            if (resultCode == RESULT_OK) waitEnabled(r, 0) else r.success(false)
        }
    }

    private fun waitEnabled(result: MethodChannel.Result, tries: Int) {
        val ad = adapter
        if (ad != null && ad.isEnabled) {
            initProxies()
            result.success(true)
            return
        }
        if (tries > 20) {
            result.success(false)
            return
        }
        handler.postDelayed({ waitEnabled(result, tries + 1) }, 500)
    }

    private fun paired(): List<Map<String, Any?>> {
        val ad = adapter ?: return emptyList()
        if (!ad.isEnabled) return emptyList()
        initProxies()
        return ad.bondedDevices.map { d ->
            mapOf(
                "id" to d.address,
                "name" to (d.name ?: d.address),
                "connected" to deviceConnected(d),
                "audio" to (d.bluetoothClass?.majorDeviceClass == BluetoothClass.Device.Major.AUDIO_VIDEO)
            )
        }
    }

    private fun deviceConnected(d: BluetoothDevice): Boolean {
        try {
            if (a2dp?.getConnectionState(d) == BluetoothProfile.STATE_CONNECTED) return true
            if (headset?.getConnectionState(d) == BluetoothProfile.STATE_CONNECTED) return true
        } catch (e: Exception) {
        }
        return try {
            val m = BluetoothDevice::class.java.getMethod("isConnected")
            m.invoke(d) as Boolean
        } catch (e: Exception) {
            false
        }
    }

    private fun isConnected(id: String): Boolean {
        val ad = adapter ?: return false
        if (!ad.isEnabled || id.isEmpty()) return false
        initProxies()
        return deviceConnected(ad.getRemoteDevice(id))
    }

    private fun connect(id: String, result: MethodChannel.Result) {
        val ad = adapter
        if (ad == null || !ad.isEnabled || id.isEmpty()) {
            result.success(false)
            return
        }
        initProxies()
        val dev = ad.getRemoteDevice(id)
        if (deviceConnected(dev)) {
            result.success(true)
            return
        }
        // I profili si collegano in modo asincrono: si aspetta un attimo.
        handler.postDelayed({
            try {
                a2dp?.let { p ->
                    BluetoothA2dp::class.java.getMethod("connect", BluetoothDevice::class.java).invoke(p, dev)
                }
            } catch (e: Exception) {
            }
            try {
                headset?.let { p ->
                    BluetoothHeadset::class.java.getMethod("connect", BluetoothDevice::class.java).invoke(p, dev)
                }
            } catch (e: Exception) {
            }
            waitConnected(dev, result, 0)
        }, 800)
    }

    private fun waitConnected(dev: BluetoothDevice, result: MethodChannel.Result, tries: Int) {
        if (deviceConnected(dev)) {
            try {
                a2dp?.let { p ->
                    BluetoothA2dp::class.java.getMethod("setActiveDevice", BluetoothDevice::class.java).invoke(p, dev)
                }
            } catch (e: Exception) {
            }
            result.success(true)
            return
        }
        if (tries > 20) {
            result.success(false)
            return
        }
        handler.postDelayed({ waitConnected(dev, result, tries + 1) }, 500)
    }
}
