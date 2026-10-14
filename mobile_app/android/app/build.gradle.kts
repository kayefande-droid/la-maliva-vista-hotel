import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: when key.properties + the keystore exist (developer machine
// or CI restore from secrets), release builds are store-signed; otherwise we
// fall back to the debug keystore so local sideload testing still works.
val releaseProps = Properties()
val releasePropsFile = rootProject.file("key.properties")
if (releasePropsFile.exists()) {
    releasePropsFile.inputStream().use { releaseProps.load(it) }
}

android {
    namespace = "com.lamaliva.lamaliva_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.lamaliva.lamaliva_app"
        // Android 8.0+ is the advertised floor (site/README). Pin it so it can
        // never silently drop below the flutter_local_notifications plugin's
        // own minimum (API 24) or rise above what we promise guests.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    signingConfigs {
        create("release") {
            if (releasePropsFile.exists()) {
                keyAlias = releaseProps.getProperty("keyAlias")
                keyPassword = releaseProps.getProperty("keyPassword")
                storeFile = file(releaseProps.getProperty("storeFile"))
                storePassword = releaseProps.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // Real signing config when key.properties is present (CI/dev);
            // otherwise the debug keys, so `flutter run --release` still works.
            signingConfig = if (releasePropsFile.exists())
                signingConfigs.getByName("release")
            else
                signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // Required by flutter_local_notifications (core library desugaring)
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
