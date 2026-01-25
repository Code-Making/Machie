package com.thomasdumonet.machine

import android.content.ComponentName
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.machine/termux_service"

    override reinstatement(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "startTermuxService") {
                try {
                    val intent = Intent()
                    intent.component = ComponentName("com.termux", "com.termux.app.RunCommandService")
                    intent.action = "com.termux.RUN_COMMAND"
                    
                    // Map the arguments from Flutter
                    intent.putExtra("com.termux.RUN_COMMAND_PATH", call.argument<String>("path"))
                    intent.putExtra("com.termux.RUN_COMMAND_ARGUMENTS", call.argument<List<String>>("arguments")?.toTypedArray())
                    intent.putExtra("com.termux.RUN_COMMAND_WORKDIR", call.argument<String>("workdir"))
                    intent.putExtra("com.termux.RUN_COMMAND_BACKGROUND", call.argument<Boolean>("background") ?: true)
                    intent.putExtra("com.termux.RUN_COMMAND_SESSION_ACTION", call.argument<String>("sessionAction") ?: "0")

                    // CORRECT CALL: startService, not startActivity
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