plugins {
    id("com.android.application")
    id("kotlin-android")
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

import java.util.Properties
import java.io.FileInputStream

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

fun Properties.keystoreProp(name: String): String? {
    val value = getProperty(name)?.trim().orEmpty()
    if (value.isNotEmpty()) {
        return value
    }
    // Some editors write UTF-8 BOM on the first key.
    val bomName = "\uFEFF$name"
    val bomValue = getProperty(bomName)?.trim().orEmpty()
    return bomValue.takeIf { it.isNotEmpty() }
}

val releaseStoreFile = keystoreProperties.keystoreProp("storeFile")
    ?.let { rootProject.file(it) }
val hasReleaseKeystore = releaseStoreFile?.exists() == true &&
    keystoreProperties.keystoreProp("storePassword") != null &&
    keystoreProperties.keystoreProp("keyPassword") != null &&
    keystoreProperties.keystoreProp("keyAlias") != null

android {
    namespace = "com.vanmarket.rider.van3"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties.keystoreProp("keyAlias")
                keyPassword = keystoreProperties.keystoreProp("keyPassword")
                storeFile = releaseStoreFile
                storePassword = keystoreProperties.keystoreProp("storePassword")
            }
        }
    }

    defaultConfig {
        applicationId = "van3.rider.com"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    // Strip Agora extensions we don't use (voice-only calls).
    // Removes ~30+ MB per ABI from the final APK.
    packaging {
        jniLibs {
            excludes += listOf(
                "**/libagora_lip_sync_extension.so",
                "**/libagora_spatial_audio_extension.so",
                "**/libagora_clear_vision_extension.so",
                "**/libagora_face_capture_extension.so",
                "**/libagora_segmentation_extension.so",
                "**/libagora_audio_beauty_extension.so",
                "**/libagora_content_inspect_extension.so",
                "**/libagora_face_detection_extension.so",
                "**/libagora_video_quality_analyzer_extension.so",
                "**/libagora_video_av1_encoder_extension.so",
                "**/libagora_video_av1_decoder_extension.so",
                "**/libagora_video_encoder_extension.so",
                "**/libagora_video_decoder_extension.so",
                "**/libagora_screen_capture_extension.so"
                // NOTE: libagora-ffmpeg.so MUST stay bundled — it is loaded
                // as a dynamic dependency of libagora-rtc-sdk.so. Removing it
                // causes UnsatisfiedLinkError at startup whenever the Agora
                // plugin tries to load (calls crash before ringing).
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11)
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("com.google.firebase:firebase-messaging-ktx:24.1.0")
}
