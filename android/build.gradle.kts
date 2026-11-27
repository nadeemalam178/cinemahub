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
        .dir("../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
    afterEvaluate {
        if (project.plugins.hasPlugin("com.android.library")) {
            val androidExt = project.extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)
            androidExt?.buildTypes?.all {
                val updatedFiles = proguardFiles.map { file ->
                    if (file.name == "proguard-android.txt") {
                        androidExt.getDefaultProguardFile("proguard-android-optimize.txt")
                    } else {
                        file
                    }
                }
                setProguardFiles(updatedFiles)
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
