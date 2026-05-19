plugins {
    id("com.android.application")
    id("com.google.gms.google-services") // Firebase/Google Services
    id("kotlin-android")
    // Flutter plugin must come after Android and Kotlin
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.sports"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    // Kotlin options - jvmTarget must be a string
    kotlinOptions {
        jvmTarget = "11"
    }

    defaultConfig {
        applicationId = "com.example.sports"
        // Use Kotlin DSL property assignment (not Groovy syntax)
        // Keep flutter.* variables if they are defined by the Flutter plugin.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // NOTE: removed any `minSdkVersion = ...` or `minSdkVersion 21` Groovy-style lines
    }

    buildTypes {
        release {
            // Use debug signing so `flutter run --release` works until you add a real keystore
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

// If you plan to use Firebase dependencies directly here (usually not needed;
// Flutter plugins handle them), you can use the BoM like this:
// dependencies {
//     implementation(platform("com.google.firebase:firebase-bom:33.5.1"))
//     implementation("com.google.firebase:firebase-analytics-ktx")
// }
