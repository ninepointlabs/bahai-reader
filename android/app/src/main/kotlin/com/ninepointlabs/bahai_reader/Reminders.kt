package com.ninepointlabs.bahai_reader

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject

/**
 * Reminders on Android (lib/core/platform/notifier.dart, AndroidNotifier). The app works out which reminders there are
 * (a port of the GTK app's rules) and hands the week ahead over here; each is set as an alarm, shown as a notification
 * when it falls due (unless already stale), and set again after the phone restarts. "Said today" on a notification is
 * kept until the app next looks ([takePending]), and stops that prayer's later reminders at once. Nothing leaves the
 * device: there is no network permission.
 */
object Reminders {
    const val CHANNEL_ID = "reminders"
    const val EXTRA_KEY = "bahai_reader.key"
    const val EXTRA_OPEN = "bahai_reader.open"
    const val EXTRA_SAID = "bahai_reader.said"
    const val EXTRA_TAG = "bahai_reader.tag"
    private const val PREFS = "bahai_reader_reminders"
    private const val SCHEDULED = "scheduled"
    private const val PENDING = "pending"

    /** Called when something is queued while the app is running, so it can fetch it. Set by MainActivity. */
    var onPending: (() -> Unit)? = null

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < 26) return
        val manager = context.getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CHANNEL_ID) == null) {
            val channel = NotificationChannel(CHANNEL_ID, "Reminders", NotificationManager.IMPORTANCE_DEFAULT)
            channel.description = "Obligatory prayer, Feasts, Holy Days and the Fast"
            manager.createNotificationChannel(channel)
        }
    }

    fun enabled(context: Context): Boolean {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        return if (Build.VERSION.SDK_INT >= 24) manager.areNotificationsEnabled() else true
    }

    /** Whether alarms may fire at the minute set (Android 12 and later ask for "Alarms & reminders"). */
    fun exact(context: Context): Boolean {
        val alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        return Build.VERSION.SDK_INT < 31 || alarms.canScheduleExactAlarms()
    }

    private fun flags() = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE

    private fun openIntent(context: Context, opens: String, code: Int): PendingIntent {
        val intent = Intent(context, MainActivity::class.java)
            .setAction("bahai_reader.OPEN.$opens")
            .putExtra(EXTRA_OPEN, opens)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        return PendingIntent.getActivity(context, code, intent, flags())
    }

    /** Shows a reminder now, replacing what is shown for its group. */
    fun show(context: Context, r: JSONObject) {
        ensureChannel(context)
        val now = System.currentTimeMillis()
        val until = r.optLong("until", 0)
        if (until in 1..now) return
        val tag = r.getString("tag")
        val opens = r.optString("opens", "today")
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, CHANNEL_ID) else Notification.Builder(context)
        builder.setSmallIcon(android.R.drawable.ic_popup_reminder)
            .setContentTitle(r.getString("title"))
            .setContentText(r.getString("body"))
            .setStyle(Notification.BigTextStyle().bigText(r.getString("body")))
            .setAutoCancel(true)
            .setContentIntent(openIntent(context, opens, tag.hashCode()))
        if (Build.VERSION.SDK_INT >= 26 && until > now) builder.setTimeoutAfter(until - now)
        val said = if (r.isNull("said")) null else r.optString("said")
        if (!said.isNullOrEmpty()) {
            val intent = Intent(context, ActionReceiver::class.java)
                .setAction("bahai_reader.SAID.$said")
                .putExtra(EXTRA_SAID, said)
                .putExtra(EXTRA_TAG, tag)
            val pending = PendingIntent.getBroadcast(context, said.hashCode(), intent, flags())
            builder.addAction(Notification.Action.Builder(null, "Said today", pending).build())
        }
        builder.addAction(Notification.Action.Builder(null, "Open", openIntent(context, opens, tag.hashCode() + 1)).build())
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        try {
            manager.notify(tag, 1, builder.build())
        } catch (e: SecurityException) {
            // Notifications not permitted.
        }
    }

    fun withdraw(context: Context, tag: String) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.cancel(tag, 1)
    }

    private fun alarmIntent(context: Context, key: String): PendingIntent {
        val intent = Intent(context, AlarmReceiver::class.java).setAction("bahai_reader.ALARM.$key").putExtra(EXTRA_KEY, key)
        return PendingIntent.getBroadcast(context, key.hashCode(), intent, flags())
    }

    private fun stored(context: Context): JSONArray = try {
        JSONArray(prefs(context).getString(SCHEDULED, "[]"))
    } catch (e: Exception) {
        JSONArray()
    }

    /** Replaces every alarm set before with [reminders]. */
    fun schedule(context: Context, reminders: JSONArray) {
        val alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val old = stored(context)
        for (i in 0 until old.length()) alarms.cancel(alarmIntent(context, old.getJSONObject(i).getString("key")))
        prefs(context).edit().putString(SCHEDULED, reminders.toString()).apply()
        arm(context, reminders)
    }

    /** Sets an alarm for each reminder still to come: exact where the system allows it, else as near as it allows. */
    fun arm(context: Context, reminders: JSONArray = stored(context)) {
        val alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val now = System.currentTimeMillis()
        val exact = exact(context)
        for (i in 0 until reminders.length()) {
            val r = reminders.getJSONObject(i)
            val at = r.getLong("at")
            if (r.getLong("until") <= now) continue
            val intent = alarmIntent(context, r.getString("key"))
            val time = maxOf(at, now)
            if (exact) {
                alarms.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, time, intent)
            } else {
                alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, time, intent)
            }
        }
    }

    fun fire(context: Context, key: String) {
        val all = stored(context)
        for (i in 0 until all.length()) {
            val r = all.getJSONObject(i)
            if (r.getString("key") == key) show(context, r)
        }
    }

    /** "Said today" from a notification: kept for the app, the notification taken down, and that prayer's later reminders dropped. */
    fun said(context: Context, said: String, tag: String) {
        queue(context, "said:$said")
        withdraw(context, tag)
        val alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val all = stored(context)
        val kept = JSONArray()
        for (i in 0 until all.length()) {
            val r = all.getJSONObject(i)
            if (!r.isNull("said") && r.optString("said") == said) {
                alarms.cancel(alarmIntent(context, r.getString("key")))
            } else {
                kept.put(r)
            }
        }
        prefs(context).edit().putString(SCHEDULED, kept.toString()).apply()
    }

    fun queue(context: Context, action: String) {
        val list = try { JSONArray(prefs(context).getString(PENDING, "[]")) } catch (e: Exception) { JSONArray() }
        list.put(action)
        prefs(context).edit().putString(PENDING, list.toString()).apply()
        onPending?.invoke()
    }

    fun takePending(context: Context): List<String> {
        val list = try { JSONArray(prefs(context).getString(PENDING, "[]")) } catch (e: Exception) { JSONArray() }
        prefs(context).edit().remove(PENDING).apply()
        return (0 until list.length()).map { list.getString(it) }
    }
}

class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val key = intent.getStringExtra(Reminders.EXTRA_KEY) ?: return
        Reminders.fire(context, key)
    }
}

class ActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val said = intent.getStringExtra(Reminders.EXTRA_SAID) ?: return
        val tag = intent.getStringExtra(Reminders.EXTRA_TAG) ?: return
        Reminders.said(context, said, tag)
    }
}

/** Alarms do not survive a restart of the phone or an update of the app: set them again. Also when "Alarms & reminders"
 * is allowed, so they become exact. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Reminders.arm(context)
    }
}
