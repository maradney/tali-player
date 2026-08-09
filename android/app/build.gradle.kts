import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing details, kept out of the repository: android/key.properties
// holds the keystore path and passwords and is gitignored, as is the .jks
// itself. See tool/ANDROID_SIGNING.md for how to create them.
//
// When the file is absent - a fresh clone, or a machine that only ever builds
// debug - the release build falls back to the debug key below rather than
// failing. That keeps `flutter build apk --release` working for local testing,
// at the cost of producing an artifact that must not be distributed; the
// fallback logs a warning saying exactly that.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val hasReleaseKeystore = keystoreProperties.getProperty("storeFile") != null

android {
    namespace = "io.github.maradney.tali"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Permanent once published — Play identifies the app by this and it can
        // never be changed afterwards. Deliberately not derived from appName in
        // app_info.dart: renaming the app must not orphan existing installs.
        //
        // io.github.<username> rather than a reverse domain, because there is no
        // maradney.com to reverse. Play never verifies domain ownership, but a
        // GitHub namespace is one the author demonstrably controls, which is the
        // convention F-Droid and Maven Central point at for exactly this case.
        applicationId = "io.github.maradney.tali"
        // Flutter's default (24) already clears the highest floor our plugins
        // impose (flutter_secure_storage 10.x needs 23), so we track the SDK's
        // tested default rather than pinning a number that would silently drift.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseKeystore) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                // Debug-signed: fine for measuring size or testing a release
                // build locally, never for handing to anyone. An app installed
                // with this key cannot later be updated by a properly signed
                // build - Android refuses the upgrade - so shipping one would
                // strand every user who installed it.
                signingConfig = signingConfigs.getByName("debug")
                // println, not logger.warn: Flutter runs Gradle quietly enough
                // that WARN-level output is swallowed, which would leave this
                // safety net silently doing nothing. Verified by building.
                println(
                    "WARNING: no android/key.properties - signing the release " +
                        "build with the DEBUG key. Do not distribute this APK. " +
                        "See tool/ANDROID_SIGNING.md."
                )
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
