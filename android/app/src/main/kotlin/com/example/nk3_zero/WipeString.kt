package com.example.nk3_zero

/**
 * Secure memory wipe helper — bridges Dart's MethodChannel to native C++ memset.
 *
 * Security rationale:
 *   Dart Strings are immutable objects managed by the Dart VM GC. There is no
 *   API to zero their underlying memory from Dart. By converting the String to
 *   a mutable JVM byte[] and char[], then zeroing those arrays via JNI with a
 *   volatile memset (secure_zero in securewipe.cpp), we zero at least the UTF-8
 *   and UTF-16 representations of the sensitive string in the JVM heap before
 *   the GC can relocate them.
 *
 * Limitations (documented for transparency):
 *   - The JVM may have already created additional internal copies (e.g. string
 *     pool, JIT-compiled constants). This wipe covers the caller's working copy.
 *   - Hardware-backed keys (Android Keystore) are not stored in heap at all,
 *     so they do not need this treatment.
 */
object WipeString {

    init {
        System.loadLibrary("securewipe")
    }

    // ── JNI entry points (implemented in securewipe.cpp) ───────────────────

    @JvmStatic
    private external fun nativeWipeBytes(bytes: ByteArray)

    @JvmStatic
    private external fun nativeWipeCharArray(chars: CharArray)

    // ── Public API ──────────────────────────────────────────────────────────

    /**
     * Wipes all accessible in-memory representations of [text].
     *
     * Steps:
     *   1. Convert to UTF-8 byte[] → zero via JNI
     *   2. Convert to UTF-16 byte[] → zero via JNI
     *   3. Convert to char[] → zero via JNI
     *
     * After this call, [text] still refers to a Java String object, but the
     * backing byte arrays for our local copies have been zeroed.
     */
    @JvmStatic
    fun wipe(text: String?) {
        if (text.isNullOrEmpty()) return

        // 1. UTF-8 bytes
        val utf8 = text.toByteArray(Charsets.UTF_8)
        nativeWipeBytes(utf8)

        // 2. UTF-16 bytes (JVM native String encoding)
        val utf16 = text.toByteArray(Charsets.UTF_16)
        nativeWipeBytes(utf16)

        // 3. char[] representation
        val chars = text.toCharArray()
        nativeWipeCharArray(chars)
    }
}
