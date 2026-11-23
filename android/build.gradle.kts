allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.google.gms:google-services:4.4.2")
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)

    afterEvaluate {
        if (plugins.hasPlugin("com.android.library") || plugins.hasPlugin("com.android.application")) {
            val android = extensions.findByName("android") as? com.android.build.gradle.BaseExtension
            android?.buildTypes?.findByName("release")?.let { release ->
                try {
                    val currentFiles = release.proguardFiles
                    val updatedFiles = currentFiles.map { file ->
                        if (file is java.io.File && file.name == "proguard-android.txt") {
                            android.getDefaultProguardFile("proguard-android-optimize.txt")
                        } else {
                            file
                        }
                    }
                    release.setProguardFiles(updatedFiles)
                } catch (_: Exception) {}
            }
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
