// FIX: Import the necessary Java class
import java.util.Properties
import kotlin.text.toInt

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// Read the local.properties file to get the Flutter SDK version
val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    localPropertiesFile.inputStream().use { stream ->
        localProperties.load(stream)
    }
}

val flutterVersionCode = localProperties.getProperty("flutter.versionCode") ?: "1"
val flutterVersionName = localProperties.getProperty("flutter.versionName") ?: "1.0"

android {
    namespace = "com.bridge.app.bridge"
    compileSdk = 36 // It's common to hardcode this
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // --- FIX FOR DESUGARING ---
        isCoreLibraryDesugaringEnabled = true
        // --- END FIX ---
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }

    kotlinOptions {
        jvmTarget = "1.8"
    }

    defaultConfig {
        applicationId = "com.bridge.app.bridge"
        minSdk = flutter.minSdkVersion // Or flutter.minSdkVersion
        targetSdk = 36 // Or flutter.targetSdkVersion
        versionCode = flutterVersionCode.toInt()
        versionName = flutterVersionName
        multiDexEnabled = true // Enable multidex
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    // --- START: Packaging Options (For OkHttp/Coroutines) ---
    // Duplicate file errors ko rokne ke liye
    packagingOptions {
        exclude("META-INF/DEPENDENCIES")
        exclude("META-INF/LICENSE")
        exclude("META-INF/LICENSE.txt")
        exclude("META-INF/license.txt")
        exclude("META-INF/NOTICE")
        exclude("META-INF/NOTICE.txt")
        exclude("META-INF/notice.txt")
        exclude("META-INF/ASL2.0")
        exclude("META-INF/*.kotlin_module")
    }
    // --- END: Packaging Options ---
}

flutter {
    source = "../.."
}

dependencies {
    // --- FIX FOR DESUGARING ---
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
    // --- END FIX ---

    // --- START: SendActivity Dependencies ---
    // Coroutines (Background tasks ke liye)
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.7.3")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")

    // OkHttp (Networking library file send karne ke liye)
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    // --- END: SendActivity Dependencies ---
}

