package com.thomasdumonet.machine

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.*

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example/file_handler"
    private var openFileResult: MethodChannel.Result? = null
    private var saveFileResult: MethodChannel.Result? = null
    private var openFolderResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "openFile" -> {
                    openFileResult = result
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "*/*"
                    }
                    startActivityForResult(intent, 101)
                }
                "openFolder" -> {
                    openFolderResult = result
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
                    startActivityForResult(intent, 103)
                }
                "listDirectory" -> {
                    val uri = Uri.parse(call.argument<String>("uri"))
                    val children = listDirectory(uri)
                    result.success(children)
                }
                "readFile" -> {
                    val uri = Uri.parse(call.argument<String>("uri"))
                    val content = readFileContent(uri)
                    result.success(content)
                }
                "writeFile" -> {
                    val uri = Uri.parse(call.argument<String>("uri"))
                    val content = call.argument<String>("content")!!
                    writeFileContent(uri, content)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        when (requestCode) {
            101 -> handleOpenFileResult(resultCode, data)
            103 -> handleOpenFolderResult(resultCode, data)
        }
    }

    private fun handleOpenFileResult(resultCode: Int, data: Intent?) {
        if (resultCode == Activity.RESULT_OK && data != null) {
            data.data?.let { uri ->
                persistUriPermission(uri)
                openFileResult?.success(uri.toString())
                return
            }
        }
        openFileResult?.success(null)
    }

    private fun handleOpenFolderResult(resultCode: Int, data: Intent?) {
        if (resultCode == Activity.RESULT_OK && data != null) {
            data.data?.let { uri ->
                persistUriPermission(uri)
                openFolderResult?.success(uri.toString())
                return
            }
        }
        openFolderResult?.success(null)
    }

    private fun persistUriPermission(uri: Uri) {
        contentResolver.takePersistableUriPermission(
            uri,
            Intent.FLAG_GRANT_READ_URI_PERMISSION or
            Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        )
    }

    private fun listDirectory(uri: Uri): List<Map<String, String>> {
        val children = mutableListOf<Map<String, String>>()
        val childUris = DocumentsContract.buildChildDocumentsUriUsingTree(
            uri, 
            DocumentsContract.getTreeDocumentId(uri)
        )

        contentResolver.query(
            childUris,
            arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_MIME_TYPE
            ),
            null,
            null,
            null
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                val id = cursor.getString(0)
                val name = cursor.getString(1)
                val mime = cursor.getString(2)
                
                children.add(mapOf(
                    "uri" to DocumentsContract.buildDocumentUriUsingTree(uri, id).toString(),
                    "name" to name,
                    "type" to if (mime == DocumentsContract.Document.MIME_TYPE_DIR) "dir" else "file"
                ))
            }
        }
        return children
    }

    private fun readFileContent(uri: Uri): String? {
        return try {
            contentResolver.openInputStream(uri)?.use { stream ->
                stream.bufferedReader().use { it.readText() }
            }
        } catch (e: Exception) {
            null
        }
    }

    private fun writeFileContent(uri: Uri, content: String) {
        try {
            contentResolver.openOutputStream(uri)?.use { stream ->
                stream.write(content.toByteArray())
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
}