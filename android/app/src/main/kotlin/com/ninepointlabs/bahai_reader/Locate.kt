package com.ninepointlabs.bahai_reader

import android.content.Context
import android.location.Location
import android.location.LocationManager
import android.os.Build
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper

/**
 * "Use my location" (lib/core/platform/locator.dart): one approximate fix from the phone's own location service, for
 * sunrise and sunset. Asked for only when tapped, never tracked, and never sent anywhere: the app has no network
 * permission. The app rounds it to about a kilometre before saving it.
 */
object Locate {
    private const val TIMEOUT_MS = 30_000L

    /** Calls [done] once, with (latitude, longitude) or why there is none. */
    fun once(context: Context, done: (DoubleArray?, String?) -> Unit) {
        val manager = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        if (Build.VERSION.SDK_INT >= 28 && !manager.isLocationEnabled) {
            return done(null, "Location is turned off in Android’s settings.")
        }
        val providers = buildList {
            if (Build.VERSION.SDK_INT >= 31) add(LocationManager.FUSED_PROVIDER)
            add(LocationManager.NETWORK_PROVIDER)
            add(LocationManager.GPS_PROVIDER)
        }.filter { it in manager.allProviders && manager.isProviderEnabled(it) }
        fun lastKnown(): Location? = try {
            providers.mapNotNull { manager.getLastKnownLocation(it) }.maxByOrNull { it.time }
        } catch (e: SecurityException) {
            null
        }
        if (providers.isEmpty()) return done(null, "No location source is turned on.")
        var finished = false
        val main = Handler(Looper.getMainLooper())
        fun finish(loc: Location?) {
            if (finished) return
            finished = true
            val l = loc ?: lastKnown()
            if (l == null) done(null, "Couldn’t find where you are. Try again, or search for your city.")
            else done(doubleArrayOf(l.latitude, l.longitude), null)
        }
        try {
            if (Build.VERSION.SDK_INT >= 30) {
                val cancel = CancellationSignal()
                manager.getCurrentLocation(providers.first(), cancel, context.mainExecutor) { finish(it) }
                main.postDelayed({ cancel.cancel(); finish(null) }, TIMEOUT_MS)
            } else {
                @Suppress("DEPRECATION")
                manager.requestSingleUpdate(providers.first(), { finish(it) }, Looper.getMainLooper())
                main.postDelayed({ finish(null) }, TIMEOUT_MS)
            }
        } catch (e: SecurityException) {
            finished = true
            done(null, "Location permission was not given.")
        }
    }
}
