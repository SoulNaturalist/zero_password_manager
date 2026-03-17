# Keep WipeString JNI methods so the linker can resolve them at runtime.
-keepclasseswithmembernames class com.example.nk3_zero.WipeString {
    native <methods>;
    private static native <methods>;
}

# Keep MainActivity and WipeString from being renamed/removed.
-keep class com.example.nk3_zero.MainActivity { *; }
-keep class com.example.nk3_zero.WipeString { *; }
