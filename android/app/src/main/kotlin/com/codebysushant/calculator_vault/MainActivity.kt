package com.codebysushant.calculator_vault

import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Handles the `calculator_vault/secure_screen` method channel.
 *
 * `enable`  -> adds FLAG_SECURE: screenshots blocked, recents preview blank.
 * `disable` -> clears FLAG_SECURE (plain calculator mode).
 *
 * NOTE: if you change the applicationId/org during `flutter create`, update
 * the package line above to match the generated MainActivity's package.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "calculator_vault/secure_screen"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enable" -> {
                        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        result.success(null)
                    }
                    "disable" -> {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
