import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val videoAppBuild = providers.environmentVariable("VIDEO_MUSIC_BUILD").orNull == "1"
val videoSigning = Properties().apply {
    if (videoAppBuild) {
        val propertiesPath = providers.environmentVariable("VIDEO_MUSIC_SIGNING_PROPERTIES").orNull
            ?: error("VIDEO_MUSIC_SIGNING_PROPERTIES must point to the video app signing configuration")
        file(propertiesPath).inputStream().use { load(it) }
    }
}

android {
    namespace = "com.mconnect.mconnect"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = if (videoAppBuild) "app.videomusic.player" else "com.mconnect.mconnect"
        manifestPlaceholders["appLabel"] = if (videoAppBuild) "悦音音乐" else "Mconnect"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = if (videoAppBuild) 6 else flutter.versionCode
        versionName = if (videoAppBuild) "0.3.3" else flutter.versionName
    }

    if (videoAppBuild) {
        signingConfigs.create("videoRelease") {
            storeFile = file(videoSigning.getProperty("storeFile"))
            storePassword = videoSigning.getProperty("storePassword")
            keyAlias = videoSigning.getProperty("keyAlias")
            keyPassword = videoSigning.getProperty("keyPassword")
            storeType = "PKCS12"
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (videoAppBuild) "videoRelease" else "debug")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.documentfile:documentfile:1.0.1")
    implementation("androidx.javascriptengine:javascriptengine:1.1.1")
}
