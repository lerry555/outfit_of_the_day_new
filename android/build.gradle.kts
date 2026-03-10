// android/build.gradle.kts

import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

plugins {
    id("com.android.application") version "8.7.3" apply false
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
    id("com.google.gms.google-services") version "4.4.1" apply false
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
}

/**
 * ✅ FIX: Kotlin JVM target musí sedieť s Java targetom v každom module.
 * - receive_sharing_intent má natvrdo Java 1.8 -> Kotlin MUSÍ byť 1.8
 * - zvyšok držíme na 11, lebo app má Java 11
 *
 * Dôležité: NEROBÍME žiadne "sourceCompatibility" hacky (to ti spôsobovalo "finalized").
 * Iba nastavíme KotlinCompile jvmTarget.
 */
subprojects {
    tasks.withType<KotlinCompile>().configureEach {
        val target = if (project.name == "receive_sharing_intent") "1.8" else "11"
        kotlinOptions {
            jvmTarget = target
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}