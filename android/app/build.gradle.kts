plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.irisvision"
    // FIX: was 36 -- not required by camera/sqflite/speech_to_text, and risks
    // "failed to find target android-36" on machines without that SDK platform
    // installed (e.g. your supervisor's laptop, lab PCs). Matches targetSdk.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.example.irisvision"
        minSdk = 24
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"

        // Memastikan pustaka C++ (.so) disertakan untuk seni bina cip ARM ZTE
        ndk {
            abiFilters.addAll(setOf("armeabi-v7a", "arm64-v8a", "x86_64"))
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

// FIX: removed manual org.tensorflow:tensorflow-lite / tensorflow-lite-gpu
// dependencies. tflite_flutter 0.10.1 already bundles and manages its own
// TensorFlow Lite native library internally -- adding your own version here
// risks two different native TFLite runtimes shipping in the same APK,
// which can cause exactly the kind of flaky, inconsistent behavior you're
// seeing across runs. If you ever need the GPU delegate specifically, wire
// it up through tflite_flutter's own GpuDelegate API in Dart, not here.

flutter {
    source = "../.."
}