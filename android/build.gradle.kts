allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

subprojects {
    project.evaluationDependsOn(":app")

    // Align every Flutter plugin's Android module to compileSdk 36 so
    // modules that ship with an older compileSdk (e.g. file_picker) build
    // cleanly against the app's toolchain.
    afterEvaluate {
        extensions.findByName("android")?.let { ext ->
            when (ext) {
                is com.android.build.gradle.LibraryExtension -> ext.compileSdk = 36
                is com.android.build.gradle.AppExtension -> ext.compileSdkVersion(36)
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
