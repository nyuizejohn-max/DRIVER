import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}


val localProperties = Properties().apply {
    val localPropertiesFile = rootProject.file("local.properties")
    if (localPropertiesFile.exists()) {
        localPropertiesFile.inputStream().use { load(it) }
    }
}
val backgroundGeolocation = project(":flutter_background_geolocation")
apply {
    from("${backgroundGeolocation.projectDir}/background_geolocation.gradle")
}

android {
    namespace = "com.wheattaste.driver_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.wheattaste.driver_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
       manifestPlaceholders["MAPS_API_KEY"] =
    System.getenv("MAPS_API_KEY")
        ?: localProperties.getProperty("MAPS_API_KEY", "")

manifestPlaceholders["TRANSISTOR_LICENSE_KEY"] =
    System.getenv("TRANSISTOR_LICENSE_KEY")
        ?: localProperties.getProperty("TRANSISTOR_LICENSE_KEY", "")
    }
        signingConfigs {
        create("driverDebug") {
            storeFile = file("driver-debug.keystore")
            storePassword = System.getenv("DRIVER_KEYSTORE_PASSWORD")
                ?: localProperties.getProperty("DRIVER_KEYSTORE_PASSWORD", "")
            keyAlias = "driverdebug"
            keyPassword = System.getenv("DRIVER_KEYSTORE_PASSWORD")
                ?: localProperties.getProperty("DRIVER_KEYSTORE_PASSWORD", "")
        }
    }

        buildTypes {
        debug {
            signingConfig = signingConfigs.getByName("driverDebug")
        }

        release {
            signingConfig = signingConfigs.getByName("driverDebug")
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
