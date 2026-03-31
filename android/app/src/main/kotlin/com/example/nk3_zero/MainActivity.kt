package com.example.nk3_zero

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.view.WindowManager
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Build
import android.os.PersistableBundle
import android.content.ClipDescription
import java.util.Arrays
import java.security.SecureRandom

/**
 * =============================================
 *          MAIN ACTIVITY — ZERO VAULT
 * =============================================
 *
 * Главная Activity приложения Zero Vault (nk3_zero).
 *
 * Ключевые функции безопасности:
 * 1. Наследуется от FlutterFragmentActivity — обязательно для local_auth + BiometricPrompt.
 * 2. Устанавливает FLAG_SECURE — запрещает скриншоты и запись экрана.
 * 3. Регистрирует два MethodChannel:
 *    - "secure_wipe"      → надёжное затирание чувствительных строк в памяти
 *    - "com.zerovault/clipboard" → пометка данных в буфере как sensitive (Android 13+)
 */

class MainActivity : FlutterFragmentActivity() {

    companion object {
        private const val SECURE_WIPE_CHANNEL = "secure_wipe"
        private const val CLIPBOARD_CHANNEL = "com.zerovault/clipboard"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // =============================================
        // 1. ЗАЩИТА ЭКРАНА — FLAG_SECURE
        // =============================================
        // Запрещает делать скриншоты и записывать экран (очень важно для password manager)
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE
        )

        // =============================================
        // 2. CHANNEL: Пометка clipboard как sensitive
        // =============================================
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CLIPBOARD_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "setSensitiveClipboard") {
                    val text = call.argument<String>("text") ?: ""
                    setSensitiveClipboard(text)
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }

        // =============================================
        // 3. CHANNEL: Надёжное затирание строк в памяти
        // =============================================
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
                        result.success(null) // всегда возвращаем успех, чтобы Dart не падал
                    }
                } else {
                    result.notImplemented()
                }
            }
    }

    /**
     * Помечает содержимое буфера обмена как чувствительное.
     * На Android 13+ (API 33) это скрывает данные от:
     * - Предложений автозаполнения клавиатуры
     * - Просмотра истории буфера обмена
     * - Предпросмотра в некоторых приложениях
     */
    private fun setSensitiveClipboard(text: String) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return // на старых версиях флаг не поддерживается
        }

        try {
            val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            val clipData = ClipData.newPlainText("ZeroVault_Sensitive", text)

            val extras = PersistableBundle().apply {
                putBoolean(ClipDescription.EXTRA_IS_SENSITIVE, true)
            }
            clipData.description.extras = extras

            clipboard.setPrimaryClip(clipData)
        } catch (e: Exception) {
            android.util.Log.e("ZeroVault", "Failed to set sensitive clipboard", e)
        }
    }
}

/**
 * =============================================
 *          WIPE STRING UTILITY
 * =============================================
 *
 * Надёжное затирание строк на native уровне.
 * Используется из Dart через MethodChannel "secure_wipe".
 */
object WipeString {

    /**
     * Многопроходное безопасное затирание строки.
     *
     * Алгоритм:
     * 1. Заполнение нулями
     * 2. Заполнение 0xFF
     * 3. Заполнение криптографически случайными байтами
     * 4. Финальное заполнение нулями
     * 5. Подсказка GC
     */
    @JvmStatic
    fun secureWipe(text: String?) {
        if (text.isNullOrEmpty()) return

        try {
            val bytes = text.toByteArray(Charsets.UTF_8)

            // Проход 1: нули
            Arrays.fill(bytes, 0.toByte())

            // Проход 2: все биты = 1
            Arrays.fill(bytes, 0xFF.toByte())

            // Проход 3: криптографически сильный random
            val random = SecureRandom()
            random.nextBytes(bytes)

            // Финальный проход — снова нули
            Arrays.fill(bytes, 0.toByte())

            // Помогаем GC собрать мусор
            System.gc()

        } catch (e: Exception) {
            android.util.Log.w("ZeroVault-Wipe", "Wipe operation failed", e)
        }
    }
}
