// android/build.gradle.kts
// DÔLEŽITÉ: Toto je súbor na úrovni projektu!

plugins {
    id("com.android.application") version "8.7.3" apply false
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
    id("com.google.gms.google-services") version "4.4.1" apply false // VERZIA PLUGINU PRE FIREBASE
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}


// ✅ Kotlin JVM target: default 11, ale pre receive_sharing_intent dáme 1.8 (lebo má Java 1.8 natvrdo)
subprojects {
    val kotlinTarget = if (project.name == "receive_sharing_intent") "1.8" else "11"

    tasks.matching { it.name.startsWith("compile") && it.name.contains("Kotlin") }.configureEach {
        (this as org.jetbrains.kotlin.gradle.tasks.KotlinCompile).kotlinOptions.jvmTarget = kotlinTarget
    }
}

