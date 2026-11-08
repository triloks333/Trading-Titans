package com.kwm.tradingtitans

import android.app.Activity
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null

    // Android 14+ tells the app a screenshot was taken (no image access);
    // forwarded to Dart for the per-screen screenshot count.
    private val screenCapture: Any? =
        if (Build.VERSION.SDK_INT >= 34) Activity.ScreenCaptureCallback { channel?.invokeMethod("screenshot", null) } else null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tt/screen_capture")
    }

    override fun onStart() {
        super.onStart()
        if (Build.VERSION.SDK_INT >= 34) {
            registerScreenCaptureCallback(mainExecutor, screenCapture as Activity.ScreenCaptureCallback)
        }
    }

    override fun onStop() {
        if (Build.VERSION.SDK_INT >= 34) {
            unregisterScreenCaptureCallback(screenCapture as Activity.ScreenCaptureCallback)
        }
        super.onStop()
    }
}
