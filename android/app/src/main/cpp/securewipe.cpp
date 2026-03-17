#include <jni.h>
#include <stdint.h>
#include <string.h>

// ---------------------------------------------------------------------------
// secure_zero — volatile memset that the compiler cannot optimise away.
// Using a volatile pointer prevents dead-store elimination (DSE), which would
// otherwise remove the fill because the buffer is "not read afterwards."
// This is the same pattern used by OpenSSL (OPENSSL_cleanse) and mbedTLS.
// ---------------------------------------------------------------------------
static void secure_zero(void* ptr, size_t len) {
    volatile uint8_t* p = static_cast<volatile uint8_t*>(ptr);
    while (len--) {
        *p++ = 0;
    }
}

// ---------------------------------------------------------------------------
// nativeWipeBytes — zeroes a Java byte[] via JNI.
// We pin the array, fill it with zeros, then release with mode JNI_COMMIT
// to write the changes back into the JVM heap before freeing the pointer.
// ---------------------------------------------------------------------------
extern "C"
JNIEXPORT void JNICALL
Java_com_example_nk3_1zero_WipeString_nativeWipeBytes(
        JNIEnv* env,
        jobject /* thiz */,
        jbyteArray bytes) {
    if (bytes == nullptr) return;

    jsize len = env->GetArrayLength(bytes);
    if (len <= 0) return;

    jboolean isCopy = JNI_FALSE;
    jbyte* ptr = env->GetByteArrayElements(bytes, &isCopy);
    if (ptr == nullptr) return;

    secure_zero(ptr, static_cast<size_t>(len));

    // 0  = copy back AND free the buffer (ensures JVM heap is updated)
    env->ReleaseByteArrayElements(bytes, ptr, 0);
}

// ---------------------------------------------------------------------------
// nativeWipeCharArray — zeroes a Java char[] via JNI.
// ---------------------------------------------------------------------------
extern "C"
JNIEXPORT void JNICALL
Java_com_example_nk3_1zero_WipeString_nativeWipeCharArray(
        JNIEnv* env,
        jobject /* thiz */,
        jcharArray chars) {
    if (chars == nullptr) return;

    jsize len = env->GetArrayLength(chars);
    if (len <= 0) return;

    jboolean isCopy = JNI_FALSE;
    jchar* ptr = env->GetCharArrayElements(chars, &isCopy);
    if (ptr == nullptr) return;

    secure_zero(ptr, static_cast<size_t>(len) * sizeof(jchar));

    env->ReleaseCharArrayElements(chars, ptr, 0);
}
