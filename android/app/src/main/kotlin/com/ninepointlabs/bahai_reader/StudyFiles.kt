package com.ninepointlabs.bahai_reader

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import io.flutter.plugin.common.MethodChannel

/**
 * The `bahai_reader/files` channel (lib/features/study/study_actions.dart, study_incoming.dart):
 * - PDFs given to the app ("Open with", Share) are read once and handed to Study, which copies them in;
 * - "save": a Markdown export, written where the person picks in Android's "Save to" screen.
 * Nothing is sent anywhere: the app has no network permission.
 */
object StudyFiles {
    const val SAVE_REQUEST = 41
    private val incoming = mutableListOf<Map<String, Any>>()
    private var saveResult: MethodChannel.Result? = null
    private var saveText: String? = null
    var onIncoming: (() -> Unit)? = null

    /** A PDF the activity was started or re-opened with: read now, while the permission to read it lasts. */
    fun take(activity: Activity, intent: Intent?) {
        intent ?: return
        val uri: Uri? = when (intent.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND -> if (Build.VERSION.SDK_INT >= 33) {
                intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                @Suppress("DEPRECATION") intent.getParcelableExtra(Intent.EXTRA_STREAM)
            }
            else -> null
        }
        uri ?: return
        try {
            val bytes = activity.contentResolver.openInputStream(uri)?.use { it.readBytes() } ?: return
            incoming.add(mapOf("name" to nameOf(activity, uri), "bytes" to bytes))
            intent.action = null
            onIncoming?.invoke()
        } catch (e: Exception) {
            incoming.add(mapOf("name" to nameOf(activity, uri), "error" to (e.message ?: e.javaClass.simpleName)))
            onIncoming?.invoke()
        }
    }

    private fun nameOf(activity: Activity, uri: Uri): String {
        try {
            activity.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                if (c.moveToFirst()) {
                    val name = c.getString(0)
                    if (!name.isNullOrBlank()) return name
                }
            }
        } catch (e: Exception) {
        }
        return uri.lastPathSegment?.substringAfterLast('/') ?: "book.pdf"
    }

    fun takeIncoming(): List<Map<String, Any>> {
        val out = incoming.toList()
        incoming.clear()
        return out
    }

    fun save(activity: Activity, name: String, mime: String, text: String, result: MethodChannel.Result) {
        saveResult?.success(false)
        saveResult = result
        saveText = text
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = mime
            putExtra(Intent.EXTRA_TITLE, name)
        }
        try {
            activity.startActivityForResult(intent, SAVE_REQUEST)
        } catch (e: Exception) {
            saveResult = null
            result.error("unavailable", "No app can save files here.", null)
        }
    }

    fun saved(activity: Activity, resultCode: Int, data: Intent?) {
        val result = saveResult ?: return
        saveResult = null
        val text = saveText
        saveText = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null || text == null) {
            result.success(false)
            return
        }
        try {
            activity.contentResolver.openOutputStream(uri, "wt")?.use { it.write(text.toByteArray(Charsets.UTF_8)) }
            result.success(true)
        } catch (e: Exception) {
            result.error("write", e.message ?: "The file could not be written.", null)
        }
    }
}
