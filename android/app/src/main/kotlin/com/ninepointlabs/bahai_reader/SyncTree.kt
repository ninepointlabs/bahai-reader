package com.ninepointlabs.bahai_reader

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import io.flutter.plugin.common.MethodChannel

/**
 * The `bahai_reader/folder` channel (lib/core/sync/android_tree_folder.dart): a sync folder the person picks in the
 * system's folder picker (one Syncthing, Dropbox or the like keeps in step). The app keeps lasting access to that one
 * folder and reads and writes only its own files in it. No storage permission; no network.
 */
object SyncTree {
    const val PICK_REQUEST = 42
    private var pickResult: MethodChannel.Result? = null

    fun pick(activity: Activity, result: MethodChannel.Result) {
        pickResult?.success(null)
        pickResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        try {
            activity.startActivityForResult(intent, PICK_REQUEST)
        } catch (e: Exception) {
            pickResult = null
            result.error("unavailable", "No folder picker is available.", null)
        }
    }

    fun picked(activity: Activity, resultCode: Int, data: Intent?) {
        val result = pickResult ?: return
        pickResult = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) return result.success(null)
        try {
            activity.contentResolver.takePersistableUriPermission(
                uri, Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            )
            result.success(uri.toString())
        } catch (e: Exception) {
            result.error("permission", e.message ?: "The folder could not be kept.", null)
        }
    }

    private fun treeDoc(tree: Uri): String = DocumentsContract.getTreeDocumentId(tree)

    /** The document id of [name] in the folder [parentDoc], or null. */
    private fun child(activity: Activity, tree: Uri, parentDoc: String, name: String): Pair<String, Boolean>? {
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, parentDoc)
        activity.contentResolver.query(
            children,
            arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_MIME_TYPE),
            null, null, null
        )?.use { c ->
            while (c.moveToNext()) {
                if (c.getString(1) == name) return Pair(c.getString(0), c.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR)
            }
        }
        return null
    }

    private fun folderDoc(activity: Activity, tree: Uri, sub: String?, create: Boolean): String? {
        val root = treeDoc(tree)
        if (sub == null) return root
        child(activity, tree, root, sub)?.let { return it.first }
        if (!create) return null
        val made = DocumentsContract.createDocument(
            activity.contentResolver, DocumentsContract.buildDocumentUriUsingTree(tree, root),
            DocumentsContract.Document.MIME_TYPE_DIR, sub
        ) ?: return null
        return DocumentsContract.getDocumentId(made)
    }

    fun name(activity: Activity, uri: String): String {
        val tree = Uri.parse(uri)
        return treeDoc(tree).substringAfter(':').ifEmpty { treeDoc(tree) }
    }

    fun list(activity: Activity, uri: String, sub: String?): List<Map<String, Any>> {
        val tree = Uri.parse(uri)
        val doc = folderDoc(activity, tree, sub, false) ?: return emptyList()
        val out = mutableListOf<Map<String, Any>>()
        activity.contentResolver.query(
            DocumentsContract.buildChildDocumentsUriUsingTree(tree, doc),
            arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME, DocumentsContract.Document.COLUMN_LAST_MODIFIED,
                DocumentsContract.Document.COLUMN_SIZE, DocumentsContract.Document.COLUMN_MIME_TYPE),
            null, null, null
        )?.use { c ->
            while (c.moveToNext()) {
                if (c.getString(3) == DocumentsContract.Document.MIME_TYPE_DIR) continue
                out.add(mapOf("name" to c.getString(0), "modified" to c.getLong(1), "size" to c.getLong(2)))
            }
        }
        return out
    }

    fun read(activity: Activity, uri: String, name: String, sub: String?): ByteArray? {
        val tree = Uri.parse(uri)
        val folder = folderDoc(activity, tree, sub, false) ?: return null
        val doc = child(activity, tree, folder, name) ?: return null
        return activity.contentResolver.openInputStream(DocumentsContract.buildDocumentUriUsingTree(tree, doc.first))
            ?.use { it.readBytes() }
    }

    fun write(activity: Activity, uri: String, name: String, sub: String?, bytes: ByteArray) {
        val tree = Uri.parse(uri)
        val folder = folderDoc(activity, tree, sub, true) ?: throw IllegalStateException("The folder is not there.")
        val existing = child(activity, tree, folder, name)
        val target = if (existing != null) {
            DocumentsContract.buildDocumentUriUsingTree(tree, existing.first)
        } else {
            DocumentsContract.createDocument(
                activity.contentResolver, DocumentsContract.buildDocumentUriUsingTree(tree, folder),
                if (name.endsWith(".pdf")) "application/pdf" else "application/json", name
            ) ?: throw IllegalStateException("The file could not be made.")
        }
        activity.contentResolver.openOutputStream(target, "wt")?.use { it.write(bytes) }
            ?: throw IllegalStateException("The file could not be written.")
    }
}
