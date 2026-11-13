import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

android {
    namespace = "com.quietud.cite.ai_bible_cite_meditation"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    androidResources {
        noCompress += listOf("onnx", "bin", "db", "json")
    }

    defaultConfig {
        applicationId = "com.quietud.cite.ai_bible_cite_meditation"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                val storePath = keystoreProperties.getProperty("storeFile")
                    ?: error("Falta 'storeFile' en android/key.properties")
                val resolvedStore = listOf(file(storePath), rootProject.file(storePath))
                    .firstOrNull { it.exists() } ?: file(storePath)
                storeFile = resolvedStore
                storePassword = keystoreProperties.getProperty("storePassword")
                    ?: error("Falta 'storePassword' en android/key.properties")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                    ?: error("Falta 'keyAlias' en android/key.properties")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                    ?: error("Falta 'keyPassword' en android/key.properties")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
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
