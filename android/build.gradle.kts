allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

subprojects {
    // Align every Flutter plugin's Android library module to compileSdk 36
    // (e.g. file_picker). plugins.withId is evaluation-order safe, unlike
    // afterEvaluate, which fails once :app is already evaluated.
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
