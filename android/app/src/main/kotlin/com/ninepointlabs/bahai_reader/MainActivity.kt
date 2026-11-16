package com.ninepointlabs.bahai_reader

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.util.TimeZone

/** The reader, plus the `bahai_reader/reminders` channel (lib/core/platform/notifier.dart, AndroidNotifier). */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var permissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Reminders.ensureChannel(this)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "bahai_reader/reminders")
        channel = ch
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "zone" -> result.success(TimeZone.getDefault().id)
                "show" -> {
                    Reminders.show(this, JSONObject(call.arguments as Map<*, *>))
                    result.success(Reminders.enabled(this))
                }
                "withdraw" -> {
                    Reminders.withdraw(this, call.arguments as String)
                    result.success(null)
                }
                "schedule" -> {
                    Reminders.schedule(this, JSONArray(call.arguments as List<*>))
                    result.success(Reminders.enabled(this))
                }
                "takePending" -> result.success(Reminders.takePending(this))
                "requestPermission" -> {
                    if (Build.VERSION.SDK_INT >= 33 &&
                        checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
                    ) {
                        permissionResult?.success(Reminders.enabled(this))
                        permissionResult = result
                        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
                    } else {
                        result.success(Reminders.enabled(this))
                    }
                }
                else -> result.notImplemented()
            }
        }
        Reminders.onPending = { Handler(Looper.getMainLooper()).post { channel?.invokeMethod("pending", null) } }
        queueOpen(intent)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        permissionResult?.success(Reminders.enabled(this))
        permissionResult = null
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        queueOpen(intent)
    }

    /** A tap on a reminder: what it opens is queued for the app (it asks at start, and is told while running). */
    private fun queueOpen(intent: Intent?) {
        val opens = intent?.getStringExtra(Reminders.EXTRA_OPEN) ?: return
        intent.removeExtra(Reminders.EXTRA_OPEN)
        Reminders.queue(this, "open:$opens")
    }

    override fun onDestroy() {
        Reminders.onPending = null
        channel = null
        super.onDestroy()
    }
}
