plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services") // ✅ Firebase plugin
}

android {
    namespace = "com.linguacall.linguacall"
    compileSdk = 36   // Firebase plugins may require higher SDK

    ndkVersion = flutter.ndkVersion

    defaultConfig {
        applicationId = "com.linguacall.linguacall"
        minSdk = flutter.minSdkVersion   // 🔥 Firebase Auth/Firestore require minSdk 23+
        targetSdk = 35
        versionCode = 1
        versionName = "1.0"

        multiDexEnabled = true

        // Reduce APK size + avoid out-of-disk during native lib packaging.
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }
    
    buildTypes {
        release {
            isMinifyEnabled = false
            isShrinkResources = false   // 🔥 ADD THIS (FIX)
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.multidex:multidex:2.0.1")
}
