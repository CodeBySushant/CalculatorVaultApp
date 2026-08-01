allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Standard Flutter build-directory redirect: all Gradle outputs go to the
// project-root /build folder, which is where the flutter tool looks for
// APKs/AABs. Without this, builds succeed but flutter run/install/build
// report "failed to produce" because outputs land in android/app/build.
val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    // Align every Flutter plugin's Android library module to compileSdk 36
    // (e.g. file_picker). plugins.withId is evaluation-order safe.
    plugins.withId("com.android.library") {
        extensions.configure<com.android.build.gradle.LibraryExtension> {
            compileSdk = 36
        }
    }
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
