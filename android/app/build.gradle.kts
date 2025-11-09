// android/app/build.gradle.kts

import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// โหลด key.properties
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.example.jewelry_shop" // 👈 แก้เป็นของคุณถ้ามี
    compileSdk = 36

    defaultConfig {
        applicationId = "com.example.jewelry_shop" // 👈 แก้เป็นของคุณ
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = 1
        versionName = "1.0.0"
    }

    // ✅ ตั้ง signing สำหรับ release
    signingConfigs {
        create("release") {
            // ถ้า key.properties ไม่มี หรือพิมพ์ผิด จะเป็นค่าว่าง (กันไม่ให้ build พังตอน debug)
            storeFile = keystoreProperties["storeFile"]?.let { file(it as String) }
            storePassword = keystoreProperties["storePassword"] as String? ?: ""
            keyAlias = keystoreProperties["keyAlias"] as String? ?: ""
            keyPassword = keystoreProperties["keyPassword"] as String? ?: ""
        }
    }

    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = "17"
    }
}

// ให้ Flutter plugin รู้ path โปรเจกต์
flutter {
    source = "../.."
}
dependencies {
    // สำหรับ flutter_local_notifications ที่ต้องใช้ desugaring
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}