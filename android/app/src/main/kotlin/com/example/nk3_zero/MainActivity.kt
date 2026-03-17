package com.example.nk3_zero

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Main Flutter activity.
 *
 * Registers the "secure_wipe" MethodChannel so that Dart code can call
 * [nativeWipe] in memory_security.dart to zero sensitive strings at the
 * native (JNI / C++) level.
 *
 * Channel protocol:
 *   method : "wipeString"
 *   args   : String — the plaintext to wipe
 *   result : null   — always succeeds (errors are swallowed to avoid crashes)
 */
class MainActivity : FlutterActivity() {

    private val secureWipeChannel = "secure_wipe"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            secureWipeChannel,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "wipeString" -> {
                    try {
                        val text = call.arguments as? String
                        WipeString.wipe(text)
                    } catch (_: Exception) {
                        // Swallow — wipe failures must not crash the app
                    } finally {
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
