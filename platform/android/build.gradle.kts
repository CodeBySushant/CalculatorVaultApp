allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// --- Build output redirect (required on this setup so `flutter run` can
// locate the produced APK). Do not remove. ---
rootProject.layout.buildDirectory.set(file("${rootProject.projectDir}/../build"))

subprojects {
    layout.buildDirectory.set(file("${rootProject.projectDir}/../build/${project.name}"))
    project.evaluationDependsOn(":app")

    // --- Force every plugin module to compile against API 36. Some plugins
    // (e.g. file_picker) declare an older compileSdk than their transitive
    // dependencies require, which fails the AAR metadata check. This aligns
    // them all to 36. ---
    afterEvaluate {
        val androidExtension = extensions.findByName("android")
        if (androidExtension is com.android.build.gradle.BaseExtension) {
            androidExtension.compileSdkVersion(36)
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
