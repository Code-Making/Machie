package com.thomasdumonet.machine

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.util.Log
import java.security.MessageDigest
import java.nio.charset.Charset
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
                val result = readFileContent(uri)
                val response = mapOf(
                    "content" to result.content,
                    "error" to result.error,
                    "isEmpty" to result.isEmpty
                )
                result.success(response)
            }
            "writeFile" -> {
                val uri = Uri.parse(call.argument<String>("uri"))
                val content = call.argument<String>("content")!!
                val result = writeFileContent(uri, content)
                result.success(mapOf(
                    "success" to result.success,
                    "error" to result.error,
                    "checksum" to result.checksum
                ))
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

fun persistUriPermission(uri: Uri) {
     try {
       contentResolver.takePersistableUriPermission(
         uri,
         Intent.FLAG_GRANT_READ_URI_PERMISSION or
         Intent.FLAG_GRANT_WRITE_URI_PERMISSION
       )
     } catch (e: SecurityException) {
       Log.e("SAF", "Permission error: ${e.message}")
     }
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


private fun readFileContent(uri: Uri): FileReadResult {
    return try {
        contentResolver.openInputStream(uri)?.use { inputStream ->
            val content = inputStream.bufferedReader().use { it.readText() }
            FileReadResult(
                content = content,
                error = null,
                isEmpty = content.isEmpty()
            )
        } ?: FileReadResult(
            content = null,
            error = "Failed to open input stream",
            isEmpty = false
        )
    } catch (e: Exception) {
        FileReadResult(
            content = null,
            error = "Error reading file: ${e.message}",
            isEmpty = false
        )
    }
}



    private fun writeFileContent(uri: Uri, content: String): FileWriteResult {
    return try {
        contentResolver.openOutputStream(uri)?.use { outputStream ->
            BufferedWriter(OutputStreamWriter(outputStream)).use { writer ->
                writer.write(content)
                writer.flush()
            }
            
            // Calculate new checksum
            val inputStream = contentResolver.openInputStream(uri)!!
            val md5 = MessageDigest.getInstance("MD5")
            val digest = md5.digest(inputStream.readBytes())
            val checksum = digest.fold("") { str, it -> str + "%02x".format(it) }
            
            FileWriteResult(true, null, checksum)
        } ?: FileWriteResult(false, "Failed to open output stream", null)
    } catch (e: Exception) {
        FileWriteResult(false, "Write error: ${e.message}", null)
    }
}
    
    private fun detectCharset(inputStream: InputStream): Charset {
     val bytes = inputStream.readBytes()
     return when {
       bytes.size >= 3 && bytes[0] == 0xEF.toByte() 
         && bytes[1] == 0xBB.toByte() 
         && bytes[2] == 0xBF.toByte() -> Charsets.UTF_8
       bytes.size >= 2 && bytes[0] == 0xFE.toByte() 
         && bytes[1] == 0xFF.toByte() -> Charsets.UTF_16BE
       // Add other encodings as needed
       else -> Charset.defaultCharset()
     }
   }
}

data class FileReadResult(
    val content: String?,
    val error: String?,
    val isEmpty: Boolean
)

data class FileWriteResult(
    val success: Boolean,
    val error: String?,
    val checksum: String?
)