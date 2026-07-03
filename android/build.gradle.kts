allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// --- Build output redirect (required so `flutter run` can find the APK). ---
rootProject.layout.buildDirectory.set(file("${rootProject.projectDir}/../build"))

subprojects {
    layout.buildDirectory.set(file("${rootProject.projectDir}/../build/${project.name}"))
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
