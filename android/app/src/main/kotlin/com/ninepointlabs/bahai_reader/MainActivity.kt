package com.ninepointlabs.bahai_reader

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.util.TimeZone

/**
 * The reader, plus the `bahai_reader/reminders` channel (lib/core/platform/notifier.dart, AndroidNotifier), the
 * `bahai_reader/location` channel (lib/core/platform/locator.dart) and the `bahai_reader/files` channel (StudyFiles.kt).
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var permissionResult: MethodChannel.Result? = null
    private var locationResult: MethodChannel.Result? = null

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
                "exact" -> result.success(Reminders.exact(this))
                "requestExact" -> {
                    // Android 12 and later: "Alarms & reminders" is a switch in settings, not a dialog.
                    if (Build.VERSION.SDK_INT >= 31 && !Reminders.exact(this)) {
                        try {
                            startActivity(
                                Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.parse("package:$packageName"))
                            )
                        } catch (e: Exception) {
                        }
                    }
                    result.success(Reminders.exact(this))
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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "bahai_reader/location").setMethodCallHandler { call, result ->
            if (call.method != "locate") return@setMethodCallHandler result.notImplemented()
            locationResult?.success(mapOf("error" to "Asked again."))
            locationResult = result
            if (checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED) {
                locate()
            } else {
                requestPermissions(arrayOf(Manifest.permission.ACCESS_COARSE_LOCATION), 2)
            }
        }
        Reminders.onPending = { Handler(Looper.getMainLooper()).post { channel?.invokeMethod("pending", null) } }
        queueOpen(intent)
        val files = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "bahai_reader/files")
        files.setMethodCallHandler { call, result ->
            when (call.method) {
                "takeIncoming" -> result.success(StudyFiles.takeIncoming())
                "save" -> StudyFiles.save(
                    this,
                    call.argument<String>("name") ?: "export.md",
                    call.argument<String>("mime") ?: "text/markdown",
                    call.argument<String>("text") ?: "",
                    result,
                )
                else -> result.notImplemented()
            }
        }
        StudyFiles.onIncoming = { Handler(Looper.getMainLooper()).post { files.invokeMethod("incoming", null) } }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "bahai_reader/folder").setMethodCallHandler { call, result ->
            val uri = call.argument<String>("uri")
            val sub = call.argument<String>("sub")
            // Folder work off the main thread; answers back on it.
            fun io(work: () -> Any?) = Thread {
                val out = try { Result.success(work()) } catch (e: Exception) { Result.failure(e) }
                Handler(Looper.getMainLooper()).post {
                    out.fold({ result.success(it) }, { result.error("folder", it.message ?: it.javaClass.simpleName, null) })
                }
            }.start()
            when (call.method) {
                "pick" -> SyncTree.pick(this, result)
                "name" -> result.success(SyncTree.name(this, uri!!))
                "list" -> io { SyncTree.list(this, uri!!, sub) }
                "read" -> io { SyncTree.read(this, uri!!, call.argument<String>("name")!!, sub) }
                "write" -> io { SyncTree.write(this, uri!!, call.argument<String>("name")!!, sub, call.argument<ByteArray>("bytes")!!); null }
                else -> result.notImplemented()
            }
        }
        StudyFiles.take(this, intent)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == StudyFiles.SAVE_REQUEST) StudyFiles.saved(this, resultCode, data)
        if (requestCode == SyncTree.PICK_REQUEST) SyncTree.picked(this, resultCode, data)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 2) {
            if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
                locate()
            } else {
                locationResult?.success(mapOf("error" to "Location permission was not given. You can search for your city instead."))
                locationResult = null
            }
            return
        }
        permissionResult?.success(Reminders.enabled(this))
        permissionResult = null
    }

    private fun locate() {
        Locate.once(this) { at, error ->
            val r = locationResult ?: return@once
            locationResult = null
            r.success(if (at != null) mapOf("lat" to at[0], "lon" to at[1]) else mapOf("error" to error))
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        queueOpen(intent)
        StudyFiles.take(this, intent)
    }

    /** A tap on a reminder: what it opens is queued for the app (it asks at start, and is told while running). */
    private fun queueOpen(intent: Intent?) {
        val opens = intent?.getStringExtra(Reminders.EXTRA_OPEN) ?: return
        intent.removeExtra(Reminders.EXTRA_OPEN)
        Reminders.queue(this, "open:$opens")
    }

    override fun onDestroy() {
        Reminders.onPending = null
        StudyFiles.onIncoming = null
        channel = null
        super.onDestroy()
    }
}
