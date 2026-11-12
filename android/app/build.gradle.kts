// Imported rather than written as java.io.File: inside android {} the name
// `java` resolves to Gradle's java{} extension, so the qualified form fails
// with "Unresolved reference 'io'". Imports must precede everything else in
// a .kts file, so this sits above the plugins block.
import java.io.File as JavaFile

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

    // Required for resValue(...) in productFlavors — the per-flavor app_name.
    // AGP disables custom resource values by default.
    buildFeatures {
        resValues = true
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

    // Two apps ship from this one codebase and must coexist on a phone:
    //   customer   — id.co.revive.re_v        (client / workshop app)
    //   respondent — id.co.revive.re_v_learning (AI Learning, AI training only)
    // Each flavor carries its own app label so they are distinguishable.
    flavorDimensions += "app"
    productFlavors {
        create("customer") {
            dimension = "app"
            applicationId = "id.co.revive.re_v"
            resValue("string", "app_name", "Revive")
        }
        create("respondent") {
            dimension = "app"
            applicationId = "id.co.revive.re_v_learning"
            resValue("string", "app_name", "re-V AI Learning")
        }
    }

    buildTypes {
        release {
            // PLAT-02 fix: read release keystore from environment variables set in CI
            // Set KEYSTORE_PATH, KEY_ALIAS, KEY_PASSWORD, STORE_PASSWORD in CI secrets
            // See docs/remediation/MANUAL.md for keystore generation instructions
            val keystorePath = System.getenv("KEYSTORE_PATH")
            if (keystorePath != null && JavaFile(keystorePath).isFile) {
                signingConfigs.create("release") {
                    storeFile = JavaFile(keystorePath)
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
