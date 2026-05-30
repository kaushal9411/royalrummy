import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// Load local.properties — never committed to git, safe for secrets
val localProps = Properties().also { props ->
    val f = rootProject.file("local.properties")
    if (f.exists()) f.inputStream().use { props.load(it) }
}

fun localProp(key: String): String? = System.getenv(key) ?: localProps.getProperty(key)

android {
    namespace = "com.lakadiya.lakadiya"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.lakadiya.lakadiya"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 23  // flutter_secure_storage v9.x requires API 23+ for encryptedSharedPreferences
        targetSdk = 34
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val ksFile = localProp("KEYSTORE_FILE")
            val ksPass = localProp("KEYSTORE_PASSWORD")
            val kAlias = localProp("KEY_ALIAS")
            val kPass  = localProp("KEY_PASSWORD")
            if (ksFile != null) {
                storeFile     = file(ksFile)
                storePassword = ksPass
                this.keyAlias = kAlias
                keyPassword   = kPass
            }
        }
    }

    buildTypes {
        release {
            val rel = signingConfigs.getByName("release")
            // Use release keystore if configured, otherwise fall back to debug for local builds
            signingConfig = if (rel.storeFile != null) rel else signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}

flutter {
    source = "../.."
}
