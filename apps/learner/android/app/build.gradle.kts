plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android plugin.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseKeystorePath = providers.environmentVariable("VERBASEED_ANDROID_KEYSTORE_PATH").orNull
val releaseKeystorePassword = providers.environmentVariable("VERBASEED_ANDROID_KEYSTORE_PASSWORD").orNull
val releaseKeyAlias = providers.environmentVariable("VERBASEED_ANDROID_KEY_ALIAS").orNull
val releaseKeyPassword = providers.environmentVariable("VERBASEED_ANDROID_KEY_PASSWORD").orNull
val releaseSigningRequired = providers.environmentVariable("VERBASEED_REQUIRE_RELEASE_SIGNING")
    .orNull
    ?.equals("true", ignoreCase = true) == true
val releaseSigningValues = listOf(
    releaseKeystorePath,
    releaseKeystorePassword,
    releaseKeyAlias,
    releaseKeyPassword,
)
val configuredReleaseSigningValues = releaseSigningValues.count { !it.isNullOrBlank() }
val hasReleaseSigning = configuredReleaseSigningValues == releaseSigningValues.size

if (configuredReleaseSigningValues != 0 && !hasReleaseSigning) {
    throw GradleException(
        "Incomplete VerbaSeed Android release signing configuration. " +
            "Provide VERBASEED_ANDROID_KEYSTORE_PATH, " +
            "VERBASEED_ANDROID_KEYSTORE_PASSWORD, VERBASEED_ANDROID_KEY_ALIAS, " +
            "and VERBASEED_ANDROID_KEY_PASSWORD together.",
    )
}
if (releaseSigningRequired && !hasReleaseSigning) {
    throw GradleException(
        "Production Android signing is required, but no complete release signing configuration was supplied.",
    )
}

android {
    namespace = "io.github.octoteo.verbaseed"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "io.github.octoteo.verbaseed"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(releaseKeystorePath!!)
                storePassword = releaseKeystorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                logger.warn(
                    "VerbaSeed release build is using DEBUG signing because production " +
                        "signing variables are absent. This artifact is for local/CI validation only.",
                )
                signingConfigs.getByName("debug")
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

dependencies {
    // Bundled on-device model: recognizes both Chinese and Latin text without
    // Google Play model downloads or a network OCR service.
    implementation("com.google.mlkit:text-recognition-chinese:16.0.1")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
