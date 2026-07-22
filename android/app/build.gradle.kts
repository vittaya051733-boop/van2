import java.util.Properties

plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "van.merchant"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    val localProperties = Properties()
    val localPropertiesFile = rootProject.file("local.properties")
    if (localPropertiesFile.exists()) {
        localPropertiesFile.inputStream().use { localProperties.load(it) }
    }
    val useVan1MapsIdentity =
        (project.findProperty("useVan1MapsIdentity") as String?) == "true" ||
            localProperties.getProperty("useVan1MapsIdentity", "false") == "true"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // Van2.com for production (side-by-side with van1). Emulator dev can set
        // useVan1MapsIdentity=true in android/local.properties to reuse van1 Maps SDK key.
        applicationId = if (useVan1MapsIdentity) "van.merchant" else "Van2.com"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation(platform("com.google.firebase:firebase-bom:33.5.1"))
    implementation("com.google.firebase:firebase-messaging-ktx:24.1.0")
}
