plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "id.co.revive.re_v"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "id.co.revive.re_v"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // PLAT-02 fix: read release keystore from environment variables set in CI
            // Set KEYSTORE_PATH, KEY_ALIAS, KEY_PASSWORD, STORE_PASSWORD in CI secrets
            // See docs/remediation/MANUAL.md for keystore generation instructions
            val keystorePath = System.getenv("KEYSTORE_PATH")
            if (keystorePath != null && java.io.File(keystorePath).exists()) {
                signingConfigs.create("release") {
                    storeFile = java.io.File(keystorePath)
                    storePassword = System.getenv("STORE_PASSWORD") ?: ""
                    keyAlias = System.getenv("KEY_ALIAS") ?: ""
                    keyPassword = System.getenv("KEY_PASSWORD") ?: ""
                }
                signingConfig = signingConfigs.getByName("release")
            } else {
                // Local development fallback — debug signing only
                // DO NOT use this for Play Store uploads
                signingConfig = signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
