package com.example.social_chat_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import androidx.core.app.NotificationCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.social_chat_app/call"
    private val TAG = "[MainActivity]"
    
    // Cache for pending actions if Flutter isn't ready yet
    private var pendingCallAction: Map<String, String>? = null
    private var isFlutterReady = false // Track if Dart side has registered handlers

    companion object {
        @JvmStatic
        var methodChannel: MethodChannel? = null

        @JvmStatic
        fun invokeAcceptCall(callerId: String, channelName: String, isVideo: Boolean) {
            println("[MainActivity] 📞 invokeAcceptCall: callerId=$callerId, channel=$channelName, isVideo=$isVideo")
            methodChannel?.invokeMethod("acceptCall", mapOf(
                "callerId" to callerId,
                "channelName" to channelName,
                "isVideo" to isVideo
            )) ?: println("[MainActivity] ⚠️ methodChannel is null, cannot invoke acceptCall")
        }

        @JvmStatic
        fun invokeDeclineCall(callerId: String, channelName: String) {
            println("[MainActivity] 📵 invokeDeclineCall: callerId=$callerId, channel=$channelName")
            methodChannel?.invokeMethod("declineCall", mapOf(
                "callerId" to callerId,
                "channelName" to channelName
            )) ?: println("[MainActivity] ⚠️ methodChannel is null, cannot invoke declineCall")
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        updateLockScreenBehavior(intent)
        
        println("$TAG onCreate called")
        handleIntent(intent)
    }

    override fun onResume() {
        super.onResume()
        println("$TAG ✅ onResume called - App is now in foreground")
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        println("$TAG 📞 onNewIntent called - App brought to foreground")
        setIntent(intent)
        updateLockScreenBehavior(intent)
        handleIntent(intent)
    }

    private fun updateLockScreenBehavior(intent: Intent?) {
        val isCallIntent = intent?.getBooleanExtra("callIncoming", false) == true ||
            intent?.getBooleanExtra("acceptCall", false) == true ||
            intent?.getBooleanExtra("declineCall", false) == true

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(isCallIntent)
            setTurnScreenOn(isCallIntent)
        }

        if (isCallIntent) {
            window.addFlags(
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_ALLOW_LOCK_WHILE_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
            println("$TAG 🔐 Lock-screen call flags ENABLED")
        } else {
            window.clearFlags(
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_ALLOW_LOCK_WHILE_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
            println("$TAG 🔐 Lock-screen call flags DISABLED")
        }
    }
    
    private fun handleIntent(intent: Intent) {
        if (intent.getBooleanExtra("acceptCall", false)) {
            val callerId = intent.getStringExtra("callerId") ?: "0"
            val channelName = intent.getStringExtra("channelName") ?: ""
            val isVideo = intent.getBooleanExtra("isVideo", false)
            println("$TAG 📞 handleIntent: Found acceptCall extra. callerId=$callerId isVideo=$isVideo")
            
             stopCallNotification()

            if (isFlutterReady && methodChannel != null) {
                // Flutter is ready, invoke directly
                invokeAcceptCall(callerId, channelName, isVideo)
            } else {
                // Flutter not ready, cache it
                println("$TAG ⚠️ Flutter not ready (isFlutterReady=$isFlutterReady), caching acceptCall action")
                pendingCallAction = mapOf(
                    "action" to "acceptCall",
                    "callerId" to callerId,
                    "channelName" to channelName,
                    "isVideo" to isVideo.toString()
                )
            }
            clearCallIntentExtras(intent)
        } else if (intent.getBooleanExtra("declineCall", false)) {
            val callerId = intent.getStringExtra("callerId") ?: "0"
            val channelName = intent.getStringExtra("channelName") ?: ""
            println("$TAG 📵 handleIntent: Found declineCall extra. callerId=$callerId")

            stopCallNotification()

            if (isFlutterReady && methodChannel != null) {
                invokeDeclineCall(callerId, channelName)
                // Minimize app check is handled by Flutter
            } else {
                println("$TAG ⚠️ Flutter not ready (isFlutterReady=$isFlutterReady), caching declineCall action")
                pendingCallAction = mapOf(
                    "action" to "declineCall",
                    "callerId" to callerId,
                    "channelName" to channelName
                )
            }
            clearCallIntentExtras(intent)
        }
    }

    private fun clearCallIntentExtras(intent: Intent) {
        intent.removeExtra("callIncoming")
        intent.removeExtra("acceptCall")
        intent.removeExtra("declineCall")
        intent.removeExtra("callerId")
        intent.removeExtra("channelName")
        intent.removeExtra("isVideo")
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Setup MethodChannel for call notifications
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
                try {
                // ... (omitted handlers for brevity, they are same as before) ...
                    when (call.method) {
                        "flutterReady" -> {
                            println("$TAG 🚀 flutterReady received from Dart")
                            isFlutterReady = true
                            
                            // Execute cached actions now that Flutter is waiting
                            pendingCallAction?.let { action ->
                                println("$TAG 🔄 Executing pending action via flutterReady: ${action["action"]}")
                                if (action["action"] == "acceptCall") {
                                    val isVideo = action["isVideo"]?.toBoolean() ?: false
                                    invokeAcceptCall(action["callerId"]!!, action["channelName"]!!, isVideo)
                                } else if (action["action"] == "declineCall") {
                                    invokeDeclineCall(action["callerId"]!!, action["channelName"]!!)
                                }
                                pendingCallAction = null
                            }
                            result.success(null)
                        }
                        "startCallNotification" -> {
                            val callerId = call.argument<String>("callerId")
                            val callerName = call.argument<String>("callerName")
                            val channelName = call.argument<String>("channelName")
                            val isVideo = call.argument<Boolean>("isVideo")

                            startCallNotification(
                                callerId ?: "0",
                                callerName ?: "Incoming Call",
                                channelName ?: "",
                                isVideo ?: false
                            )
                            result.success(null)
                        }
                        "stopCallNotification" -> {
                             stopCallNotification()
                             result.success(null)
                        }
                        "showBackgroundCallNotification" -> {
                            val callerName = call.argument<String>("callerName")
                            val channelName = call.argument<String>("channelName")
                            showBackgroundCallNotification(callerName ?: "", channelName ?: "")
                            result.success(null)
                        }
                        "hideBackgroundCallNotification" -> {
                            hideBackgroundCallNotification()
                            result.success(null)
                        }
                        "minimizeApp" -> {
                            println("$TAG 📉 minimizeApp called from Flutter")
                            moveTaskToBack(true)
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    println("$TAG ❌ Error in method call: ${e.message}")
                    result.error("ERROR", e.message, null)
                }
            }
            
        // Check for pending actions
        pendingCallAction?.let { action ->
            println("$TAG 🔄 Executing pending action: ${action["action"]}")
            if (action["action"] == "acceptCall") {
                val isVideo = action["isVideo"]?.toBoolean() ?: false
                invokeAcceptCall(action["callerId"]!!, action["channelName"]!!, isVideo)
            } else if (action["action"] == "declineCall") {
                invokeDeclineCall(action["callerId"]!!, action["channelName"]!!)
            }
            pendingCallAction = null
        }
    }

    private fun startCallNotification(
        callerId: String,
        callerName: String,
        channelName: String,
        isVideo: Boolean
    ) {
        println("$TAG 📞 startCallNotification called")

        val intent = Intent(this, CallNotificationService::class.java).apply {
            action = "START_CALL"
            putExtra("callerId", callerId)
            putExtra("callerName", callerName)
            putExtra("channelName", channelName)
            putExtra("isVideo", isVideo)
            putExtra("playRingtone", true) // Enabled to ensure sound plays in background
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                try {
                    startForegroundService(intent)
                    println("$TAG ✅ startForegroundService succeeded")
                } catch (e: Exception) {
                    // This can happen if app is in background and restricted.
                    // But we likely was triggered by FCM which gives us temp whitelist.
                    println("$TAG ⚠️ startForegroundService failed (${e.message}), falling back to startService")
                    startService(intent)
                }
            } else {
                startService(intent)
            }
            println("$TAG ✅ startCallNotification sent to service")
        } catch (e: Exception) {
            println("$TAG ❌ Error starting service: ${e.message}")
            e.printStackTrace()
        }
    }

    private fun stopCallNotification() {
        println("$TAG 📵 stopCallNotification called")

        val intent = Intent(this, CallNotificationService::class.java).apply {
            action = "STOP_CALL"
        }

        try {
            stopService(intent)
            println("$TAG ✅ stopCallNotification sent to service")
        } catch (e: Exception) {
            println("$TAG ❌ Error stopping service: ${e.message}")
            e.printStackTrace()
        }
    }

    private fun showBackgroundCallNotification(callerName: String, channelName: String) {
        println("$TAG 📱 showBackgroundCallNotification: $callerName")
        
        try {
            val intent = Intent(this, CallNotificationService::class.java).apply {
                action = "SHOW_BACKGROUND_NOTIFICATION"
                putExtra("callerName", callerName)
                putExtra("channelName", channelName)
            }
            startService(intent) // Background notifications don't strictly need startForeground IF we are already running? No, stick to pattern.
            // Actually, if we are in call, we are likely foreground.
            println("$TAG ✅ Background notification service called")
        } catch (e: Exception) {
            println("$TAG ❌ Error showing background notification: ${e.message}")
        }
    }

    private fun hideBackgroundCallNotification() {
        println("$TAG 📵 hideBackgroundCallNotification")
        try {
            val intent = Intent(this, CallNotificationService::class.java).apply {
                action = "HIDE_BACKGROUND_NOTIFICATION"
            }
            startService(intent)
            println("$TAG ✅ Background notification hidden")
        } catch (e: Exception) {
            println("$TAG ❌ Error hiding background notification: ${e.message}")
        }
    }
}
