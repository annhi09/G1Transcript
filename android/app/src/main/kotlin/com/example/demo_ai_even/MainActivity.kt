//// android/app/src/main/kotlin/com/example/demo_ai_even/MainActivity.kt
//package com.example.demo_ai_even
//
//import android.content.Intent
//import android.os.Build
//import android.os.Bundle
//import android.util.Log
//import android.media.AudioDeviceInfo
//import android.media.AudioManager
//import androidx.annotation.RequiresApi
//import com.example.demo_ai_even.bluetooth.BleChannelHelper
//import com.example.demo_ai_even.bluetooth.BleManager
//import com.example.demo_ai_even.cpp.Cpp
//import io.flutter.embedding.android.FlutterActivity
//import io.flutter.embedding.engine.FlutterEngine
//import io.flutter.plugin.common.EventChannel
//import io.flutter.plugin.common.MethodChannel
//
//class MainActivity : FlutterActivity(), EventChannel.StreamHandler {
//
//    private val captionServiceChannelName = "caption_service"
//    private val audioRouteChannelName = "audio_route"
//
//    override fun onCreate(savedInstanceState: Bundle?) {
//        super.onCreate(savedInstanceState)
//        Cpp.init()
//        BleManager.instance.initBluetooth(this)
//    }
//
//    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
//        super.configureFlutterEngine(flutterEngine)
//
//        // Existing BLE/Event channel
//        BleChannelHelper.initChannel(this, flutterEngine)
//
//        // Foreground service control (you already added this earlier)
//        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, captionServiceChannelName)
//            .setMethodCallHandler { call, result ->
//                try {
//                    when (call.method) {
//                        "startService" -> {
//                            val intent = Intent(this, CaptionMicService::class.java)
//                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(intent)
//                            else @Suppress("DEPRECATION") startService(intent)
//                            result.success(null)
//                        }
//                        "stopService" -> {
//                            val intent = Intent(this, CaptionMicService::class.java)
//                            stopService(intent)
//                            result.success(null)
//                        }
//                        else -> result.notImplemented()
//                    }
//                } catch (e: Exception) {
//                    Log.e("MainActivity", "FGS method error", e)
//                    result.error("FGS_ERROR", e.message, null)
//                }
//            }
//
//        // NEW: Audio routing for SpeechRecognizer (best-effort)
//        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, audioRouteChannelName)
//            .setMethodCallHandler { call, result ->
//                val am = getSystemService(AUDIO_SERVICE) as AudioManager
//                try {
//                    when (call.method) {
//                        "routeToBluetooth" -> {
//                            val ok = routeToBluetooth(am)
//                            result.success(ok)
//                        }
//                        "routeToWiredOrUsb" -> {
//                            val ok = routeToWiredOrUsb(am)
//                            result.success(ok)
//                        }
//                        "routeToPhoneMic" -> {
//                            val ok = clearCommunicationDevice(am)
//                            result.success(ok)
//                        }
//                        "useVoiceCommMode" -> { // enable/disable MODE_IN_COMMUNICATION
//                            val enable = call.argument<Boolean>("enable") ?: true
//                            am.mode = if (enable) AudioManager.MODE_IN_COMMUNICATION else AudioManager.MODE_NORMAL
//                            result.success(true)
//                        }
//                        else -> result.notImplemented()
//                    }
//                } catch (e: Exception) {
//                    Log.e("MainActivity", "audio_route error", e)
//                    result.error("AUDIO_ROUTE", e.message, null)
//                }
//            }
//    }
//
//    // ---- Routing helpers ----
//
//    private fun routeToBluetooth(am: AudioManager): Boolean {
//        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
//            // API 31+: pick a communication device (BLE headset or SCO headset)
//            val devs = am.availableCommunicationDevices
//            val target = devs.firstOrNull {
//                it.type == AudioDeviceInfo.TYPE_BLE_HEADSET ||
//                        it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO
//            } ?: return false
//            am.setCommunicationDevice(target)  // returns Boolean in API 31+
//        } else {
//            // Legacy: SCO route for BT HFP
//            @Suppress("DEPRECATION")
//            am.isBluetoothScoOn = true
//            @Suppress("DEPRECATION")
//            am.startBluetoothSco()
//            true
//        }
//    }
//
//    private fun routeToWiredOrUsb(am: AudioManager): Boolean {
//        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
//            val devs = am.availableCommunicationDevices
//            val target = devs.firstOrNull {
//                it.type == AudioDeviceInfo.TYPE_WIRED_HEADSET ||
//                        it.type == AudioDeviceInfo.TYPE_USB_HEADSET ||
//                        it.type == AudioDeviceInfo.TYPE_USB_DEVICE
//            } ?: return false
//            am.setCommunicationDevice(target)  // returns Boolean
//        } else {
//            // Pre-31 cannot explicitly select; rely on insertion priority + comm mode
//            true
//        }
//    }
//
//    private fun clearCommunicationDevice(am: AudioManager): Boolean =
//        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
//            am.clearCommunicationDevice()
//        } else {
//            @Suppress("DEPRECATION")
//            am.stopBluetoothSco()
//            @Suppress("DEPRECATION")
//            am.isBluetoothScoOn = false
//            true
//        }
//
//
//
////    private fun clearCommunicationDevice(am: AudioManager): Boolean {
////        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
////            am.clearCommunicationDevice()  // returns Boolean
////        } else {
////            @Suppress("DEPRECATION")
////            am.stopBluetoothSco()
////            @Suppress("DEPRECATION")
////            am.isBluetoothScoOn = false
////            true
////        }
////    }
//
////    private fun routeToBluetooth(am: AudioManager): Boolean {
////        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
////            // API 31+: pick a communication device (BLE headset or SCO headset)
////            val devs = am.availableCommunicationDevices
////            val target = devs.firstOrNull {
////                it.type == AudioDeviceInfo.TYPE_BLE_HEADSET || it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO
////            } ?: return false
////            am.setCommunicationDevice(target)
////        } else {
////            // Legacy: SCO route for BT HFP
////            @Suppress("DEPRECATION")
////            am.isBluetoothScoOn = true
////            @Suppress("DEPRECATION")
////            am.startBluetoothSco()
////            true
////        }
////    }
////
////    private fun routeToWiredOrUsb(am: AudioManager): Boolean {
////        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
////            val devs = am.availableCommunicationDevices
////            val target = devs.firstOrNull {
////                it.type == AudioDeviceInfo.TYPE_WIRED_HEADSET ||
////                        it.type == AudioDeviceInfo.TYPE_USB_HEADSET ||
////                        it.type == AudioDeviceInfo.TYPE_USB_DEVICE
////            } ?: return false
////            am.setCommunicationDevice(target)
////        } else {
////            // Pre-31 cannot explicitly select; rely on insertion priority + comm mode
////            true
////        }
////    }
////
////    private fun clearCommunicationDevice(am: AudioManager): Boolean {
////        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
////            am.clearCommunicationDevice()
////        } else {
////            @Suppress("DEPRECATION")
////            am.stopBluetoothSco()
////            @Suppress("DEPRECATION")
////            am.isBluetoothScoOn = false
////            true
////        }
////    }
//
//    // ----- EventChannel.StreamHandler (existing) -----
//    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
//        Log.i(this::class.simpleName, "EventChannel.StreamHandler - OnListen: arguments = $arguments ,events = $events")
//        BleChannelHelper.addEventSink(arguments as String?, events)
//    }
//
//    override fun onCancel(arguments: Any?) {
//        Log.i(this::class.simpleName, "EventChannel.StreamHandler - OnCancel: arguments = $arguments")
//        BleChannelHelper.removeEventSink(arguments as String?)
//    }
//}


// android/app/src/main/kotlin/com/example/demo_ai_even/MainActivity.kt
package com.example.demo_ai_even

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.util.Log
import com.example.demo_ai_even.bluetooth.BleChannelHelper
import com.example.demo_ai_even.bluetooth.BleManager
import com.example.demo_ai_even.cpp.Cpp
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity(), EventChannel.StreamHandler {

    private val captionServiceChannelName = "caption_service"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Cpp.init()
        BleManager.instance.initBluetooth(this)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Existing BLE channels
        BleChannelHelper.initChannel(this, flutterEngine)

        // New MethodChannel to control the foreground service from Flutter
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            captionServiceChannelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startService" -> {
                    try {
                        val intent = Intent(this, CaptionMicService::class.java)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            @Suppress("DEPRECATION")
                            startService(intent)
                        }
                        result.success(null)
                    } catch (e: Exception) {
                        Log.e("MainActivity", "startService error", e)
                        result.error("START_SERVICE_ERROR", e.message, null)
                    }
                }

                "stopService" -> {
                    try {
                        val intent = Intent(this, CaptionMicService::class.java)
                        stopService(intent)
                        result.success(null)
                    } catch (e: Exception) {
                        Log.e("MainActivity", "stopService error", e)
                        result.error("STOP_SERVICE_ERROR", e.message, null)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    // ----- EventChannel.StreamHandler (your existing BLE event wiring) -----
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        Log.i(
            this::class.simpleName,
            "EventChannel.StreamHandler - OnListen: arguments = $arguments ,events = $events"
        )
        BleChannelHelper.addEventSink(arguments as String?, events)
    }

    override fun onCancel(arguments: Any?) {
        Log.i(
            this::class.simpleName,
            "EventChannel.StreamHandler - OnCancel: arguments = $arguments"
        )
        BleChannelHelper.removeEventSink(arguments as String?)
    }
}



//package com.example.demo_ai_even
//
//
//import android.content.Intent
//import android.os.Bundle
//import android.util.Log
//import com.example.demo_ai_even.bluetooth.BleChannelHelper
//import com.example.demo_ai_even.bluetooth.BleManager
//import com.example.demo_ai_even.cpp.Cpp
//import io.flutter.embedding.android.FlutterActivity
//import io.flutter.embedding.engine.FlutterEngine
//import io.flutter.plugin.common.EventChannel
//import io.flutter.plugin.common.MethodChannel
//
//class MainActivity: FlutterActivity(), EventChannel.StreamHandler {
//
//
//    override fun onCreate(savedInstanceState: Bundle?) {
//        super.onCreate(savedInstanceState)
//        Cpp.init()
//        BleManager.instance.initBluetooth(this)
//    }
//
//    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
//        super.configureFlutterEngine(flutterEngine)
//        BleChannelHelper.initChannel(this, flutterEngine)
//
//    }
//
//    /// Interface - EventChannel.StreamHandler
//    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
//        Log.i(this::class.simpleName,"EventChannel.StreamHandler - OnListen: arguments = $arguments ,events = $events")
//        BleChannelHelper.addEventSink(arguments as String?, events)
//    }
//
//    /// Interface - EventChannel.StreamHandler
//    override fun onCancel(arguments: Any?) {
//        Log.i(this::class.simpleName,"EventChannel.StreamHandler - OnCancel: arguments = $arguments")
//        BleChannelHelper.removeEventSink(arguments as String?)
//    }
//
//}
