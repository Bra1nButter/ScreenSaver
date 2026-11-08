package com.screensaver.screen_saver

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import java.io.File
import java.io.FileNotFoundException

class ApkFileProvider : ContentProvider() {

    companion object {
        fun getUriForFile(packageName: String, file: File): Uri {
            return Uri.Builder()
                .scheme("content")
                .authority("$packageName.apkprovider")
                .path(file.name)
                .build()
        }
    }

    override fun onCreate(): Boolean = true

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor? {
        val ctx = context ?: throw FileNotFoundException("Context is null")
        val fileName = uri.lastPathSegment ?: throw FileNotFoundException("Missing file name")
        val file = File(File(ctx.cacheDir, "updates"), fileName)
        if (!file.exists()) {
            throw FileNotFoundException("APK file not found: ${file.absolutePath}")
        }
        return ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
    }

    override fun getType(uri: Uri): String = "application/vnd.android.package-archive"

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?
    ): Cursor? {
        val ctx = context ?: return null
        val fileName = uri.lastPathSegment ?: return null
        val file = File(File(ctx.cacheDir, "updates"), fileName)
        if (!file.exists()) return null

        val columns = projection ?: arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
        val row = Array<Any?>(columns.size) { index ->
            when (columns[index]) {
                OpenableColumns.DISPLAY_NAME -> file.name
                OpenableColumns.SIZE -> file.length()
                else -> null
            }
        }
        return MatrixCursor(columns, 1).apply { addRow(row) }
    }

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int = 0
}