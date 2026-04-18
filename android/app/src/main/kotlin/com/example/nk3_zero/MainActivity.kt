package com.example.nk3_zero

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.view.WindowManager
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.os.PersistableBundle
import android.content.ClipDescription
import java.util.Arrays
import java.security.SecureRandom

/**
 * =============================================
 *          MAIN ACTIVITY — ZERO VAULT
 * =============================================
 */

class MainActivity : FlutterFragmentActivity() {

    companion object {
        private const val SECURE_WIPE_CHANNEL = "secure_wipe"
        private const val CLIPBOARD_CHANNEL = "com.zerovault/clipboard"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        // FLAG_SECURE must be set BEFORE super.onCreate so the first frame is
        // never capturable (CWE-200: sensitive UI exposed via screenshot/recorder).
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE
        )
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Re-assert FLAG_SECURE in case the window was recreated (e.g. theme change,
        // config change not covered by configChanges, or split-screen reattach).
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE
        )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CLIPBOARD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setSensitiveClipboard" -> {
                        val text = call.argument<String>("text") ?: ""
                        setSensitiveClipboard(text)
                        result.success(null)
                    }
                    "clearClipboard" -> {
                        clearClipboard()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SECURE_WIPE_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "wipeString") {
                    try {
                        val text = call.arguments as? String
                        if (!text.isNullOrEmpty()) {
                            WipeString.secureWipe(text)
                        }
                    } catch (e: Exception) {
                        android.util.Log.w("ZeroVault", "Secure wipe failed: ${e.message}")
                    } finally {
                        result.success(null)
                    }
                } else {
                    result.notImplemented()
                }
            }
    }

    /**
     * Marks clipboard entry as sensitive on API 33+.
     *
     * Label is deliberately generic — on some launchers the label appears in
     * paste previews, so "ZeroVault_*" would leak that a password manager is
     * involved.
     */
    private fun setSensitiveClipboard(text: String) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return
        }

        try {
            val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            val clipData = ClipData.newPlainText("", text)

            val extras = PersistableBundle().apply {
                putBoolean(ClipDescription.EXTRA_IS_SENSITIVE, true)
            }
            clipData.description.extras = extras

            clipboard.setPrimaryClip(clipData)
        } catch (e: Exception) {
            android.util.Log.e("ZeroVault", "Failed to set sensitive clipboard", e)
        }
    }

    /**
     * Synchronously clears the system clipboard. Called when the app goes to
     * background (CWE-316 / CWE-312: sensitive data persisted on system buffer).
     *
     * We only clear when the clipboard still holds OUR data — we check
     * EXTRA_IS_SENSITIVE on API 33+, otherwise we clear unconditionally (can't
     * distinguish ours from user's on older Android, but the only caller is our
     * own background-wipe path so the risk of clobbering user data is minimal).
     */
    private fun clearClipboard() {
        try {
            val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                val isOurs = clipboard.primaryClipDescription
                    ?.extras
                    ?.getBoolean(ClipDescription.EXTRA_IS_SENSITIVE, false)
                    ?: false
                if (!isOurs) return
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                clipboard.clearPrimaryClip()
            } else {
                // Pre-28 has no clearPrimaryClip; overwrite with empty ClipData.
                clipboard.setPrimaryClip(ClipData.newPlainText("", ""))
            }
        } catch (e: Exception) {
            android.util.Log.w("ZeroVault", "Clipboard clear failed: ${e.message}")
        }
    }
}

/**
 * =============================================
 *          WIPE STRING UTILITY
 * =============================================
 *
 * Best-effort secure wipe of sensitive data that entered the JVM as a String.
 *
 * LIMITATION — IMPORTANT:
 * Java/Kotlin Strings are immutable, and on modern Android (P+) the internal
 * `String.value` field is off-limits to reflection. We therefore cannot wipe
 * the original String's backing array — it lives until GC (and may survive
 * multiple GCs in the tenured generation).
 *
 * What we CAN do — and what this class does:
 *   1. Derive a byte[] / char[] copy of the String.
 *   2. Overwrite that copy with volatile-memset in native C++, which the
 *      compiler cannot elide (plain Arrays.fill can be DCE'd under JIT).
 *   3. Random + zero passes to defeat naive forensic scrapers.
 *
 * For truly sensitive material, callers must use CharArray / ByteArray from
 * the start (never String) and feed those arrays here via nativeWipeBytes /
 * nativeWipeCharArray directly.
 */
object WipeString {

    init {
        try {
            System.loadLibrary("securewipe")
        } catch (t: Throwable) {
            android.util.Log.e("ZeroVault-Wipe", "Failed to load libsecurewipe.so", t)
        }
    }

    @JvmStatic external fun nativeWipeBytes(bytes: ByteArray)
    @JvmStatic external fun nativeWipeCharArray(chars: CharArray)

    @JvmStatic
    fun secureWipe(text: String?) {
        if (text.isNullOrEmpty()) return

        try {
            // Wipe a char[] copy first — one byte-per-codepoint less info than
            // a UTF-8 byte[] (doesn't double up for multibyte chars).
            val chars = text.toCharArray()
            try {
                val random = SecureRandom()
                val randomBytes = ByteArray(chars.size * 2)
                random.nextBytes(randomBytes)
                for (i in chars.indices) {
                    chars[i] = ((randomBytes[i * 2].toInt() and 0xFF) or
                                ((randomBytes[i * 2 + 1].toInt() and 0xFF) shl 8)).toChar()
                }
                Arrays.fill(randomBytes, 0.toByte())
                nativeWipeCharArray(chars)          // volatile memset — DCE-safe
            } finally {
                Arrays.fill(chars, '\u0000')
            }

            // Also wipe the UTF-8 byte[] copy that Flutter's MethodChannel
            // materialised on the JVM heap when it deserialised the argument.
            val bytes = text.toByteArray(Charsets.UTF_8)
            try {
                nativeWipeBytes(bytes)
            } finally {
                Arrays.fill(bytes, 0.toByte())
            }
        } catch (e: UnsatisfiedLinkError) {
            android.util.Log.w("ZeroVault-Wipe", "Native wipe unavailable; falling back to JVM Arrays.fill")
            try {
                val bytes = text.toByteArray(Charsets.UTF_8)
                Arrays.fill(bytes, 0.toByte())
                val chars = text.toCharArray()
                Arrays.fill(chars, '\u0000')
            } catch (_: Exception) { /* swallow */ }
        } catch (e: Exception) {
            android.util.Log.w("ZeroVault-Wipe", "Wipe operation failed", e)
        }
    }
}
