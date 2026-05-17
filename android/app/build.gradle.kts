import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.attendance.attendance_app"
    compileSdk = flutter.compileSdkVersion
    // Match Firebase / ML Kit plugins (required). keepDebugSymbols below protects face SDK .so.
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.attendance.attendance_app"
        // MobSF: avoid minSdk below API 29 (Android 10) for reasonable security updates.
        minSdk = maxOf(flutter.minSdkVersion, 29)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // KBY Face SDK ships ARM .so only (see facesdk_plugin/android/libs/facesdk.aar).
        ndk {
            abiFilters += listOf("armeabi-v7a", "arm64-v8a")
        }
    }

    packaging {
        jniLibs {
            // Extract .so on install — helps Face SDK load on some ARM devices.
            useLegacyPackaging = true
            keepDebugSymbols += "**/*.so"
        }
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = rootProject.file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // MobSF: ship with a release keystore when android/key.properties exists.
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

// facesdk_plugin ships native SDK as local .aar under the plugin; those cannot be
// implementation() inside the plugin library on AGP 8+. Link them into the app APK.
dependencies {
    implementation(
        fileTree(
            mapOf(
                "dir" to "${rootProject.projectDir}/../facesdk_plugin/android/libs",
                "include" to listOf("*.aar", "*.jar"),
            ),
        ),
    )
}
