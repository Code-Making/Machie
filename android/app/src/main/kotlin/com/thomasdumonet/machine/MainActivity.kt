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
                    val isRoot = call.argument<Boolean>("isRoot") ?: false
                    
                    val children = if (isRoot) {
                        listRootDirectory(uri)
                    } else {
                        listDirectory(uri)
                    }
                    
                    result.success(children)
                }
        "readFile" -> {
            val uri = Uri.parse(call.argument<String>("uri"))
            val readResult = readFileContent(uri) // Renamed variable
            val response = mapOf(
                "content" to readResult.content,
                "error" to readResult.error,
                "isEmpty" to readResult.isEmpty
            )
            result.success(response) // Use method channel result
        }
        "writeFile" -> {
            val uri = Uri.parse(call.argument<String>("uri"))
            val content = call.argument<String>("content")!!
            val writeResult = writeFileContent(uri, content) // Renamed variable
            result.success(mapOf(
                "success" to writeResult.success,
                "error" to writeResult.error,
                "checksum" to writeResult.checksum
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
    
    override fun onCreate(savedInstanceState: Bundle?) {
      super.onCreate(savedInstanceState)
      handleIntent(intent)
    }
    
    override fun onNewIntent(intent: Intent) {
      super.onNewIntent(intent)
      handleIntent(intent)
    }
    
    private fun handleIntent(intent: Intent) {
      if (intent.action == Intent.ACTION_VIEW) {
        intent.data?.let { uri ->
          MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example/file_handler")
            .invokeMethod("openFileFromIntent", uri.toString())
        }
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
    try {
        // Get the document ID from the provided URI
        val docId = DocumentsContract.getDocumentId(uri)
        
        // Build the correct child URI for this specific directory
        val childUris = DocumentsContract.buildChildDocumentsUriUsingTree(
            uri, 
            docId
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
    } catch (e: Exception) {
        Log.e("SAF", "Error listing directory: ${e.message}")
    }
    return children
}

private fun listRootDirectory(uri: Uri): List<Map<String, String>> {
    val children = mutableListOf<Map<String, String>>()
    try {
        // Get root document ID from tree URI
        val rootId = DocumentsContract.getTreeDocumentId(uri)
        
        val childUris = DocumentsContract.buildChildDocumentsUriUsingTree(
            uri, 
            rootId
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
    } catch (e: Exception) {
        Log.e("SAF", "Error listing root directory: ${e.message}")
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
            }

            // Calculate checksum AFTER writing
            val inputStream = contentResolver.openInputStream(uri)!!
            val md5 = MessageDigest.getInstance("MD5")
            val digest = md5.digest(inputStream.readBytes())
            val checksum = digest.joinToString("") { "%02x".format(it) }

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