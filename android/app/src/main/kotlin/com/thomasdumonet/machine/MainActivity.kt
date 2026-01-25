package com.thomasdumonet.machine

import android.content.ComponentName
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.machine/termux_service"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "startTermuxService") {
                val path = call.argument<String>("path")
                val arguments = call.argument<List<String>>("arguments")
                val workdir = call.argument<String>("workdir")
                val background = call.argument<Boolean>("background") ?: true
                val sessionAction = call.argument<String>("sessionAction") ?: "0"

                try {
                    val intent = Intent()
                    intent.component = ComponentName("com.termux", "com.termux.app.RunCommandService")
                    intent.action = "com.termux.RUN_COMMAND"
                    
                    intent.putExtra("com.termux.RUN_COMMAND_PATH", path)
                    // Termux expects a String Array for arguments
                    intent.putExtra("com.termux.RUN_COMMAND_ARGUMENTS", arguments?.toTypedArray())
                    intent.putExtra("com.termux.RUN_COMMAND_WORKDIR", workdir)
                    intent.putExtra("com.termux.RUN_COMMAND_BACKGROUND", background)
                    intent.putExtra("com.termux.RUN_COMMAND_SESSION_ACTION", sessionAction)

                    // Start the Termux Background Service
                    context.startService(intent)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("INTENT_FAILED", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}