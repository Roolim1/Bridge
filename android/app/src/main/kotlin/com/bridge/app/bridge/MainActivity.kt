package com.bridge.app.bridge // FIX: Matched package name to build.gradle.kts

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val ROUTE_CHANNEL = "app.channel.bridge/route"
    private val SHARE_CHANNEL = "app.channel.bridge/share" // <-- NAYA CHANNEL

    private var sharedFilePath: String? = null // <-- File path store karne ke liye

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Purana route channel (Quick Tile ke liye)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ROUTE_CHANNEL).setMethodCallHandler {
                call, result ->
            if (call.method == "getInitialRoute") {
                val route = intent?.getStringExtra("route")
                if (route != null) {
                    result.success(route)
                    intent?.removeExtra("route") // Route ko clear karein
                } else {
                    result.success("/")
                }
            } else {
                result.notImplemented()
            }
        }

        // Naya share channel (File path dene ke liye)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SHARE_CHANNEL).setMethodCallHandler {
                call, result ->
            if (call.method == "getSharedFilePath") {
                // Jab app start hui, tab path store kar liya tha
                if (sharedFilePath != null) {
                    result.success(sharedFilePath)
                    sharedFilePath = null // Path ko clear karein
                } else {
                    // Agar path null hai (shayad app normal tarike se khuli hai)
                    // Toh intent se check karein
                    val path = intent?.getStringExtra("sharedFilePath")
                    if (path != null) {
                        result.success(path)
                        intent?.removeExtra("sharedFilePath")
                    } else {
                        result.success(null)
                    }
                }
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent) // Naye intent ko set karein

        // Agar app pehle se khuli hai aur share kiya jaaye
        val route = intent.getStringExtra("route")
        if (route != null) {
            if (route == "/share") {
                // Share route ke liye file path bhi store karein
                sharedFilePath = intent.getStringExtra("sharedFilePath")
            }
            MethodChannel(flutterEngine!!.dartExecutor.binaryMessenger, ROUTE_CHANNEL)
                .invokeMethod("navigateTo", route) // Flutter ko navigate karne bolein
            intent.removeExtra("route")
        }
    }

    override fun onPostResume() {
        super.onPostResume()
        // Agar app cold start hui hai (share se)
        if (intent?.getStringExtra("route") == "/share") {
            sharedFilePath = intent.getStringExtra("sharedFilePath")
            // Channel ko trigger karein (agar Flutter pehle se ready hai)
            MethodChannel(flutterEngine!!.dartExecutor.binaryMessenger, ROUTE_CHANNEL)
                .invokeMethod("navigateTo", "/share")
            intent.removeExtra("route")
            intent.removeExtra("sharedFilePath")
        }
    }
}
