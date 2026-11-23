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

    // Automatically patch legacy proguard-android.txt in subproject build files before Gradle evaluates them
    try {
        val buildFile = project.buildFile
        if (buildFile.exists()) {
            val text = buildFile.readText()
            if (text.contains("proguard-android.txt")) {
                buildFile.writeText(text.replace("proguard-android.txt", "proguard-android-optimize.txt"))
            }
        }
    } catch (_: Exception) {}
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
