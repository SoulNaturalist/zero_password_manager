plugins {
    id("com.android.application")
    id("kotlin-android")
    // Flutter Gradle plugin must come last
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.nk3_zero"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.example.nk3_zero"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // ── NDK / JNI ──────────────────────────────────────────────────────
        externalNativeBuild {
            cmake {
                // Pass -DANDROID to the C++ compiler
                cppFlags += "-std=c++17"
                // Build for all common ABIs
                abiFilters += setOf("arm64-v8a", "armeabi-v7a", "x86_64")
            }
        }
    }

    // ── NDK build ──────────────────────────────────────────────────────────
    externalNativeBuild {
        cmake {
            path = file("CMakeLists.txt")
            version = "3.18.1"
        }
    }

    buildTypes {
        release {
            // Minification — keep native method names so JNI lookup works
            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
